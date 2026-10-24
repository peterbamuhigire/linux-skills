# Short paths for scripts users run - 2026-10-24

## Change

A script the user is asked to run is now launched by one line with the shortest path that resolves: a bare `sk-*` name on `PATH`, or `~/<name>.sh` for a one-off. Skill-directory, scratch and temp paths are no longer handed to users, and no script may require an output-path argument.

- New always-on rule in [`rules/common/core.md`](../../rules/common/core.md) and a matching bullet in `AGENTS.md` Working Rules.
- New section "Handing a script to a user" and one anti-pattern in [`linux-bash-scripting`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md): installed `sk-*` first, one-off collectors copied to `~/<name>.sh`, default output next to the script (mode 600, owned by `$SUDO_USER`), one line with no wrapped path, a short checksum and a cleanup line for root scripts.
- Replaced `sudo bash ~/.claude/skills/scripts/server-audit.sh` with `sudo sk-audit` in `linux-security-analysis`, `linux-server-provisioning`, `linux-server-hardening` (two places), `linux-disaster-recovery` and its `restore-procedures.md` reference.

## Why

The replaced command pointed at a file that does not exist. On the validation host `ls ~/.claude/skills/scripts/server-audit.sh` reports "No such file or directory", while `/usr/local/bin/sk-audit` is installed and is the script the `linux-security-analysis` fast-path table already names. A long path also wraps in a terminal and picks up stray newlines when copied. The shortest path was therefore both the correct one and the safer one to paste.

## Evidence

| Check | Result |
|---|---|
| Documented path exists | No. `~/.claude/skills/scripts/server-audit.sh` is absent; `scripts/sk-audit.sh` is the real source and `sk-audit` is on `PATH` |
| `scripts/validate_skills.py --baseline quality-baseline.json` | 48 of 48 skills compliant, no failures, before and after the edit |
| `scripts/routing_smoke_test.py` | 30 of 30 fixtures passed, precision 1.000, before and after the edit |
| `scripts/tests/check-distro-matrix.sh` | 41 passed, 0 failed, before and after the edit |

## Limits and follow-up

- `sudo sk-audit` was not executed in this change: the validation account has no passwordless sudo. Its existence and install location were verified, its behaviour was not re-tested here.
- No external standard, vendor claim or version was admitted, so the Digital Research currentness gate had nothing to verify; its local checkout was not used. This is a user-directed convention.
- `01-provisioning-and-bootstrap/linux-server-provisioning/references/provisioning-steps.md` still carries long `/home/administrator/.claude/skills/scripts/...` paths for `update-all-repos`, `server-audit.sh` and `setup-claude-code.sh`. They do not match the current `scripts/` layout. Fixing them needs the whole provisioning block re-tested on a host, so they are left unchanged and `NOT ASSESSED`.
- `notes/server-security.md` line 39 still symlinks `scripts/server-audit.sh`, which is also absent. It is an administrator setup note, not a skill command, and is left for the same reason.
- `linux-cloud-init` keeps its `runcmd` path: it is run by a machine, which the rule exempts.

*Author: Peter Bamuhigire (techguypeter.com).*
