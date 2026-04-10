# linux-skills engine specification

Version 1.0 — 2026-04-10
**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This is the binding specification for every script and skill in this repo.
Deviations require updating this document first.

---

## 1. Goals

Turn `linux-skills` from a knowledge base into a full Linux server management
engine for Ubuntu/Debian production servers. Concretely:

1. Every skill has accompanying executable scripts that can be invoked either
   by a human at a terminal or by Claude Code running non-interactively.
2. Scripts install to `/usr/local/bin/` under a single namespace so they feel
   like a coherent toolkit.
3. Scripts are **safe by default** — they confirm before destructive
   operations, support dry-run, and log on request.
4. Scripts are **self-documenting** — `sk-<name> --help` always works.
5. The engine installs on a fresh server in one command and grows incrementally
   as skills are used.

## 2. Audiences

Every script supports two callers:

- **Human operator at a terminal.** Interactive by default: colorized output,
  menus, prompts, confirmations before anything destructive.
- **Claude Code running as a tool.** Non-interactive mode via flags. Claude is
  expected to pre-commit to every decision before invoking the script.

The same script file serves both; there is no separate "quiet mode" binary.

## 3. Installation model — Hybrid C

The repo is cloned to `~/.claude/skills/` on each server. Scripts live in
`scripts/` inside the repo and are **installed** (copied or symlinked) to
`/usr/local/bin/` so they are on every user's `$PATH`.

There are two installation flows:

### 3.1 Core install (bulk, at setup time)

Run once when setting up a fresh server, as part of `setup-claude-code.sh`:

```bash
sudo install-skills-bin core
```

This installs the **core** scripts — the minimal set every server needs
regardless of what it runs. Core is defined by the tier-1 rows of
`script-inventory.md` marked `core=yes`.

### 3.2 Per-skill lazy install (on first use)

When Claude Code first uses a skill on a server, the skill's `SKILL.md`
instructs Claude to ensure its scripts are installed:

```bash
sudo install-skills-bin linux-webstack
```

This reads the `## Scripts` section of `linux-webstack/SKILL.md` and installs
every script listed there. Idempotent — safe to run repeatedly.

Each skill's `SKILL.md` contains a preamble like:

> **First use on a new server?** Run `sudo install-skills-bin linux-webstack`
> to install this skill's scripts into `/usr/local/bin/`.

Claude Code checks whether the scripts are present (e.g. `command -v sk-nginx-new-site`)
and runs the installer if they are not.

### 3.3 `install-skills-bin` behavior

- `install-skills-bin core` — installs tier-1 core scripts.
- `install-skills-bin <skill-name>` — installs one skill's scripts.
- `install-skills-bin all` — installs everything (opt-in, for golden images).
- `install-skills-bin --list` — shows what is installed vs. available.
- `install-skills-bin --uninstall <skill-name>` — removes a skill's scripts.
- Installer reads the `## Scripts` manifest in each `SKILL.md` to decide what
  to copy. It uses `install(1)` with mode `0755`, owner `root`, group `root`.
- On conflict (target exists), the installer refuses unless `--force` is
  passed. It never silently overwrites.

## 4. Naming convention

All installed scripts use the `sk-` prefix in `/usr/local/bin/`. Examples:

```
sk-audit              # security audit
sk-harden-ssh         # SSH hardening
sk-mysql-backup       # MySQL backup
sk-nginx-new-site     # generate a new Nginx vhost
sk-why-slow           # troubleshooting entry point
```

- Prefix (`sk-`) is namespaced and collision-free.
- Tab completion groups them: `sk-<TAB>` shows everything.
- Source files in `scripts/` use the same name with a `.sh` extension:
  `scripts/sk-audit.sh`, `scripts/sk-harden-ssh.sh`, etc. The installer strips
  the extension on copy so the binary is `sk-audit`, not `sk-audit.sh`.

Exceptions (legacy, kept for compatibility): `update-all-repos` stays as-is.

## 5. Standard flags

Every `sk-*` script **must** support this flag set via the shared parser in
`common.sh`:

| Flag | Meaning |
|---|---|
| `--help`, `-h` | Print usage, flags, and exit 0. Must list every decision flag the script accepts. |
| `--version` | Print script version and exit 0. |
| `--yes`, `-y` | Non-interactive mode. Skip all confirmations. **Errors out** if a required decision was not passed as a flag. Never silently picks a default. |
| `--dry-run`, `-n` | Print every action the script would take. Change nothing. |
| `--log[=PATH]` | Tee output to `/var/log/linux-skills/<script>-YYYYMMDD-HHMMSS.log` (or a caller-specified path). |
| `--json` | Emit machine-readable output (where meaningful). Suppresses color codes. |
| `--verbose`, `-v` | Extra diagnostic output. |
| `--quiet`, `-q` | Only errors and the final result. Incompatible with `--verbose`. |

Scripts may add their own flags for decision inputs (e.g. `--domain example.com`,
`--user alice`). Decision flags are documented in `--help` and required when
`--yes` is passed.

### 5.1 The `--yes` contract

`--yes` is **not** "accept all defaults." It means "the caller has already
decided — honor the flags exactly." If a script would normally prompt for a
domain name and the caller did not pass `--domain`, the script **aborts** with
a clear error:

```
ERROR: --yes was passed but --domain is required.
       Run with --help to see required flags for this script.
```

This protects Claude Code from getting a different result than it intended.

## 6. `common.sh` library contract

Every `sk-*` script must source the shared library:

```bash
source /usr/local/lib/linux-skills/common.sh
```

(The installer places `common.sh` at that path alongside the binaries.)

### 6.1 Functions the library must provide

**Output primitives** (from existing `server-audit.sh` style, standardized):

| Function | Purpose |
|---|---|
| `pass "msg"` | Green `[PASS]` line, increments `PASS_COUNT`. |
| `warn "msg"` | Yellow `[WARN]` line, increments `WARN_COUNT`. |
| `fail "msg"` | Red `[FAIL]` line, increments `FAIL_COUNT`. |
| `info "msg"` | Cyan `[INFO]` line. Does not affect counts. |
| `header "Section"` | Bold section separator. |
| `die "msg" [exit_code]` | Print red error to stderr, exit with `exit_code` (default 1). |
| `log "msg"` | Timestamped line to the log file (if `--log` is set). |

**Guards:**

| Function | Purpose |
|---|---|
| `require_root` | Exit if not root. |
| `require_debian` | Exit if not Debian/Ubuntu (checks `/etc/os-release`). |
| `require_cmd <cmd>...` | Exit if any listed command is missing. Lists which package provides it. |
| `require_flag <name>` | In `--yes` mode, exit if the named flag was not set. |

**Interaction:**

| Function | Purpose |
|---|---|
| `confirm "Do X?" [default=N]` | Returns 0 on yes, 1 on no. In `--yes` mode returns 0 automatically **only for non-destructive confirms**. Destructive confirms require an explicit decision flag. |
| `confirm_destructive "This will DELETE X."` | Requires the user to type the exact word `yes` (not `y`). In `--yes` mode, requires a decision flag — never auto-confirms. |
| `prompt "Label" [default] [validator]` | Read a single value with optional default and validator function. |
| `select_one "Label" opt1 opt2 ...` | Numeric menu, returns chosen value. |

**Safe file operations:**

| Function | Purpose |
|---|---|
| `safe_tempfile [prefix]` | Creates a temp file with `mktemp`, registers it for cleanup on EXIT/INT/TERM trap. Returns the path. |
| `safe_tempdir [prefix]` | Same, for directories. |
| `atomic_write <target>` | Reads stdin, writes to `<target>.new` in the same directory, then `mv` on success. Preserves permissions and ownership. |
| `backup_file <path>` | Copies `<path>` to `<path>.bak-YYYYMMDD-HHMMSS` before mutating. Prints the backup path. |

**Flag parsing:**

| Function | Purpose |
|---|---|
| `parse_standard_flags "$@"` | Consumes standard flags, sets globals: `DRY_RUN`, `YES`, `LOG_FILE`, `JSON`, `VERBOSE`, `QUIET`. Leaves unknown flags in `REMAINING_ARGS` for the script to parse. |
| `run` | Wrapper that prints a command before running it. In `--dry-run` mode, prints and skips. Example: `run systemctl restart nginx`. |

**Standard failure trap:**

The library installs a trap on `ERR`, `EXIT`, `INT`, `TERM` that:
- Removes registered temp files.
- If the script died mid-way, prints a clear failure message with the line
  number and the command that failed.
- Flushes any pending log output.

### 6.2 Minimal script skeleton

Every script must follow this six-section layout (from *Pro Bash*):

```bash
#!/usr/bin/env bash
#: Title:       sk-example
#: Synopsis:    sk-example [--flags] <arg>
#: Description: One-line description of what this script does.
#: Author:      linux-skills
#: Version:     0.1.0

# --- 1. Library + safety -----------------------------------------------------
set -uo pipefail
source /usr/local/lib/linux-skills/common.sh

# --- 2. Defaults -------------------------------------------------------------
DOMAIN=""
PORT=443

# --- 3. Functions ------------------------------------------------------------
usage() {
    cat <<EOF
Usage: sk-example [--flags] <arg>

Decision flags (required under --yes):
  --domain <name>   Domain to operate on
  --port <n>        Port (default: 443)

Standard flags:
  --help, -h        Show this help
  --yes, -y         Non-interactive mode
  --dry-run, -n     Show what would happen
  --log             Log to /var/log/linux-skills/
EOF
}

# --- 4. Flag parsing ---------------------------------------------------------
parse_standard_flags "$@"
# (script-specific flags consumed here, removed from REMAINING_ARGS)

# --- 5. Sanity checks --------------------------------------------------------
require_root
require_debian
require_cmd nginx openssl
[[ "$YES" == "1" ]] && require_flag DOMAIN

# --- 6. Main logic -----------------------------------------------------------
header "Example operation"
# ... work happens here via pass/warn/fail/info and run ...
```

## 7. Per-skill manifest (`## Scripts` section)

Every `SKILL.md` that ships scripts must contain a `## Scripts` section. The
installer parses this with a simple grep-based reader — no YAML, no JSON.

### 7.1 Format

```markdown
## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-webstack
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-nginx-new-site | scripts/sk-nginx-new-site.sh | no | Generate a new Nginx vhost with TLS and reload. |
| sk-nginx-test-reload | scripts/sk-nginx-test-reload.sh | yes | Validate Nginx config and reload. |
```

### 7.2 Parser rules

The installer parses by regex: any markdown table row under a line matching
`^## Scripts` is treated as a script entry. Columns in order:

1. **Script** — the binary name (without `.sh`).
2. **Source** — path relative to repo root.
3. **Core?** — `yes` or `no`. `yes` means `install-skills-bin core` picks it up.
4. **Purpose** — one line, human-readable. Ignored by the installer.

Leading and trailing `|` and whitespace are stripped. Header and separator
rows are skipped (detected by presence of `---`).

## 8. Directory layout

```
linux-skills/
├── CLAUDE.md                     # project instructions, loaded by Claude
├── README.md
├── docs/
│   └── engine-design/            # this directory
│       ├── README.md
│       ├── spec.md               # <you are here>
│       └── script-inventory.md
├── scripts/
│   ├── lib/
│   │   └── common.sh             # shared library (NOT yet written)
│   ├── install-skills-bin        # installer (NOT yet written)
│   ├── sk-audit.sh               # renamed from server-audit.sh
│   ├── sk-mysql-backup.sh
│   ├── sk-nginx-new-site.sh
│   └── ... (see inventory)
├── linux-bash-scripting/         # the meta-skill (NEW)
│   ├── SKILL.md
│   └── references/
│       ├── script-template.sh
│       ├── common-sh-contract.md
│       └── interactive-ux.md
├── linux-sysadmin/               # hub
│   └── SKILL.md
├── linux-network-admin/          # (NEW)
├── linux-dns-server/             # (NEW)
├── linux-mail-server/            # (NEW)
├── linux-virtualization/         # (NEW)
├── linux-cloud-init/             # (NEW)
├── linux-package-management/     # (NEW)
├── linux-config-management/      # (NEW)
├── linux-observability/          # (NEW)
├── linux-secrets/                # (NEW)
└── linux-*/                      # the 14 existing specialist skills
```

Runtime paths on a managed server:

```
/usr/local/bin/sk-*                    # installed scripts
/usr/local/lib/linux-skills/common.sh  # shared library
/var/log/linux-skills/                 # script logs (--log)
/etc/linux-skills/                     # persistent state (rare)
~/.claude/skills/                      # the repo clone
```

## 9. Safety rules

These are non-negotiable for every script.

1. **Read `common.sh`** — never reimplement colors, prompts, confirm, or die.
2. **Quote every variable** — `"$var"`, not `$var`. Use `shellcheck` as CI.
3. **`IFS= read -r`** — for every `read`. No exceptions.
4. **`set -uo pipefail`** — always. Do not set `-e` (it interacts badly with
   traps and function returns); instead, handle errors explicitly or via
   `die`.
5. **Register a cleanup trap** before creating any temp file.
6. **Atomic file edits** — never `> file` on something important. Use
   `atomic_write` or `backup_file` + edit.
7. **Confirm destructive operations** — via `confirm_destructive`, which
   demands an explicit `yes` (not `y`) in interactive mode and a decision flag
   in `--yes` mode.
8. **Every script supports `--dry-run`** and must be testable end-to-end with
   it.
9. **Every script supports `--help`** and the help text must list every
   decision flag that becomes required under `--yes`.
10. **Validate before mutating** — always run `nginx -t`, `apache2ctl
    configtest`, `visudo -c`, `sshd -t`, etc. before reloading.
11. **Input validation with `case`, not sprawling regex** — per *Pro Bash*.
12. **No `eval` on untrusted input, ever.**
13. **Exit codes:** `0` success, `1` generic failure, `2` usage/flag error,
    `3` precondition failed, `4` user aborted, `5` dependency missing.
14. **Log where it matters** — destructive operations write a timestamped
    entry to `/var/log/linux-skills/<script>.log` regardless of `--log`.

## 10. What this session produces vs. what comes next

**This session (planning):**
- This spec file.
- `script-inventory.md` — the curated list of ~90 scripts.
- 10 new `SKILL.md` files (the new skills).
- Updates to the 14 existing `SKILL.md` files to add `## Scripts` manifests.
- Hub routing update in `linux-sysadmin/SKILL.md`.

**Not this session (implementation — next session):**
- `scripts/lib/common.sh` — the shared library.
- `scripts/install-skills-bin` — the installer.
- Migration of existing scripts (`server-audit.sh` → `sk-audit.sh`, etc.).
- The ~90 scripts in the inventory, built in priority order.
- `shellcheck` CI wiring.
- Integration testing (a VM-backed smoke test of each script with
  `--dry-run`).

## 11. Open questions deferred to implementation session

- Should `common.sh` be installed to `/usr/local/lib/linux-skills/` (clean) or
  `/usr/local/bin/sk-lib.sh` (co-located)? Leaning clean.
- Should scripts source the library from the repo (development mode) or from
  the installed path (production mode)? Leaning: sniff `/usr/local/lib/...`
  first, fall back to `$SCRIPT_DIR/lib/common.sh`.
- How do we test destructive scripts without trashing a server? Proposal: a
  dedicated LXD container target that scripts can operate on in CI.
- Do we want a `sk` command that lists and runs all `sk-*` scripts interactively?
  (Deferred — not essential for v1.)
