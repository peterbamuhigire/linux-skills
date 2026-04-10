---
name: linux-bash-scripting
description: Write interactive, secure, powerful Bash scripts for the linux-skills engine. Defines the canonical script template, the common.sh library contract, standard flags, interactive UX rules, and safety patterns every `sk-*` script must follow. Use before writing or reviewing any script in this repo.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Bash Scripting — the meta-skill

This skill is the foundation every other script in `linux-skills` is built on.
Before writing a new `sk-*` script, or reviewing an existing one, load this
skill.

It defines:

1. The canonical script template (six-section layout from *Pro Bash*).
2. The `common.sh` library contract (what functions exist, what they do).
3. The standard flag set every script must support.
4. Interactive UX rules (prompts, confirmations, output).
5. Safety patterns every script must follow.
6. How Claude Code invokes these scripts non-interactively.

Read the full engine spec in [`docs/engine-design/spec.md`](../docs/engine-design/spec.md)
and the script catalogue in [`docs/engine-design/script-inventory.md`](../docs/engine-design/script-inventory.md)
for context.

---

## When to use this skill

- Before writing any new script in `scripts/`.
- Before reviewing a script that another person (or another Claude session) wrote.
- When asked "how do I make a script interactive / secure / safe / dry-runnable / help-printing?"
- When unsure which library function to call from `common.sh`.

## When NOT to use this skill

- For one-liners and ad-hoc commands (don't over-engineer a `grep`).
- For Python, Node.js, Go, or any non-Bash tooling.
- For scripts that will never live in this repo (e.g. throwaway fixes).

---

## The canonical script template

Every `sk-*` script must start from this six-section layout. See
[`references/script-template.sh`](references/script-template.sh) for a
copy-pasteable version. To create a new script, the recommended flow is:

```bash
sudo sk-new-script <skill-name> <script-name>   # scaffolds from template
```

The six sections in order:

1. **Metadata header** — `#:` prefixed comments with Title, Synopsis,
   Description, Author, Contact, Version. Grep-extractable. Author line must
   always read `#: Author:  Peter Bamuhigire <techguypeter.com>`.
2. **Library + safety** — `set -uo pipefail` then `source` of `common.sh`.
   Never use `set -e` (it interacts badly with traps and function return
   codes).
3. **Defaults** — every tunable as a top-level variable with its default. No
   magic numbers deep in the script.
4. **Functions** — helpers, including a `usage()` that prints every flag the
   script accepts.
5. **Flag parsing** — call `parse_standard_flags "$@"`, then parse
   script-specific decision flags from `REMAINING_ARGS`.
6. **Sanity checks** — `require_root`, `require_debian`, `require_cmd`, and
   any `require_flag` calls for `--yes` mode.
7. **Main logic** — the work, expressed via `header`, `pass`, `warn`, `fail`,
   `info`, and `run`.

---

## The `common.sh` library contract

`common.sh` is the shared library every script sources from
`/usr/local/lib/linux-skills/common.sh`. The full function contract lives in
[`references/common-sh-contract.md`](references/common-sh-contract.md) — read
it before calling a new function. Summary:

### Output

| Function | Purpose |
|---|---|
| `pass "msg"` | Green `[PASS]` line; increments `PASS_COUNT`. |
| `warn "msg"` | Yellow `[WARN]` line; increments `WARN_COUNT`. |
| `fail "msg"` | Red `[FAIL]` line; increments `FAIL_COUNT`. |
| `info "msg"` | Cyan `[INFO]` line; no count. |
| `header "Section"` | Bold section separator. |
| `die "msg" [exit_code]` | Red error to stderr, exit with code (default 1). |
| `log "msg"` | Timestamped line to log file (if `--log`). |

Always use these. Never roll your own `echo -e "\033[31m..."`.

### Guards

| Function | Purpose |
|---|---|
| `require_root` | Exit 1 if not root. |
| `require_debian` | Exit 3 if `/etc/os-release` isn't Debian/Ubuntu. |
| `require_cmd <cmd>...` | Exit 5 if any command is missing; names the package. |
| `require_flag <NAME>` | Under `--yes`, exit 2 if the named global variable is empty. |

### Interaction (skipped under `--yes`)

| Function | Purpose |
|---|---|
| `confirm "Do X?" [default=N]` | yes/no; default = N. Auto-yes under `--yes` **only** for non-destructive confirms. |
| `confirm_destructive "About to DELETE X"` | Requires typed `yes`, not `y`. Under `--yes`, requires a decision flag — **never** auto-confirms. |
| `prompt "Label" [default] [validator]` | Single-value read with optional default + validator. |
| `select_one "Label" opt1 opt2...` | Numeric menu; returns chosen value. |

### Safe file operations

| Function | Purpose |
|---|---|
| `safe_tempfile [prefix]` | `mktemp` + trap cleanup. Returns path. |
| `safe_tempdir [prefix]` | As above, directory. |
| `atomic_write <target>` | Reads stdin, writes `<target>.new`, `mv` on success. Preserves perms/owner. |
| `backup_file <path>` | Copies to `<path>.bak-YYYYMMDD-HHMMSS`. Prints backup path. |

### Flag parsing

| Function | Purpose |
|---|---|
| `parse_standard_flags "$@"` | Consumes standard flags, sets `DRY_RUN`, `YES`, `LOG_FILE`, `JSON`, `VERBOSE`, `QUIET`. Leaves unknown args in `REMAINING_ARGS`. |
| `run <cmd>...` | Prints the command. In `--dry-run`, prints and skips. |

---

## Standard flags — mandatory on every script

Every script must support these flags via `parse_standard_flags`:

| Flag | Meaning |
|---|---|
| `--help`, `-h` | Print `usage()` and exit 0. Must list every decision flag. |
| `--version` | Print version and exit 0. |
| `--yes`, `-y` | Non-interactive. **Errors** if a required decision flag is missing — never silently defaults. |
| `--dry-run`, `-n` | Print every action, change nothing. |
| `--log[=PATH]` | Tee output to `/var/log/linux-skills/<script>-YYYYMMDD-HHMMSS.log`. |
| `--json` | Machine-readable output (where meaningful). No colors. |
| `--verbose`, `-v` | Extra diagnostics. |
| `--quiet`, `-q` | Errors and final result only. Incompatible with `-v`. |

### The `--yes` contract (non-negotiable)

`--yes` means **"the caller has pre-committed to every decision"**. It does
**not** mean "accept safe defaults." If a script would normally prompt for a
required input and the caller did not supply a flag for it, the script must
abort:

```
ERROR: --yes was passed but --domain is required.
       Run `<script> --help` to see required flags.
```

This rule exists because Claude Code invokes scripts non-interactively and
must get exactly the outcome it asked for — silent defaults are a footgun.

---

## Interactive UX rules

When running interactively (no `--yes`), scripts must feel friendly at a
terminal. See [`references/interactive-ux.md`](references/interactive-ux.md)
for the full rule set. Key points:

- **Announce before acting.** Every destructive step prints what it is about
  to do, then asks to confirm.
- **Show progress.** Long-running steps use `header` to mark phases.
- **PASS / WARN / FAIL is the output grammar.** Use `pass`, `warn`, `fail`,
  `info` — never ad-hoc `echo`.
- **Explain failures.** When a check fails, say *why* in plain English and
  point at the remediation (another `sk-*` script, a config file, a man page).
- **Colors are semantic.** Green = good; yellow = watch; red = broken;
  cyan = neutral information. Never decorate.
- **Confirm destructive operations with a typed word, not a single letter.**
  Use `confirm_destructive`, which requires the user to type `yes`.
- **`Ctrl-C` is a first-class exit path.** The trap installed by `common.sh`
  ensures a clean exit. Don't fight it.
- **Help text must be complete.** Every decision flag listed. Examples
  included. Fits on one screen where possible.

---

## Safety patterns every script must follow

These rules are enforced by `sk-lint` (the pre-commit linter) and checked in
code review. Violations block a merge.

1. **Source `common.sh`** — never reimplement colors, prompts, traps.
2. **`set -uo pipefail`** — always. **Never** `set -e`.
3. **Quote every variable** — `"$var"`, `"${array[@]}"`, always.
4. **`IFS= read -r`** — every `read`, every time.
5. **Parameter expansion over sed/awk** — `${var##*/}` for basename,
   `${var%.*}` for removing a suffix. Faster and safer than subprocessing.
6. **Atomic file edits** — write to `$target.new`, then `mv`. Never `> file`
   on anything important. Use `atomic_write` or `backup_file` first.
7. **Safe temp files** — `safe_tempfile`, which auto-registers a cleanup trap.
8. **Validate with `case`, not sprawling regex** — from *Pro Bash*. Easier to
   read, easier to extend, easier to debug.
9. **`printf` over `echo`** — `printf '%s\n' "$var"`. `echo`'s behavior varies.
10. **`"$@"` (quoted)** when forwarding args. Unquoted `$@` word-splits.
11. **Exit codes matter** — `0` success, `1` generic failure, `2`
    usage/flag error, `3` precondition failed, `4` user aborted, `5`
    dependency missing.
12. **Never `eval` untrusted input.** No exceptions.
13. **Validate external configs before reload** — `nginx -t`, `apache2ctl
    configtest`, `visudo -c`, `sshd -t`, `named-checkconf`. Every time.
14. **Destructive operations write a timestamped audit line** to
    `/var/log/linux-skills/<script>.log` regardless of `--log`.
15. **Every script passes `shellcheck` with zero warnings.** Run `sk-lint`
    before committing.

---

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-bash-scripting
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-new-script | scripts/sk-new-script.sh | yes | Scaffold a new `sk-*` script from the canonical template in a skill's `scripts/` directory. |
| sk-lint | scripts/sk-lint.sh | yes | Run `shellcheck` plus custom engine checks (standard flags present, `common.sh` sourced, no `set -e`, no unquoted vars) on one or more scripts. |

---

## How Claude Code invokes these scripts

When Claude Code is asked to do something that maps to a script in this
toolkit, it must:

1. **Discover** — check `command -v sk-foo` to see if the script is
   installed. If not, suggest `sudo install-skills-bin <skill-name>`.
2. **Read help** — run `sk-foo --help` to see the required decision flags.
3. **Pre-commit** — decide every required input up front (domain, user,
   port, path, etc.). Never call with `--yes` and hope a default saves the day.
4. **Dry-run first** — when uncertain, run with `--dry-run --yes --<flags>`
   to preview.
5. **Invoke** — run with `--yes --log --<flags>`.
6. **Interpret** — parse PASS/WARN/FAIL counts from output; if `--json` is
   supported, use it.

If any step of this loop isn't possible (e.g. the script doesn't have the
flag we need), that's a script bug — file it against the inventory, not a
silent workaround.

---

## References

- [`references/script-template.sh`](references/script-template.sh) — the canonical six-section template.
- [`references/common-sh-contract.md`](references/common-sh-contract.md) — full function contract for the shared library.
- [`references/interactive-ux.md`](references/interactive-ux.md) — interactive UX rules in detail.
- [`docs/engine-design/spec.md`](../docs/engine-design/spec.md) — the binding engine specification.
- [`docs/engine-design/script-inventory.md`](../docs/engine-design/script-inventory.md) — the curated catalogue.
