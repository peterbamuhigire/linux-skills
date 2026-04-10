# Interactive UX rules

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Rules for how `sk-*` scripts behave when a human is at the terminal (no
`--yes`). The goal is scripts that a new admin can run with confidence —
communicative, safe, and forgiving.

Informed by *Beginner's Guide to the Unix Terminal* (friendly, explicit,
explain-as-you-go) and *Pro Bash* (structure, validation, safety).

---

## The five rules

### 1. Announce before acting

Every destructive or non-obvious step prints **what it is about to do**
before doing it. Format:

```
=== Harden SSH ===
  [INFO] Backing up /etc/ssh/sshd_config to /etc/ssh/sshd_config.bak-20260410-110523
  [INFO] Setting PermitRootLogin no
  [INFO] Setting PasswordAuthentication no
  [INFO] Will run: sshd -t && systemctl reload ssh
Continue? [y/N]
```

No script should ever silently do something that changes the system.

### 2. Show progress

Long-running work is broken into phases marked with `header`. The operator
should always know *which* phase they are in.

```
=== Phase 1/4: Validating config ===
...
=== Phase 2/4: Backing up existing files ===
...
```

### 3. PASS / WARN / FAIL is the output grammar

The entire vocabulary of script output is:

- `pass` — something is correct or an action succeeded.
- `warn` — something works but could be better.
- `fail` — something is broken or an action failed.
- `info` — neutral information.
- `header` — phase separator.

No ad-hoc `echo "…"`. The operator scans the left-column tag, not your prose.

### 4. Explain failures

When `fail` fires, the next line must say *why* in plain English and *how*
to fix it — preferably by naming another `sk-*` script:

```
  [FAIL] UFW is not active
         → Run: sudo sk-ufw-reset
```

```
  [FAIL] Certificate expires in 4 days
         → Run: sudo sk-cert-renew --domain example.com
```

Never end a session with an unexplained `[FAIL]`.

### 5. Colors are semantic, not decorative

- Green — something works.
- Yellow — something to watch.
- Red — something is broken.
- Cyan — neutral info.
- Bold — section headers only.

Do not use color for emphasis or flair. The operator's brain is trained to
scan the left column; color reinforces, it doesn't replace words.

---

## Confirmations

Three kinds:

### Non-destructive — `confirm "…"`

```bash
if confirm "Install jq now?"; then
    run apt install -y jq
fi
```

Accepts `y`, `yes`, `Y`, `YES`. Default is N. Under `--yes`, auto-accepts.

### Destructive — `confirm_destructive "…"`

```bash
confirm_destructive "About to DELETE ALL UFW rules and start over" \
    || die "User aborted" 4
```

Requires the operator to **type the word `yes`** — single-letter `y` is
rejected. Under `--yes`, the caller must have already passed an explicit
decision flag; this function refuses to auto-confirm.

### Typed value — `prompt "…"`

```bash
DOMAIN=$(prompt "Domain to serve" "" 'case "$1" in *.*) return 0;; *) return 1;; esac')
```

Always has a validator for anything that isn't free-form text. Re-prompts on
invalid input with a short explanation.

---

## Help text

Every script's `--help` output must contain, in order:

1. **One-line usage synopsis** — `sk-foo [OPTIONS] <arg>`.
2. **Description** — one sentence, what the script does.
3. **Decision flags** section — every flag that becomes required under
   `--yes`. Each flag has a default (if any) and a one-line purpose.
4. **Standard flags** section — the common `--help`, `--yes`, `--dry-run`,
   `--log`, `--json`, `--verbose`, `--quiet` block.
5. **Exit codes** — the six standard codes.
6. **Examples** — at least two: one interactive, one non-interactive for
   Claude.
7. **Author** — Peter Bamuhigire `<techguypeter.com>` `+256784464178`.

Target: fits on one 80x40 terminal when piped to `less`. If it's longer,
split the script.

---

## Error recovery

- **`Ctrl-C` always works.** The `common.sh` cleanup trap ensures temp files
  are removed and the log file is closed. Never install a script-local trap
  that swallows `INT`.
- **Mid-script failures roll back where possible.** If a script creates a
  resource and a later step fails, the cleanup trap should undo the first
  step. Use `sk_on_exit <function>` to register rollback.
- **Config changes always use `backup_file` first.** If a later step fails,
  the operator has a `.bak-YYYYMMDD-HHMMSS` file to revert from, and the
  script's error message tells them where it is.

---

## Avoid these anti-patterns

- ❌ Ad-hoc colors: `echo -e "\033[31mBad\033[0m"`. Use `fail`.
- ❌ Silent defaults under `--yes`. Require a flag.
- ❌ `rm -rf` without `confirm_destructive` and `backup_file`.
- ❌ A 200-line script with no `header` calls. Split into phases.
- ❌ `set -e` at the top. Interacts badly with traps and subshells.
- ❌ `echo` instead of `printf`. Portability hazard.
- ❌ Reading `grep -q foo "$file"` to decide an action, then running a
  destructive command without confirming. Use `confirm` after the check.
- ❌ Ending with a `[FAIL]` and no next-step hint.
- ❌ Help text that omits a decision flag. If it's in the script, it's in
  `--help`.
