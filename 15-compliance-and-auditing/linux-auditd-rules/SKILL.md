---
name: linux-auditd-rules
description: Use when inspecting, designing, testing, persisting, or querying auditd rules for forensic attribution on Debian/Ubuntu or RHEL-family hosts. Covers watches, syscalls, loss, and immutable mode; use linux-file-integrity for drift and linux-benchmark-scanning for scoring.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Linux Audit Daemon (auditd) Rules

## Distro support

Two-family skill. **auditd is the same daemon on both families** — same
`auditctl` syntax, same `/etc/audit/rules.d/*.rules`, same `ausearch` /
`aureport`. Only the package step and the source of pre-built compliance
rulesets differ. The RHEL family additionally surfaces **SELinux AVC**
denials through the same audit log, so `ausearch -m AVC` is a RHEL-side
bonus signal. Body uses Debian/Ubuntu; substitute per this matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Install | `apt install auditd audispd-plugins` | `dnf install audit` (usually preinstalled) |
| Daemon / unit | `auditd` | `auditd` (same) |
| Rule drop-ins | `/etc/audit/rules.d/*.rules` | `/etc/audit/rules.d/*.rules` (same) |
| Compile + load | `augenrules --load` | `augenrules --load` (same) |
| Daemon config | `/etc/audit/auditd.conf` | `/etc/audit/auditd.conf` (same) |
| Log file | `/var/log/audit/audit.log` | `/var/log/audit/audit.log` (same) |
| Pre-built compliance rules | hand-authored / upstream samples | `scap-security-guide` → `/usr/share/audit/sample-rules/` (PCI-DSS, CIS, STIG) |
| AVC denials as audit events | AppArmor (not in audit.log) | **SELinux** (`ausearch -m AVC`, `aureport --avc`) |
| Auth log correlated with audit | `/var/log/auth.log` | `/var/log/secure` |

auditd answers **"who did what, and when?"** by hooking the kernel audit
subsystem. It complements the other two compliance layers: file-hash drift
(`linux-file-integrity`, AIDE) and benchmark scanning
(`linux-benchmark-scanning`, OpenSCAP/Lynis). See
[`../../docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md) and the
SELinux reference in
[`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md).

<!-- dual-compat-start -->
## Use When

- Adding, listing, or deleting audit rules with `auditctl` or persisting them in `/etc/audit/rules.d/`.
- Watching files (`-w`) or syscalls (`-a always,exit`) for a compliance or forensic requirement.
- Searching the audit trail with `ausearch`/`aureport` to attribute a change to a user.
- Locking the rule set immutable (`-e 2`) or tuning audit-log rotation and buffers.

## Do Not Use When

- The task is detecting file-content drift by hash; use `linux-file-integrity` (AIDE).
- The task is a benchmark/compliance scan with a score; use `linux-benchmark-scanning` (OpenSCAP/Lynis).
- The task is blocking abusive IPs or rootkit scanning; use `linux-intrusion-detection`.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Attribution/compliance objective, exact paths/syscalls, architectures, and key | Control owner and system inventory | yes | Stop rule design; do not deploy broad guesses. |
| Existing rules, event rate, backlog/loss state, and log capacity | Read-only host inspection | yes | Return a proposed read-only assessment plan. |
| Persistence, immutable-mode, change window, and console recovery approval | Change record | mutation only | Keep runtime inspection; do not load or lock rules. |

## Capability Contract

Default to read-only: read/search rules, status, logs, and reports without changing the host. Runtime/persistent rule changes, daemon config, reload, rotation, and `-e 2` require explicit authority. Immutable mode requires console recovery and separate approval because reversal needs reboot.

## Degraded Mode

Without audit-log access, review supplied rules statically and mark attribution/loss checks `not assessed`. Without workload reproduction, do not claim the rule captures the intended event. Without authority, emit tested commands as a proposal only.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| File watch or syscall rule | Prefer syscall filters for attributable system calls; use narrow file watches where path monitoring is the requirement. | Excess noise or missing attribution. |
| Runtime or persistent | Test runtime first, then persist only a proven rule. | Reboot regression or lost rule. |
| Permission mask | Record only required operations; avoid hot read auditing unless mandated. | Backlog overflow and lost events. |
| Immutable mode | Set `-e 2` only after complete validation and recovery approval. | Locking a broken/noisy ruleset. |

## Workflow

1. Read/search the current rules, daemon/backlog status, log capacity, and relevant events; stop if the target or loss baseline is unknown.
2. Translate the objective into the narrowest keyed rule and review architecture/path coverage.
3. With authority, load the rule at runtime first and generate the intended positive event plus a negative control.
4. Confirm attribution with `ausearch`, event rate, and zero unacceptable loss; abort and delete the runtime rule if noise/loss exceeds the limit.
5. Persist and reload only the proven rule, then verify active and on-disk sets match.
6. Consider `-e 2` only after separate approval. Recover from a failed rule by removing/reverting the drop-in and reloading; immutable failures require the approved reboot path.

## Quality standards

- Every rule carries a descriptive `-k` key so the trail is searchable.
- Persist rules in `rules.d`; never rely on runtime-only `auditctl` across reboots.
- Watch the narrowest path that meets the requirement — broad watches on busy trees lose events.
- Ship the log off-box: an attacker with root can delete `/var/log/audit/`.

## Anti-Patterns

- Auditing reads on hot files. Fix: narrow operations/filters and measure event rate before persistence.
- Leaving `-e 2` set during development. Fix: test runtime, persist, reload, and lock only after approval.
- Treating uninterpreted numeric IDs as final. Fix: preserve raw IDs and add `ausearch -i` for human attribution.
- Ignoring nonzero `lost` counts. Fix: stop acceptance, reduce noise or tune capacity, and rerun the test.
- Deploying rules without keys. Fix: assign stable descriptive keys tied to the control objective.
- Copying a benchmark ruleset wholesale. Fix: map each selected rule to the host architecture, workload, and control.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Rule/control record | Compliance and platform owners | Maps objective to exact keyed rule, scope, persistence, approval, and rollback. |
| Attribution report | Investigator | Positive test identifies expected actor/action/object/time; negative control is excluded. |
| Health evidence | Operator | Active/persistent rules match and backlog/lost metrics remain within declared limits. |

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Rule-load and event evidence | Contains redacted `auditctl` status/list, test event, `ausearch` attribution, event-rate/loss result, and unavailable checks. |

## Worked Example

To attribute edits to `/etc/sudoers`, inspect existing overlap, test a keyed runtime write/attribute rule, make one authorised test change, prove the actor with `ausearch -k`, confirm no loss, then persist. Do not enable immutable mode during this test.
<!-- dual-compat-end -->

## References

- [`references/auditd-reference.md`](references/auditd-reference.md) — install, rule syntax, the rule catalogue, immutable mode, rotation, alerting, and the full `ausearch`/`aureport` cookbook.

**This skill is self-contained.** Every command below is a standard tool on
both families — `auditctl`, `augenrules`, `ausearch`, `aureport` (see
**Distro support** for the one install difference). The `sk-*` script in the
**Optional fast path** section is a convenience wrapper — never required.

## auditd: install and enable

```bash
sudo apt install auditd audispd-plugins        # dnf install audit (usually preinstalled)
sudo systemctl enable --now auditd
sudo systemctl status auditd --no-pager
```

Key paths:

- `/etc/audit/auditd.conf` — daemon config (log location, rotation, buffer).
- `/etc/audit/rules.d/*.rules` — drop-in rule files; combined into
  `/etc/audit/audit.rules` at daemon start via `augenrules`.
- `/var/log/audit/audit.log` — the log (mode 600, root-only).

## Adding rules with auditctl (runtime)

```bash
# Watch a file: -w path  -p perms(r,w,x,a)  -k key
sudo auditctl -w /etc/passwd -p wa -k identity
sudo auditctl -w /etc/ssh/sshd_config -p wa -k sshd_config

# Watch a syscall: -a always,exit -F arch=b64 -S <syscall> -k key
sudo auditctl -a always,exit -F arch=b64 -S execve -F euid=0 -k root_exec

# List / delete / status
sudo auditctl -l
sudo auditctl -D                # delete all rules
sudo auditctl -s                # status: enabled, failure mode, backlog, LOSSES
```

Runtime rules vanish on reboot — validate here, then persist (below).

## Persistent rules in /etc/audit/rules.d/

```bash
sudo tee /etc/audit/rules.d/10-linux-skills.rules > /dev/null <<'EOF'
-D
-b 8192
-w /etc/passwd  -p wa -k identity
-w /etc/shadow  -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd_config
-a always,exit -F arch=b64 -S execve -F euid=0 -k root_exec
# -e 2          # uncomment to lock immutable AFTER the rules are proven
EOF

sudo augenrules --load          # compile rules.d/ into audit.rules and load
sudo auditctl -l | head
```

The full rule catalogue (identity, SSH, web/db config, privileged exec, time,
kernel modules, network) is in
[`references/auditd-reference.md`](references/auditd-reference.md).

On the RHEL family, compliance rulesets ship ready-made — copy a profile
instead of hand-writing:

```bash
sudo dnf install scap-security-guide
sudo cp /usr/share/audit/sample-rules/30-pci-dss-v31.rules /etc/audit/rules.d/
sudo augenrules --load
```

## Immutable mode (-e 2)

End the rule set with `-e 2` to lock it until reboot. An attacker with root
then cannot silently disable auditing mid-incident; rule changes require a
reboot. Use `-e 0` (or omit) during development, flip to `-e 2` once stable.

```bash
sudo auditctl -e 2              # lock now (runtime); also as last line of rules.d
sudo auditctl -s | grep enabled # enabled 2 = immutable
```

## Analysing the trail: ausearch / aureport

```bash
# ausearch — find events; -i interprets uid/gid into names
sudo ausearch -k sudoers -i
sudo ausearch -f /etc/passwd -i
sudo ausearch --start recent -i
sudo ausearch -m AVC -ts recent        # SELinux denials (RHEL family)

# aureport — summaries
sudo aureport --summary
sudo aureport -au --failed             # failed logins
sudo aureport -k --summary             # events by key
```

`auid=` survives `su`/`sudo` — it is the *original* logged-in user, which is
what attribution needs. Full cookbook and example investigations in
[`references/auditd-reference.md`](references/auditd-reference.md).

## Log rotation and losses

Rotation is handled by `auditd` itself via `/etc/audit/auditd.conf`
(`max_log_file`, `num_logs`, `max_log_file_action = ROTATE`). If
`auditctl -s` shows a nonzero `lost`, raise the buffer (`-b 16384`) or narrow
the rules. Detail in
[`references/auditd-reference.md`](references/auditd-reference.md).

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-auditd-rules` installs:

| Task | Fast-path script |
|---|---|
| Audit health: status, losses, rule count, recent key activity | `sudo sk-audit-status` |

This is an optional read-only wrapper around `auditctl`, `ausearch`, and
`aureport`. The commands above are the source of truth.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-auditd-rules
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-audit-status | scripts/sk-audit-status.sh | yes | Read-only auditd health report on both families: daemon state, immutable/enabled flag, loaded rule count, backlog/lost counters, top keys by event volume (aureport -k), and recent AVC denials on the RHEL family. Changes nothing. |
