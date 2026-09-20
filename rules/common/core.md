# Core Rules — Linux Engine

> Distilled from this engine's own `CLAUDE.md`.

## Never hardcode a distro-specific package manager or service name in a script

No `apt`, `ufw`, or `apache2` literal in a script. Use the `common.sh`
primitives instead: `detect_distro`, `pkg_install`, `pkg_is_installed`,
`ensure_epel`, `svc_name`, `firewall_allow`, `web_conf_dir`, `web_reload`. This
is what makes one script work across the Debian/Ubuntu and RHEL families
instead of needing a fork per distro.

*Full template contract:* `linux-bash-scripting` — load before writing or
reviewing any `sk-*` script.

## Every specialist skill states its distro support matrix up front

A `## Distro support` section mapping Debian/Ubuntu commands, paths, and
services to their RHEL-family equivalents is not optional detail — a skill that
omits it is incomplete, because a command that works on Ubuntu silently failing
on Fedora is exactly the failure mode this engine exists to prevent.

## Destructive commands go through the shared gate, not ad-hoc confirmation

`hooks/destructive-bash-gate.js` covers this engine the same as every other —
`rm -rf`, `dd if=`, and firewall-flush commands are exactly the class of
operation a sysadmin engine runs routinely and must never run silently.

## Scope changes to a declared blast radius, not just a pattern match

Checked against ECC's `skills/safety-guard/SKILL.md` (2026-09-20): its
mechanical content — intercepting a fixed list of destructive command
patterns — duplicates what `hooks/destructive-bash-gate.js` already does and
adds nothing new there. Its one genuinely additive idea is **Freeze Mode**:
before a sensitive operation (a production host, an autonomous/unattended
run, a migration), state which directory, host, or service the change is
scoped to, and treat anything outside that declared scope as out of bounds
for this task — ask before touching it, rather than silently widening scope
mid-task. This engine has no hook that mechanically enforces a directory
freeze (unlike the destructive-command gate, which is mechanical); until one
exists, this is operator/agent discipline: name the scope explicitly at the
start of a provisioning, hardening, or migration task, and flag — don't
just act on — any edit or command that falls outside it. This is distinct
from, and in addition to, the distro-support and destructive-command rules
above: those catch *wrong* commands; this catches a *right* command run
against the *wrong* target.

*Second-wave audit note:* a separate pass judged `safety-guard` as a whole
"not worth taking" for this engine, on the reasoning that its mechanical
content is already covered. That judgment holds for the mechanical part;
this rule imports only the Freeze Mode scoping discipline, which that pass
did not evaluate separately.
