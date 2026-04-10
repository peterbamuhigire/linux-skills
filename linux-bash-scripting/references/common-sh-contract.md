# `common.sh` library contract

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

The shared library every `sk-*` script sources. Installed to
`/usr/local/lib/linux-skills/common.sh` by `install-skills-bin`. In
development, scripts fall back to `scripts/lib/common.sh` inside the repo.

This document is the contract. The library itself is built in the
implementation session — this doc tells the implementer exactly what to build
and tells script authors exactly what they can rely on.

---

## Globals set by the library

After `source common.sh` and `parse_standard_flags "$@"`, these are set:

| Variable | Type | Default | Meaning |
|---|---|---|---|
| `DRY_RUN` | 0/1 | 0 | `--dry-run` was passed. |
| `YES` | 0/1 | 0 | `--yes` was passed. |
| `LOG_FILE` | path | "" | Log target, if `--log` was passed. |
| `JSON` | 0/1 | 0 | `--json` was passed. |
| `VERBOSE` | 0/1 | 0 | `--verbose` was passed. |
| `QUIET` | 0/1 | 0 | `--quiet` was passed. |
| `PASS_COUNT` | int | 0 | Incremented by `pass`. |
| `WARN_COUNT` | int | 0 | Incremented by `warn`. |
| `FAIL_COUNT` | int | 0 | Incremented by `fail`. |
| `REMAINING_ARGS` | array | "" | Args not consumed by `parse_standard_flags`. |
| `SK_SCRIPT_NAME` | string | — | Basename of the calling script, derived from `$0`. |
| `SK_AUDIT_LOG` | path | `/var/log/linux-skills/<script>.log` | Destructive-op audit trail. Always written, not controlled by `--log`. |

---

## Colors (internal)

Exported from `common.sh` but rarely used directly by scripts:

```bash
SK_GREEN='\033[0;32m'
SK_YELLOW='\033[1;33m'
SK_RED='\033[0;31m'
SK_CYAN='\033[0;36m'
SK_BOLD='\033[1m'
SK_NC='\033[0m'
```

When `JSON=1` or `QUIET=1` or when stdout is not a TTY, colors collapse to
empty strings.

---

## Output primitives

### `pass "msg"`

```
  [PASS] SSH root login is disabled
```

Increments `PASS_COUNT`. Prints to stdout unless `QUIET=1`.

### `warn "msg"`

```
  [WARN] X11 forwarding is enabled
```

Increments `WARN_COUNT`. Always prints (warnings are never suppressed).

### `fail "msg"`

```
  [FAIL] MySQL is listening on 0.0.0.0
```

Increments `FAIL_COUNT`. Always prints.

### `info "msg"`

```
  [INFO] Detected PHP 8.2
```

Suppressed under `QUIET=1`. Does not affect counts.

### `header "Section name"`

```

=== Section name ===
```

Bold. Blank line before it. Always printed.

### `die "msg" [exit_code]`

Prints `msg` in red to stderr prefixed with `FATAL:`, then exits with
`exit_code` (default 1). Flushes pending log output. Triggers the cleanup
trap.

### `log "msg"`

Appends a timestamped line to `LOG_FILE` if set. No-op otherwise. Use for
information that should land in the log but not clutter stdout.

---

## Guard primitives

### `require_root`

```bash
require_root
```

Exits 1 if `$EUID != 0`. Error message suggests `sudo`.

### `require_debian`

Reads `/etc/os-release`. Exits 3 unless `$ID` is `debian` or `ubuntu`. Error
message names the distro it found.

### `require_cmd <cmd>...`

```bash
require_cmd nginx certbot jq
```

Exits 5 if any listed command is missing. For common tools, the error names
the apt package that provides it (`jq` → `apt install jq`).

### `require_flag <NAME>`

```bash
if [[ "$YES" == "1" ]]; then
    require_flag DOMAIN
    require_flag PORT
fi
```

In `--yes` mode, checks that the named global variable is non-empty. Exits 2
with a clear message if not, pointing at `--help`. Outside `--yes` mode, this
function is a no-op (the script will prompt interactively instead).

---

## Interaction primitives

All interaction functions check `YES` first. Behavior under `--yes`:

- `confirm` — returns 0 (yes) only for **non-destructive** prompts.
- `confirm_destructive` — **never** auto-confirms under `--yes`. Requires a
  prior `require_flag` to have succeeded.
- `prompt` — returns the default if set, otherwise `die` with a missing-flag
  message.
- `select_one` — returns the first option if a default is given, otherwise
  `die`.

### `confirm "Do X?" [default=N]`

```bash
confirm "Enable UFW now?" && run ufw enable
```

Default `N`. Accepts `y`/`yes`/`Y`/`YES` as yes, anything else as no. Under
`--yes`, returns 0 immediately (non-destructive path).

### `confirm_destructive "About to DELETE X"`

```bash
confirm_destructive "This will reset ALL UFW rules to defaults" \
    || die "User aborted" 4
```

Requires the user to type the literal word `yes` (not `y`). Any other input
returns 1. Under `--yes`, the caller must have already passed a decision flag
and called `require_flag` — otherwise the script has a bug and
`confirm_destructive` will `die` with "refusing to auto-confirm destructive
operation under --yes".

### `prompt "Label" [default] [validator]`

```bash
DOMAIN=$(prompt "Domain" "" 'case "$1" in *.*) return 0;; *) return 1;; esac')
```

Interactive read. Validator is a shell snippet that receives the value in
`$1` and returns 0 if valid. Re-prompts on invalid input.

### `select_one "Label" opt1 opt2 opt3...`

```bash
PROFILE=$(select_one "Pick a UFW profile" web-server bastion db custom)
```

Prints a numbered menu, reads a choice, returns the chosen string.

---

## Safe file operations

### `safe_tempfile [prefix]`

```bash
TMP=$(safe_tempfile my-config)
echo "content" > "$TMP"
# ... no manual rm needed; cleanup trap handles it
```

Creates a file in `/tmp` via `mktemp`, registers it in the cleanup trap,
returns the path.

### `safe_tempdir [prefix]`

Same, for directories.

### `atomic_write <target>`

```bash
generate_config | atomic_write /etc/nginx/sites-available/example.conf
```

Reads stdin, writes it to `<target>.new` in the same directory (so the mv is
same-filesystem = atomic), then `mv` on success. Preserves existing
permissions and ownership of the target. If the target doesn't exist, uses
`0644 root:root`.

### `backup_file <path>`

```bash
backup_file /etc/ssh/sshd_config
```

Copies the file to `<path>.bak-YYYYMMDD-HHMMSS`. Prints the backup path to
stdout and to the audit log. No-op if the file doesn't exist.

---

## Flag parsing

### `parse_standard_flags "$@"`

Consumes the standard flags from the argument list, sets the globals, leaves
the rest in `REMAINING_ARGS` for the script to handle. Always call this
before parsing script-specific flags.

```bash
parse_standard_flags "$@"

while [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; do
    case "${REMAINING_ARGS[0]}" in
        --domain)
            DOMAIN="${REMAINING_ARGS[1]}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        ...
    esac
done
```

### `run <cmd>...`

```bash
run systemctl reload nginx
```

- Prints the command prefixed with `→` in verbose or dry-run mode.
- In `DRY_RUN=1` mode, prints and skips execution.
- In normal mode, executes and returns the command's exit code.
- On failure, the caller is responsible for calling `die` or recovering.

---

## The cleanup trap

`common.sh` installs a single trap on `EXIT INT TERM ERR` that:

1. Removes every path registered by `safe_tempfile` / `safe_tempdir`.
2. On non-zero exit, prints a failure banner with the script name, line
   number, and failed command (via `BASH_COMMAND` and `LINENO`).
3. Closes the log file descriptor if `--log` was active.

Scripts should not install their own `trap` on these signals. If a script
needs additional cleanup, it registers a function via `sk_on_exit <func>`
and the library's trap calls it.

---

## Exit codes

Every script exits with one of:

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Generic failure |
| 2 | Usage / flag error |
| 3 | Precondition failed (wrong OS, wrong architecture) |
| 4 | User aborted (Ctrl-C or confirm denied) |
| 5 | Dependency missing |

Other codes are reserved. If a script needs a custom code, document it in
`usage()`.
