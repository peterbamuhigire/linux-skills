---
name: linux-bash-scripting
description: "Use when writing or reviewing portable sk-* Bash scripts for this engine, including common.sh primitives, flags, dry runs, and safety gates; use linux-repo-sync for Git-update behaviour and not for one-off commands."
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Bash Scripting — the meta-skill

## Distro support

This meta-skill is **how** sk-* scripts stay two-family. A script must never
hardcode `apt`, `ufw`, or `apache2` — it calls the `common.sh` primitives, which
resolve to the right tool for the detected family (Debian/Ubuntu or the RHEL
family: Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle).

| Need | Don't hardcode | Use this primitive |
|---|---|---|
| Detect the family | parse `/etc/os-release` | `detect_distro` → `SK_DISTRO_FAMILY`, `SK_PKG` |
| Install packages | `apt install` / `dnf install` | `pkg_install <pkg>...` |
| Query installed | `dpkg -s` / `rpm -q` | `pkg_is_installed <pkg>` |
| Enable extra repo | `add-apt-repository` / EPEL | `ensure_epel` (no-op off-RHEL & on Fedora) |
| Service unit name | `apache2` / `httpd` | `svc_name apache` |
| Open a firewall port | `ufw allow` / `firewall-cmd` | `firewall_allow <port|service>` |
| Web config dir / reload | `sites-available` / `conf.d` | `web_conf_dir`, `web_reload` |
| Gate the script | check `$ID` | `require_family <debian|rhel|any>` |

Full contract: [`references/common-sh-contract.md`](references/common-sh-contract.md).
Plan: [`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

<!-- dual-compat-start -->

## Use when

- Writing a new `sk-*` script in this repository.
- Reviewing or refactoring an existing script under `scripts/`.
- Checking whether a script matches the engine contract, flag model, and safety rules.

## Do not use when

- The task is a one-off shell command or an operational fix that will not become a repo script.
- The implementation language is not Bash.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Target skill, script name, and inventory entry | Request and script inventory | yes | Stop before scaffolding an unowned script |
| Behaviour, inputs, decision flags, and side effects | Operator and owning specialist skill | yes | Produce a review/questions list; do not invent defaults |
| Distro support and service/package mappings | Owning skill and `common.sh` contract | yes | Require `any` only when both families are verified |
| Test fixtures and mutation authority | Maintainer and safe test host | for execution | Limit work to static review and dry-run design |

## Capability Contract

Review uses read/search access and is read-only by default. Editing an owned script requires explicit implementation authority; executing privileged or destructive paths requires separate test-host approval. Never use production state to discover what an unsafe script does.

## Degraded Mode

Without shellcheck, a Bash runtime, root, or both distro families, complete static checks and label runtime, privilege, or family behaviour unassessed. Do not claim portability or safety from source inspection alone.

## Decision Rules

| Choice | Action | Failure avoided |
|---|---|---|
| Input requires a prompt | Add a named decision flag and `require_flag` under `--yes` | Invented unattended defaults |
| Operation changes important config | Backup, atomic write, native validation, then reload | Partial config and outage |
| Package/service differs by family | Use `common.sh` primitive | Debian-only automation |
| Operation is destructive | Typed confirmation plus explicit non-interactive flag | Accidental deletion |

## Workflow

For every mutating `sk-*` script, apply the safe reversible operations standard: detect the family, capture a before state, support a dry-run or no-op path, make the operation idempotent, use atomic writes where files change, preserve ownership/labels, and expose a bounded rollback or recovery path. A script is not release-ready until its success path, already-correct path, invalid-input path, and rollback/recovery evidence are tested for both distro families or explicitly marked unassessed.

1. Read the owning skill, engine spec, inventory, template, and `common.sh` contract.
2. Define inputs, effects, decisions, exit codes, rollback, and family support; stop on an unresolved destructive default.
3. Scaffold or review the six-section structure and standard flags.
4. Implement through shared primitives with quoted inputs, safe temp files, backups, and native validators.
5. Test help, bad inputs, `--yes`, dry run, interruption, idempotency, and both families where claimed.
6. Recover failed mutation from backup, then run shellcheck/engine lint and reconcile manifest documentation.

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Script validation evidence | Includes shellcheck/engine lint, help, dry run, negative paths, distro matrix, diff, and manifest alignment |

## Quality standards

- Every script must be safe, idempotent by default, and compatible with human and agent callers.
- `common.sh` is mandatory; do not reinvent shared behavior.
- Help output, failure modes, and validation-before-reload rules must be explicit.

## Anti-patterns

- Bypassing `common.sh`. Fix: use its output, guard, package, service, and file primitives.
- Treating `--yes` as permission to invent defaults. Fix: require every decision flag.
- Shipping without a manifest entry. Fix: reconcile the owning skill and inventory.
- Using `set -e`. Fix: handle expected failures and preserve `set -uo pipefail`.
- Writing important files with direct redirection. Fix: back up and use atomic writes.
- Claiming family portability after one-family testing. Fix: test both or mark one unassessed.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Conforming script or review | Maintainer | Contract, flags, safety, and family rules are satisfied |
| Test evidence | Reviewer | Covers help, errors, dry run, destructive gates, and lint |
| Manifest update | Installer | Script source, name, core status, and purpose agree |

## Worked Example

For `sk-cifs-mount`, make share, mount point, and credentials source explicit flags. Under `--yes`, missing any required choice exits 2; dry run prints package, credential-file, mount, and fstab actions without exposing the password or writing files.

<!-- dual-compat-end -->

## References

- [`../../docs/continuous-improvement/safe-reversible-operations-standard.md`](../../docs/continuous-improvement/safe-reversible-operations-standard.md)
- [`../../docs/continuous-improvement/two-family-validation-and-recovery.md`](../../docs/continuous-improvement/two-family-validation-and-recovery.md)

- [`references/script-template.sh`](references/script-template.sh)
- [`references/common-sh-contract.md`](references/common-sh-contract.md)
- [`references/interactive-ux.md`](references/interactive-ux.md)
- [`docs/engine-design/spec.md`](../../docs/engine-design/spec.md)

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

Read the full engine spec in [`docs/engine-design/spec.md`](../../docs/engine-design/spec.md)
and the script catalogue in [`docs/engine-design/script-inventory.md`](../../docs/engine-design/script-inventory.md)
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
6. **Sanity checks** — `require_root`, `require_family <debian|rhel|any>`,
   `require_cmd`, and any `require_flag` calls for `--yes` mode.
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
| `require_family <debian\|rhel\|any>` | Exit 3 if the detected family isn't allowed. Gate a script to one family, or pass `any` for both. Prefer this over the legacy `require_debian`. |
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
- [`docs/engine-design/spec.md`](../../docs/engine-design/spec.md) — the binding engine specification.
- [`docs/engine-design/script-inventory.md`](../../docs/engine-design/script-inventory.md) — the curated catalogue.
