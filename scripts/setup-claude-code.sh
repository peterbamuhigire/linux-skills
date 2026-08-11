#!/usr/bin/env bash
#: Title:       setup-claude-code.sh
#: Synopsis:     bash setup-claude-code.sh --help
#: Description: Optional Claude Code bootstrap with explicit target, authority,
#:              network, SSH-key, privileged-write, dry-run, and recovery gates.
#:              It does not form part of the canonical, runner-neutral skill path.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.4.0

set -uo pipefail

# This adapter runs before linux-skills has been cloned, so common.sh cannot be
# sourced. Keep the adapter small and fail closed instead of adding a second
# general-purpose command library.

SCRIPT_VERSION="0.4.0"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DRY_RUN=0
YES=0
AUTHORIZE_NETWORK=0
AUTHORIZE_USER_WRITES=0
AUTHORIZE_PRIVILEGED_WRITES=0
AUTHORIZE_SSH_KEY=0

SKILLS_ROOT=""
SKILLS_REPO=""
REPO_REF=""
CLAUDE_PACKAGE=""
SSH_KEY=""
KNOWN_HOSTS=""
GIT_NAME=""
GIT_EMAIL=""
RECOVERY_FILE=""

GIT_ACTION=""
NODE_ACTION=""
CLAUDE_ACTION=""
SSH_KEY_ACTION=""
GITHUB_SSH_ACTION=""
CHECKOUT_ACTION=""
ENGINE_ACTION=""
REGISTRY_ACTION=""

STAGING_DIR=""
CLONE_CREATED=0

info()   { printf '%b\n' "${CYAN}[INFO]${NC} $*"; }
warn()   { printf '%b\n' "${YELLOW}[WARN]${NC} $*" >&2; }
pass()   { printf '%b\n' "${GREEN}[PASS]${NC} $*"; }
error() { printf '%b\n' "${RED}[FAIL]${NC} $*" >&2; exit 1; }
usage_error() { printf '%b\n' "${RED}[FAIL]${NC} $*" >&2; exit 2; }
header() { printf '\n%b\n' "${BOLD}=== $* ===${NC}"; }

usage() {
    cat <<'EOF'
Usage: bash scripts/setup-claude-code.sh [standard flags] [explicit choices]

Optional Claude Code adapter. It is not required by Codex or generic agents.
The command never pulls an existing checkout and never runs a downloaded shell
script. Review the plan with --dry-run before granting any authority.

TARGETS (required for a real run; --skills-root is always required):
    --skills-root PATH          Exact checkout target; must be absolute
    --repo-url URL              Exact GitHub URL, required with --checkout-action clone
    --repo-ref SHA               Exact 40-hex commit, required with --checkout-action clone
    --claude-package SPEC        Exact @anthropic-ai/claude-code@X.Y.Z package,
                                required with --claude-action install
    --ssh-key PATH               Must be exactly $HOME/.ssh/id_ed25519 when used
    --known-hosts PATH           Existing known_hosts file for verified SSH only
    --recovery-file PATH         New exact path for the pre-change recovery record

EXPLICIT ACTIONS (required with --yes; interactive mode prompts when absent):
    --git-action configure|skip
    --node-action install|skip
    --claude-action install|skip
    --ssh-key-action generate|existing|skip
    --github-ssh-action verify|skip
    --checkout-action clone|existing
    --engine-action install|skip
    --registry-action create|skip

AUTHORITY FLAGS (required for the matching real actions; never implied by --yes):
    --authorize-network          Permit package, npm, git, or SSH network access
    --authorize-user-writes     Permit the explicit user-owned targets
    --authorize-privileged-writes
                                Permit package and /usr/local or /etc writes
    --authorize-ssh-key          Permit creation of the exact SSH key target

STANDARD FLAGS:
    -h, --help                  Show this help and exit
        --version               Print version and exit
    -y, --yes                   Non-interactive; all actions and inputs are required
    -n, --dry-run               Print the exact plan; do not call sudo, git, npm, ssh,
                                ssh-keygen, or a package manager

EXAMPLES:
    bash scripts/setup-claude-code.sh --dry-run \
      --skills-root /home/peter/.claude/skills \
      --checkout-action existing \
      --git-action skip --node-action skip --claude-action skip \
      --ssh-key-action skip --github-ssh-action skip \
      --engine-action skip --registry-action skip

    bash scripts/setup-claude-code.sh --yes \
      --skills-root /home/peter/.claude/skills \
      --checkout-action existing --git-action configure \
      --git-name "Peter Bamuhigire" --git-email peter@example.invalid \
      --node-action install --claude-action skip \
      --ssh-key-action existing --ssh-key /home/peter/.ssh/id_ed25519 \
      --github-ssh-action verify --known-hosts /home/peter/.ssh/known_hosts \
      --engine-action install --registry-action skip \
      --recovery-file /home/peter/bootstrap-recovery.txt \
      --authorize-network --authorize-user-writes \
      --authorize-privileged-writes

RECOVERY:
    A real run writes the new --recovery-file before the first mutation. It
    records exact targets and previous user-config/key/checkout state. If a
    later step fails, stop, retain the record and staging path, and recover
    only after reviewing that record; this adapter does not auto-delete or
    reset user data.
EOF
}

cleanup() {
    # A failed clone is deliberately retained for inspection and recovery. Do
    # not recursively delete a path that could have become user-owned.
    if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" && "$CLONE_CREATED" == "0" ]]; then
        warn "Unsuccessful clone staging retained at exact path: $STAGING_DIR"
    fi
}
trap cleanup EXIT

require_arg() {
    local flag="$1"
    local value="${2-}"
    [[ -n "$value" ]] || usage_error "$flag requires a value"
}

validate_choice() {
    local flag="$1"
    local value="$2"
    shift 2
    local allowed
    for allowed in "$@"; do
        [[ "$value" == "$allowed" ]] && return 0
    done
    usage_error "$flag must be one of: $*"
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --version) printf '%s\n' "$SCRIPT_VERSION"; exit 0 ;;
            -y|--yes) YES=1 ;;
            -n|--dry-run) DRY_RUN=1 ;;
            --authorize-network) AUTHORIZE_NETWORK=1 ;;
            --authorize-user-writes) AUTHORIZE_USER_WRITES=1 ;;
            --authorize-privileged-writes) AUTHORIZE_PRIVILEGED_WRITES=1 ;;
            --authorize-ssh-key) AUTHORIZE_SSH_KEY=1 ;;
            --skills-root) require_arg "$1" "${2-}"; SKILLS_ROOT="$2"; shift ;;
            --repo-url) require_arg "$1" "${2-}"; SKILLS_REPO="$2"; shift ;;
            --repo-ref) require_arg "$1" "${2-}"; REPO_REF="$2"; shift ;;
            --claude-package) require_arg "$1" "${2-}"; CLAUDE_PACKAGE="$2"; shift ;;
            --ssh-key) require_arg "$1" "${2-}"; SSH_KEY="$2"; shift ;;
            --known-hosts) require_arg "$1" "${2-}"; KNOWN_HOSTS="$2"; shift ;;
            --git-name) require_arg "$1" "${2-}"; GIT_NAME="$2"; shift ;;
            --git-email) require_arg "$1" "${2-}"; GIT_EMAIL="$2"; shift ;;
            --recovery-file) require_arg "$1" "${2-}"; RECOVERY_FILE="$2"; shift ;;
            --git-action) require_arg "$1" "${2-}"; GIT_ACTION="$2"; shift ;;
            --node-action) require_arg "$1" "${2-}"; NODE_ACTION="$2"; shift ;;
            --claude-action) require_arg "$1" "${2-}"; CLAUDE_ACTION="$2"; shift ;;
            --ssh-key-action) require_arg "$1" "${2-}"; SSH_KEY_ACTION="$2"; shift ;;
            --github-ssh-action) require_arg "$1" "${2-}"; GITHUB_SSH_ACTION="$2"; shift ;;
            --checkout-action) require_arg "$1" "${2-}"; CHECKOUT_ACTION="$2"; shift ;;
            --engine-action) require_arg "$1" "${2-}"; ENGINE_ACTION="$2"; shift ;;
            --registry-action) require_arg "$1" "${2-}"; REGISTRY_ACTION="$2"; shift ;;
            *) usage_error "unknown argument: $1" ;;
        esac
        shift
    done
}

prompt_value() {
    local label="$1"
    local value="${2-}"
    if [[ -n "$value" ]]; then
        return 0
    fi
    if (( YES )); then
        usage_error "$label is required with --yes"
    fi
    printf '%s' "${YELLOW}[?]${NC} $label: "
    IFS= read -r value || error "input interrupted while reading $label"
    [[ -n "$value" ]] || usage_error "$label cannot be empty"
    case "$label" in
        skills-root) SKILLS_ROOT="$value" ;;
        repo-url) SKILLS_REPO="$value" ;;
        ssh-key) SSH_KEY="$value" ;;
        known-hosts) KNOWN_HOSTS="$value" ;;
        git-name) GIT_NAME="$value" ;;
        git-email) GIT_EMAIL="$value" ;;
        recovery-file) RECOVERY_FILE="$value" ;;
    esac
}

prompt_action() {
    local label="$1"
    local current="$2"
    local value=""
    [[ -n "$current" ]] && return 0
    if (( YES )); then
        usage_error "$label is required with --yes"
    fi
    printf '%s' "${YELLOW}[?]${NC} $label (type the full choice): "
    IFS= read -r value || error "input interrupted while reading $label"
    [[ -n "$value" ]] || usage_error "$label cannot be empty"
    case "$label" in
        git-action) GIT_ACTION="$value" ;;
        node-action) NODE_ACTION="$value" ;;
        claude-action) CLAUDE_ACTION="$value" ;;
        ssh-key-action) SSH_KEY_ACTION="$value" ;;
        github-ssh-action) GITHUB_SSH_ACTION="$value" ;;
        checkout-action) CHECKOUT_ACTION="$value" ;;
        engine-action) ENGINE_ACTION="$value" ;;
        registry-action) REGISTRY_ACTION="$value" ;;
    esac
}

validate_absolute_path() {
    local label="$1"
    local value="$2"
    [[ "$value" == /* ]] || usage_error "$label must be an absolute path"
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || usage_error "$label contains a newline"
    [[ "$value" != "/" ]] || usage_error "$label cannot be /"
}

validate_shell_path() {
    local label="$1"
    local value="$2"
    validate_absolute_path "$label" "$value"
    case "$value" in
        *[!A-Za-z0-9_./-]*) usage_error "$label may contain only letters, digits, dot, underscore, slash, and hyphen" ;;
    esac
}

validate_inputs() {
    validate_absolute_path skills-root "$SKILLS_ROOT"
    [[ "$SKILLS_ROOT" != "/usr" && "$SKILLS_ROOT" != "/etc" && "$SKILLS_ROOT" != "/var" && "$SKILLS_ROOT" != "/home" && "$SKILLS_ROOT" != "/root" ]] || usage_error "skills-root is a protected parent, choose an exact checkout directory"
    [[ "$SKILLS_ROOT" != *$'\n'* && "$SKILLS_ROOT" != *$'\r'* ]] || usage_error "skills-root contains a newline"

    validate_choice --git-action "$GIT_ACTION" configure skip
    validate_choice --node-action "$NODE_ACTION" install skip
    validate_choice --claude-action "$CLAUDE_ACTION" install skip
    validate_choice --ssh-key-action "$SSH_KEY_ACTION" generate existing skip
    validate_choice --github-ssh-action "$GITHUB_SSH_ACTION" verify skip
    validate_choice --checkout-action "$CHECKOUT_ACTION" clone existing
    validate_choice --engine-action "$ENGINE_ACTION" install skip
    validate_choice --registry-action "$REGISTRY_ACTION" create skip

    if [[ "$CHECKOUT_ACTION" == "clone" ]]; then
        [[ -n "$SKILLS_REPO" ]] || usage_error "--repo-url is required when --checkout-action clone is selected"
        [[ "$REPO_REF" =~ ^[0-9a-fA-F]{40}$ ]] || usage_error "--repo-ref must be an exact 40-hex commit when --checkout-action clone is selected"
        case "$SKILLS_REPO" in
            git@github.com:[A-Za-z0-9._-]+/[A-Za-z0-9._-]+.git|https://github.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+.git) ;;
            *) usage_error "--repo-url must be an explicit GitHub SSH or HTTPS repository URL" ;;
        esac
    elif [[ -n "$REPO_REF" ]]; then
        usage_error "--repo-ref is only valid with --checkout-action clone"
    fi

    if [[ "$CLAUDE_ACTION" == "install" ]]; then
        [[ "$CLAUDE_PACKAGE" =~ ^@anthropic-ai/claude-code@[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage_error "--claude-package must be an exact @anthropic-ai/claude-code@X.Y.Z version"
    elif [[ -n "$CLAUDE_PACKAGE" ]]; then
        usage_error "--claude-package is only valid with --claude-action install"
    fi

    if [[ "$GIT_ACTION" == "configure" ]]; then
        [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]] || usage_error "--git-name and --git-email are required when configuring Git"
        [[ "$GIT_NAME" != *$'\n'* && "$GIT_EMAIL" != *$'\n'* ]] || usage_error "Git identity cannot contain a newline"
    fi

    if [[ "$SSH_KEY_ACTION" != "skip" ]]; then
        [[ -n "$SSH_KEY" ]] || usage_error "--ssh-key is required when an SSH-key action is selected"
        validate_shell_path ssh-key "$SSH_KEY"
        [[ "$SSH_KEY" == "$HOME/.ssh/id_ed25519" ]] || usage_error "--ssh-key must target exactly $HOME/.ssh/id_ed25519"
    fi

    if [[ "$GITHUB_SSH_ACTION" == "verify" ]]; then
        [[ -n "$KNOWN_HOSTS" ]] || usage_error "--known-hosts is required for verified GitHub SSH"
        validate_shell_path known-hosts "$KNOWN_HOSTS"
    fi

    if [[ "$SKILLS_REPO" == git@github.com:* ]]; then
        [[ "$SSH_KEY_ACTION" != "skip" ]] || usage_error "SSH checkout requires an explicit --ssh-key-action"
        [[ -n "$KNOWN_HOSTS" ]] || usage_error "SSH checkout requires an explicit --known-hosts path"
        validate_shell_path known-hosts "$KNOWN_HOSTS"
    fi

    if (( ! DRY_RUN )); then
        [[ -n "$RECOVERY_FILE" ]] || usage_error "--recovery-file is required for a real run"
        validate_absolute_path recovery-file "$RECOVERY_FILE"
        [[ ! -e "$RECOVERY_FILE" ]] || usage_error "recovery-file already exists; choose a new exact path"
    fi
}

prompt_missing_inputs() {
    prompt_value skills-root "$SKILLS_ROOT"
    prompt_action git-action "$GIT_ACTION"
    prompt_action node-action "$NODE_ACTION"
    prompt_action claude-action "$CLAUDE_ACTION"
    prompt_action ssh-key-action "$SSH_KEY_ACTION"
    prompt_action github-ssh-action "$GITHUB_SSH_ACTION"
    prompt_action checkout-action "$CHECKOUT_ACTION"
    prompt_action engine-action "$ENGINE_ACTION"
    prompt_action registry-action "$REGISTRY_ACTION"

    if [[ "$CHECKOUT_ACTION" == "clone" ]]; then
        prompt_value repo-url "$SKILLS_REPO"
    fi
    if [[ "$GIT_ACTION" == "configure" ]]; then
        prompt_value git-name "$GIT_NAME"
        prompt_value git-email "$GIT_EMAIL"
    fi
    if [[ "$SSH_KEY_ACTION" != "skip" ]]; then
        prompt_value ssh-key "$SSH_KEY"
    fi
    if [[ "$GITHUB_SSH_ACTION" == "verify" ]]; then
        prompt_value known-hosts "$KNOWN_HOSTS"
    fi
    if (( ! DRY_RUN )); then
        prompt_value recovery-file "$RECOVERY_FILE"
    fi
}

target_state() {
    if [[ -e "$SKILLS_ROOT" ]]; then
        if [[ -L "$SKILLS_ROOT" ]]; then
            printf '%s' "symlink"
        elif [[ -d "$SKILLS_ROOT/.git" ]]; then
            printf '%s' "git-checkout"
        elif [[ -d "$SKILLS_ROOT" ]]; then
            printf '%s' "directory"
        else
            printf '%s' "other"
        fi
    else
        printf '%s' "absent"
    fi
}

validate_target() {
    local state
    state="$(target_state)"
    case "$CHECKOUT_ACTION:$state" in
        existing:git-checkout) ;;
        existing:*) error "--checkout-action existing requires a real git checkout at exact target $SKILLS_ROOT (state: $state)" ;;
        clone:absent) ;;
        clone:*) error "--checkout-action clone requires the exact target to be absent (state: $state): $SKILLS_ROOT" ;;
    esac
    if [[ "$GITHUB_SSH_ACTION" == "verify" || "$SKILLS_REPO" == git@github.com:* ]]; then
        [[ -n "$KNOWN_HOSTS" ]] || usage_error "verified SSH requires --known-hosts"
        if (( ! DRY_RUN )); then
            [[ -f "$KNOWN_HOSTS" ]] || error "known_hosts must already exist; this adapter will not create or update it"
        fi
    fi
}

require_authority() {
    local action="$1"
    local flag="$2"
    local value="$3"
    (( value == 1 )) || error "$action requires explicit $flag"
}

validate_authority() {
    (( DRY_RUN )) && return 0

    local user_write=0 network=0 privileged=0 ssh_write=0
    # The recovery record is itself an explicit user-owned write and is
    # required before every real run, even when all operational actions skip.
    (( ! DRY_RUN )) && user_write=1
    [[ "$GIT_ACTION" == "configure" ]] && user_write=1
    [[ "$CHECKOUT_ACTION" == "clone" ]] && user_write=1 && network=1
    [[ "$SSH_KEY_ACTION" == "generate" ]] && user_write=1 && ssh_write=1
    [[ "$NODE_ACTION" == "install" ]] && network=1 && privileged=1
    [[ "$CLAUDE_ACTION" == "install" ]] && network=1 && privileged=1
    [[ "$GITHUB_SSH_ACTION" == "verify" ]] && network=1
    [[ "$ENGINE_ACTION" == "install" ]] && privileged=1
    [[ "$REGISTRY_ACTION" == "create" ]] && privileged=1

    (( user_write )) && require_authority "user-owned target writes" --authorize-user-writes "$AUTHORIZE_USER_WRITES"
    (( network )) && require_authority "network access" --authorize-network "$AUTHORIZE_NETWORK"
    (( privileged )) && require_authority "privileged writes" --authorize-privileged-writes "$AUTHORIZE_PRIVILEGED_WRITES"
    (( ssh_write )) && require_authority "SSH-key generation" --authorize-ssh-key "$AUTHORIZE_SSH_KEY"

    if (( YES )) && [[ "$SSH_KEY_ACTION" == "generate" ]]; then
        error "--yes cannot generate a new SSH key because no passphrase may be supplied non-interactively; generate it separately or use --ssh-key-action existing"
    fi
}

print_plan() {
    header "Dry-run: no host mutation"
    info "Exact checkout target: $SKILLS_ROOT"
    info "Checkout action: $CHECKOUT_ACTION"
    [[ "$CHECKOUT_ACTION" == "clone" ]] && info "Remote repository: $SKILLS_REPO at exact commit $REPO_REF"
    info "Git configuration action: $GIT_ACTION"
    [[ "$GIT_ACTION" == "configure" ]] && info "Global Git identity target: user.name/user.email"
    info "Node.js action: $NODE_ACTION"
    info "Claude CLI action: $CLAUDE_ACTION (exact package: ${CLAUDE_PACKAGE:-not-used}; install scripts disabled)"
    info "SSH-key action: $SSH_KEY_ACTION"
    [[ "$SSH_KEY_ACTION" != "skip" ]] && info "Exact SSH-key target: $SSH_KEY"
    info "GitHub SSH verification: $GITHUB_SSH_ACTION"
    [[ "$GITHUB_SSH_ACTION" == "verify" ]] && info "Read-only known_hosts target: $KNOWN_HOSTS"
    info "Engine action: $ENGINE_ACTION (exact installer: $SKILLS_ROOT/scripts/install-skills-bin)"
    info "Registry action: $REGISTRY_ACTION (exact target: /etc/linux-skills/repos.conf)"
    if [[ -n "$RECOVERY_FILE" ]]; then
        info "Recovery record would be written to: $RECOVERY_FILE"
    else
        info "Recovery record: required for a real run; not written in this dry-run"
    fi
    pass "dry-run completed; sudo, package manager, npm, git, ssh, ssh-keygen, and remote shell execution were not called"
}

write_recovery_manifest() {
    local recovery_dir recovery_tmp old_name old_email target_before key_before registry_before
    recovery_dir="$(dirname "$RECOVERY_FILE")"
    [[ -d "$recovery_dir" ]] || error "recovery-file parent must already exist: $recovery_dir"
    [[ ! -L "$recovery_dir" ]] || error "recovery-file parent must not be a symlink: $recovery_dir"

    old_name="$(git config --global --get user.name 2>/dev/null || true)"
    old_email="$(git config --global --get user.email 2>/dev/null || true)"
    target_before="$(target_state)"
    key_before="absent"
    [[ -e "$SSH_KEY" ]] && key_before="present"
    registry_before="absent"
    [[ -e /etc/linux-skills/repos.conf ]] && registry_before="present"

    recovery_tmp="$(mktemp "$recovery_dir/.bootstrap-recovery.XXXXXX")" || error "cannot create recovery temporary file in $recovery_dir"
    if ! {
        printf 'linux-skills Claude bootstrap recovery record v1\n'
        printf 'created_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'checkout_target=%s\n' "$SKILLS_ROOT"
        printf 'checkout_state_before=%s\n' "$target_before"
        printf 'repository_url=%s\n' "${SKILLS_REPO:-not-used}"
        printf 'repository_commit=%s\n' "${REPO_REF:-not-used}"
        printf 'claude_package=%s\n' "${CLAUDE_PACKAGE:-not-used}"
        printf 'ssh_key_target=%s\n' "${SSH_KEY:-not-used}"
        printf 'ssh_key_state_before=%s\n' "$key_before"
        printf 'known_hosts_target=%s\n' "${KNOWN_HOSTS:-not-used}"
        printf 'registry_target=/etc/linux-skills/repos.conf\n'
        printf 'registry_state_before=%s\n' "$registry_before"
        printf 'global_git_user_name_before=%s\n' "${old_name:-unset}"
        printf 'global_git_user_email_before=%s\n' "${old_email:-unset}"
        printf '\nRecovery boundary:\n'
        printf '%s\n' 'Do not reset or delete an existing checkout. The adapter never pulls an existing checkout.'
        printf '%s\n' 'If clone staging fails, inspect the retained staging path printed by the adapter.'
        printf '%s\n' 'If a later step fails, stop and use this record to restore Git identity or quarantine only a checkout created by this run.'
        printf '%s\n' 'The adapter does not promise package rollback; use the host package manager history and operator change record.'
    } > "$recovery_tmp"; then
        rm -f -- "$recovery_tmp"
        error "cannot write recovery record"
    fi
    chmod 600 "$recovery_tmp" || error "cannot protect recovery record"
    if [[ -e "$RECOVERY_FILE" ]]; then
        rm -f -- "$recovery_tmp"
        error "recovery-file appeared during preparation; refusing overwrite: $RECOVERY_FILE"
    fi
    mv -- "$recovery_tmp" "$RECOVERY_FILE" || error "cannot commit recovery record: $RECOVERY_FILE"
    pass "recovery record created at exact target $RECOVERY_FILE"
}

run_user_write() {
    local description="$1"
    shift
    if ! "$@"; then
        error "$description failed; retain recovery record and stop"
    fi
}

run_privileged() {
    local description="$1"
    shift
    info "$description: sudo $*"
    if ! sudo -- "$@"; then
        error "$description failed; retain recovery record and stop"
    fi
}

install_node() {
    [[ "$NODE_ACTION" == "install" ]] || return 0
    header "Node.js"
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        info "Node.js and npm already exist: $(node --version 2>/dev/null || printf 'unknown')"
        return 0
    fi
    local package_manager=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        case "${ID:-} ${ID_LIKE:-}" in
            *debian*|*ubuntu*) package_manager="apt-get" ;;
            *fedora*|*rhel*|*centos*|*rocky*|*alma*) package_manager="dnf" ;;
        esac
    fi
    [[ -n "$package_manager" ]] || error "unsupported distro for package-managed Node.js installation"
    if [[ "$package_manager" == "apt-get" ]]; then
        run_privileged "refresh package metadata" "$package_manager" update
    fi
    run_privileged "install distribution Node.js and npm packages" "$package_manager" install -y nodejs npm
    command -v node >/dev/null 2>&1 || error "Node.js is still unavailable after package installation"
    command -v npm >/dev/null 2>&1 || error "npm is still unavailable after package installation"
}

install_claude() {
    [[ "$CLAUDE_ACTION" == "install" ]] || return 0
    header "Claude Code CLI"
    command -v npm >/dev/null 2>&1 || error "npm is required for Claude CLI installation; select --node-action install or install it separately"
    # Fetched shell-script execution and package install hooks are not
    # permitted here. The package spec and exact global target are fixed;
    # network authority remains a separate explicit decision.
    run_privileged "install the exact Claude package version through npm" npm install --global --ignore-scripts "$CLAUDE_PACKAGE"
    command -v claude >/dev/null 2>&1 || warn "Claude CLI was installed but is not currently visible in PATH"
}

configure_git() {
    [[ "$GIT_ACTION" == "configure" ]] || return 0
    header "Git configuration"
    run_user_write "set global Git user.name" git config --global user.name "$GIT_NAME"
    run_user_write "set global Git user.email" git config --global user.email "$GIT_EMAIL"
    run_user_write "set global Git default branch" git config --global init.defaultBranch main
    pass "global Git identity configured for the explicit operator values"
}

prepare_ssh_key() {
    [[ "$SSH_KEY_ACTION" != "skip" ]] || return 0
    header "SSH key"
    if [[ "$SSH_KEY_ACTION" == "existing" ]]; then
        [[ -f "$SSH_KEY" && -f "${SSH_KEY}.pub" ]] || error "existing SSH-key action requires both exact files: $SSH_KEY and ${SSH_KEY}.pub"
        [[ "$(stat -c '%a' "$SSH_KEY" 2>/dev/null || printf 'unknown')" == "600" ]] || warn "private key mode is not 600; correct it outside this adapter before use"
        info "Using the existing exact SSH-key target without changing it: $SSH_KEY"
        return 0
    fi
    [[ ! -e "$SSH_KEY" && ! -e "${SSH_KEY}.pub" ]] || error "refusing to overwrite an existing exact SSH-key target"
    run_user_write "create the exact SSH-key parent" mkdir -p "$HOME/.ssh"
    run_user_write "protect the exact SSH-key parent" chmod 700 "$HOME/.ssh"
    info "ssh-keygen will prompt for a passphrase; an empty passphrase is not supplied by this adapter"
    run_user_write "generate the exact SSH key" ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY"
    run_user_write "protect the generated private key" chmod 600 "$SSH_KEY"
    run_user_write "protect the generated public key" chmod 644 "${SSH_KEY}.pub"
}

verify_github_ssh() {
    [[ "$GITHUB_SSH_ACTION" == "verify" ]] || return 0
    header "GitHub SSH verification"
    [[ -f "$KNOWN_HOSTS" ]] || error "known_hosts must already exist; refusing to create or accept a host key"
    [[ "$SSH_KEY_ACTION" != "skip" ]] || error "GitHub SSH verification requires an explicit SSH-key action"
    local output status
    set +e
    output="$(ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$KNOWN_HOSTS" -i "$SSH_KEY" -T git@github.com 2>&1)"
    status=$?
    set -u
    printf '%s\n' "$output"
    if [[ "$output" == *"successfully authenticated"* ]]; then
        pass "GitHub SSH identity was accepted by the verified host key"
    else
        error "GitHub SSH verification did not produce the expected authentication result (ssh exit $status)"
    fi
}

clone_checkout() {
    [[ "$CHECKOUT_ACTION" == "clone" ]] || return 0
    header "linux-skills checkout"
    local parent
    parent="$(dirname "$SKILLS_ROOT")"
    [[ -d "$parent" ]] || error "checkout parent must already exist; refusing implicit directory creation: $parent"
    [[ ! -L "$parent" ]] || error "checkout parent must not be a symlink: $parent"
    STAGING_DIR="$(mktemp -d "$parent/.linux-skills-bootstrap.XXXXXX")" || error "cannot create exact-parent staging directory"
    info "Cloning $SKILLS_REPO to retained staging path $STAGING_DIR"
    local clone_ssh_command=""
    if [[ "$SKILLS_REPO" == git@github.com:* ]]; then
        clone_ssh_command="ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=$KNOWN_HOSTS -i $SSH_KEY"
    fi
    if [[ -n "$clone_ssh_command" ]]; then
        GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$clone_ssh_command" git -c core.hooksPath=/dev/null clone -- "$SKILLS_REPO" "$STAGING_DIR/checkout" || error "git clone failed; inspect retained staging path $STAGING_DIR"
    else
        GIT_TERMINAL_PROMPT=0 git -c core.hooksPath=/dev/null clone -- "$SKILLS_REPO" "$STAGING_DIR/checkout" || error "git clone failed; inspect retained staging path $STAGING_DIR"
    fi
    [[ -d "$STAGING_DIR/checkout/.git" ]] || error "clone did not produce a git checkout in retained staging path $STAGING_DIR"
    run_user_write "checkout the exact pinned repository commit" git -C "$STAGING_DIR/checkout" checkout --detach "${REPO_REF,,}"
    local actual_ref
    actual_ref="$(git -C "$STAGING_DIR/checkout" rev-parse HEAD 2>/dev/null)" || error "cannot verify the checked-out repository commit"
    [[ "$actual_ref" == "${REPO_REF,,}" ]] || error "repository commit verification failed; expected ${REPO_REF,,}, got $actual_ref"
    mv -- "$STAGING_DIR/checkout" "$SKILLS_ROOT" || error "cannot move verified clone to exact target $SKILLS_ROOT"
    CLONE_CREATED=1
    rmdir -- "$STAGING_DIR" 2>/dev/null || warn "staging parent retained for manual cleanup: $STAGING_DIR"
    STAGING_DIR=""
    pass "checkout created at exact target $SKILLS_ROOT"
}

install_engine() {
    [[ "$ENGINE_ACTION" == "install" ]] || return 0
    header "linux-skills engine"
    local installer="$SKILLS_ROOT/scripts/install-skills-bin"
    [[ -f "$installer" && -x "$installer" ]] || error "exact engine installer is missing or not executable: $installer"
    run_privileged "install linux-skills core scripts from the exact checkout" "$installer" core
    pass "core engine installation completed through the exact checkout installer"
}

create_registry() {
    [[ "$REGISTRY_ACTION" == "create" ]] || return 0
    header "linux-skills repository registry"
    local target="/etc/linux-skills/repos.conf"
    [[ ! -e "$target" ]] || error "refusing to overwrite existing privileged registry target: $target"
    local tmp
    tmp="$(mktemp)" || error "cannot create registry temporary file"
    if ! {
        printf '%s\n' '# linux-skills repo registry'
        printf '%s\n' '# Format: Name|Path|post_pull_command'
        printf 'Linux Skills|%s|\n' "$SKILLS_ROOT"
    } > "$tmp"; then
        rm -f -- "$tmp"
        error "cannot prepare repository registry"
    fi
    run_privileged "create the exact registry directory" install -d -m 0755 /etc/linux-skills
    run_privileged "write the new exact repository registry" install -m 0644 -o root -g root "$tmp" "$target"
    rm -f -- "$tmp"
    pass "repository registry created at exact target $target"
}

main() {
    parse_args "$@"
    if (( EUID == 0 )); then
        error "do not run this adapter as root; run it as the target admin user and grant only the explicit sudo authority"
    fi
    if (( ! DRY_RUN )); then
        command -v git >/dev/null 2>&1 || error "git is required for the recovery record and selected actions"
        command -v sudo >/dev/null 2>&1 || error "sudo is required for the selected privileged boundaries"
    fi

    prompt_missing_inputs
    validate_inputs
    validate_target
    validate_authority

    if (( DRY_RUN )); then
        print_plan
        return 0
    fi

    write_recovery_manifest
    configure_git
    install_node
    install_claude
    prepare_ssh_key
    verify_github_ssh
    clone_checkout
    install_engine
    create_registry
    header "Bootstrap complete"
    info "Canonical entry point remains: $SKILLS_ROOT/AGENTS.md -> $SKILLS_ROOT/linux-sysadmin/SKILL.md"
    info "Retain the recovery record at: $RECOVERY_FILE"
    pass "optional Claude bootstrap completed with explicit authorities"
}

main "$@"
