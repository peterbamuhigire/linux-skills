#!/usr/bin/env bash
#: Title:       sk-update-all-repos
#: Synopsis:    sk-update-all-repos [--yes] [--all|--repo <name>|--dry-run]
#: Description: Pull every registered git repo on this server. Supports an
#:              interactive menu (human use) and non-interactive --all / --repo
#:              flags (Claude Code / cron use). Runs `git reset --hard` before
#:              pulling — local changes are destroyed. Optional per-repo
#:              post-pull build step (e.g. `npm run build`).
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.2.0

# =============================================================================
# 1. Library + safety
# =============================================================================
set -uo pipefail

SK_LIB="/usr/local/lib/linux-skills/common.sh"
if [[ ! -f "$SK_LIB" ]]; then
    _SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SK_LIB="${_SD}/lib/common.sh"
fi
# shellcheck source=/dev/null
source "$SK_LIB" || { echo "FATAL: cannot source common.sh" >&2; exit 5; }

# =============================================================================
# 2. Defaults
# =============================================================================
SCRIPT_VERSION="0.2.0"

# Repo registry lives at /etc/linux-skills/repos.conf
# Format: "Name|Path|post_command" — one per line, # for comments.
REPO_REGISTRY="${REPO_REGISTRY:-/etc/linux-skills/repos.conf}"

SELECT_ALL=0
SELECTED_REPO=""
REPO_LIST=()

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-update-all-repos [OPTIONS]

Pull every registered git repo on this server.

Reads /etc/linux-skills/repos.conf with lines of the form:
    Name|/path/to/repo|optional post-pull command chain

Interactive by default — shows a numbered menu. Use flags for cron or
Claude Code invocation.

WARNING: runs `git reset --hard` and `git clean -fd` before pulling.
Local changes in tracked files are destroyed. Untracked files are removed.

POST-PULL COMMANDS:
    The third registry field is optional. It supports a constrained `&&`
    command chain such as:
        npm install --production && npm run build
    Each command is tokenized and executed directly — no shell evaluation,
    pipes, redirects, command substitution, or inline environment assignment.
    For complex logic, point the field at a checked-in executable script.

DECISION FLAGS (one is required under --yes):
    --all                       Update every registered repo
    --repo <name>               Update one repo by its registered Name

STANDARD FLAGS:
    -h, --help                  Show this help and exit
        --version               Print version
    -y, --yes                   Non-interactive mode
    -n, --dry-run               Print what would happen, change nothing
        --log                   Tee output to /var/log/linux-skills/
    -v, --verbose               Extra diagnostic output

EXIT CODES:
    0  all updates succeeded
    1  one or more updates failed
    2  usage/flag error
    3  registry file missing

EXAMPLES:
    sudo sk-update-all-repos                      # interactive menu
    sudo sk-update-all-repos --yes --all          # cron: update everything
    sudo sk-update-all-repos --yes --repo "My Site"

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

load_registry() {
    if [[ ! -f "$REPO_REGISTRY" ]]; then
        die "registry missing: $REPO_REGISTRY (create it with lines: Name|Path|post_command)" 3
    fi
    REPO_LIST=()
    while IFS= read -r line; do
        # Skip comments and blanks
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        REPO_LIST+=("$line")
    done < "$REPO_REGISTRY"

    if (( ${#REPO_LIST[@]} == 0 )); then
        die "registry is empty: $REPO_REGISTRY" 3
    fi
}

get_name()  { printf '%s' "$1" | cut -d'|' -f1; }
get_path()  { printf '%s' "$1" | cut -d'|' -f2; }
get_post()  { printf '%s' "$1" | cut -d'|' -f3; }

contains_unsafe_shell_chars() {
    local s="$1"
    [[ "$s" == *"|"* ]] && return 0
    [[ "$s" == *";"* ]] && return 0
    [[ "$s" == *">"* ]] && return 0
    [[ "$s" == *"<"* ]] && return 0
    [[ "$s" == *"`"* ]] && return 0
    [[ "$s" == *"$("* ]] && return 0
    [[ "$s" == *"\${"* ]] && return 0
    [[ "$s" == *"="* && "$s" != *=*/* && "$s" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && return 0
    return 1
}

run_post_chain() {
    local post="$1"
    local name="$2"
    local path="$3"
    local segments=()
    local rest="$post"

    while [[ "$rest" == *"&&"* ]]; do
        segments+=("${rest%%&&*}")
        rest="${rest#*&&}"
    done
    segments+=("$rest")

    local segment trimmed
    for segment in "${segments[@]}"; do
        trimmed="$(printf '%s' "$segment" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [[ -z "$trimmed" ]] && continue

        if contains_unsafe_shell_chars "$trimmed"; then
            fail "unsafe post-pull command for $name: $trimmed"
            info "allowed: simple argv commands, optionally chained with &&"
            info "for complex logic, use an executable script path in the registry"
            return 1
        fi

        local cmd=()
        # shellcheck disable=SC2206
        cmd=($trimmed)
        if (( ${#cmd[@]} == 0 )); then
            continue
        fi

        # Treat relative script paths as repo-relative for predictable deploy hooks
        if [[ "${cmd[0]}" == ./* ]]; then
            cmd[0]="$path/${cmd[0]#./}"
        fi

        if [[ "${cmd[0]}" == /* || "${cmd[0]}" == ./* ]]; then
            [[ -x "${cmd[0]}" ]] || { fail "post-pull executable missing or not executable: ${cmd[0]}"; return 1; }
        fi

        if ! run "${cmd[@]}"; then
            fail "post-pull command failed for $name: $trimmed"
            return 1
        fi
    done

    return 0
}

update_one_repo() {
    local name="$1"
    local path="$2"
    local post="$3"

    header "Updating: $name"
    info "path: $path"

    if [[ ! -d "$path/.git" ]]; then
        fail "$path is not a git repository"
        return 1
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        info "DRY-RUN: would reset, clean, and pull $path"
        [[ -n "$post" ]] && info "DRY-RUN: would run post-pull: $post"
        return 0
    fi

    cd "$path" || { fail "cannot enter $path"; return 1; }
    git config --global --add safe.directory "$path" 2>/dev/null || true

    info "resetting local changes (tracked + untracked)"
    run git reset --hard HEAD
    run git clean -fd

    local before after
    before=$(git rev-parse HEAD)

    info "pulling latest"
    if ! git pull --rebase; then
        fail "git pull failed for $name"
        return 1
    fi
    after=$(git rev-parse HEAD)

    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    info "branch: $branch"
    info "latest: $(git log -1 --oneline)"

    # Fix node_modules executable bits (npm install can strip them)
    if [[ -d "$path/node_modules/.bin" ]]; then
        local non_exec
        non_exec=$(find "$path/node_modules/.bin" -not -perm -u+x 2>/dev/null)
        if [[ -n "$non_exec" ]]; then
            info "fixing execute permissions in node_modules/.bin/"
            chmod +x "$path/node_modules/.bin/"* 2>/dev/null || true
        fi
    fi

    # Run post-pull command if changes were pulled
    if [[ -n "$post" ]]; then
        if [[ "$before" != "$after" ]]; then
            header "post-pull: $post"
            if run_post_chain "$post" "$name" "$path"; then
                pass "build complete for $name"
            else
                return 1
            fi
        else
            info "no changes, skipping post-pull"
        fi
    fi

    pass "$name updated"
    _sk_audit "updated $name at $path ($before -> $after)"
    return 0
}

update_all() {
    local failed=0
    for entry in "${REPO_LIST[@]}"; do
        update_one_repo "$(get_name "$entry")" "$(get_path "$entry")" "$(get_post "$entry")" \
            || failed=$((failed + 1))
    done
    if (( failed > 0 )); then
        warn "$failed repo(s) failed to update"
        return 1
    fi
    return 0
}

update_named() {
    local target="$1"
    for entry in "${REPO_LIST[@]}"; do
        if [[ "$(get_name "$entry")" == "$target" ]]; then
            update_one_repo "$(get_name "$entry")" "$(get_path "$entry")" "$(get_post "$entry")"
            return $?
        fi
    done
    die "repo not found in registry: $target" 2
}

interactive_menu() {
    while true; do
        printf "\n${SK_BOLD}=============================================\n"
        printf " Repository Update Tool\n"
        printf "=============================================${SK_NC}\n\n"
        printf "  Repositories:\n\n"
        local i=1
        for entry in "${REPO_LIST[@]}"; do
            printf "  %2d) %-30s %s\n" "$i" "$(get_name "$entry")" "$(get_path "$entry")"
            i=$((i + 1))
        done
        printf "\n   a) Update ALL repositories\n"
        printf "   q) Quit\n\n"
        printf "  Enter your choice: "

        local choice
        IFS= read -r choice
        echo

        case "$choice" in
            [aA])
                update_all
                printf "\nPress Enter to return to menu or 'q' to quit: "
                IFS= read -r cont
                [[ "$cont" =~ ^[qQ]$ ]] && return 0
                ;;
            [qQ])
                return 0
                ;;
            ''|*[!0-9]*)
                warn "invalid choice"
                ;;
            *)
                if (( choice >= 1 && choice <= ${#REPO_LIST[@]} )); then
                    local entry="${REPO_LIST[$((choice - 1))]}"
                    update_one_repo "$(get_name "$entry")" "$(get_path "$entry")" "$(get_post "$entry")"
                    printf "\nUpdate another? (Enter to continue, 'q' to quit): "
                    IFS= read -r cont
                    [[ "$cont" =~ ^[qQ]$ ]] && return 0
                else
                    warn "invalid choice"
                fi
                ;;
        esac
    done
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

while (( ${#REMAINING_ARGS[@]} > 0 )); do
    case "${REMAINING_ARGS[0]}" in
        --all)
            SELECT_ALL=1
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --repo)
            SELECTED_REPO="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --registry)
            REPO_REGISTRY="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        *)
            die "unknown argument: ${REMAINING_ARGS[0]}" 2
            ;;
    esac
done

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root
require_cmd git

if [[ "$YES" == "1" ]]; then
    if (( SELECT_ALL == 0 )) && [[ -z "$SELECTED_REPO" ]]; then
        die "--yes requires either --all or --repo <name>" 2
    fi
fi

load_registry

# =============================================================================
# 6. Main logic
# =============================================================================

if (( SELECT_ALL == 1 )); then
    update_all
    exit $?
elif [[ -n "$SELECTED_REPO" ]]; then
    update_named "$SELECTED_REPO"
    exit $?
else
    interactive_menu
fi
