---
name: linux-auditd-rules
description: Manage the Linux Audit daemon (auditd) for compliance and forensic attribution on Debian/Ubuntu and RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Add and inspect rules with auditctl, persist them in /etc/audit/rules.d/*.rules and load with augenrules, watch files (-w) and syscalls (-a always,exit), tag events with keys (-k), analyse the trail with ausearch and aureport, lock the rule set immutable (-e 2), and tune buffer/rotation of /var/log/audit/audit.log. auditd is identical across both families; RHEL ships pre-built compliance rulesets (PCI-DSS, CIS, STIG) via scap-security-guide. For automated benchmark scanning use linux-benchmark-scanning; for file-hash drift use linux-file-integrity.
license: MIT
metadata:
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

## Use when

- Adding, listing, or deleting audit rules with `auditctl` or persisting them in `/etc/audit/rules.d/`.
- Watching files (`-w`) or syscalls (`-a always,exit`) for a compliance or forensic requirement.
- Searching the audit trail with `ausearch`/`aureport` to attribute a change to a user.
- Locking the rule set immutable (`-e 2`) or tuning audit-log rotation and buffers.

## Do not use when

- The task is detecting file-content drift by hash; use `linux-file-integrity` (AIDE).
- The task is a benchmark/compliance scan with a score; use `linux-benchmark-scanning` (OpenSCAP/Lynis).
- The task is blocking abusive IPs or rootkit scanning; use `linux-intrusion-detection`.

## Required inputs

- The file path(s) or syscall(s) to audit, and the key (`-k`) to tag them with.
- Whether the change should be runtime-only (`auditctl`) or persistent (`rules.d`).
- Whether the rule set should become immutable (`-e 2`) after loading.

## Workflow

1. Inspect the current rule set (`auditctl -l`) and daemon status (`auditctl -s`).
2. Add the watch or syscall rule, runtime first to validate, then persist in `rules.d`.
3. Load with `augenrules --load`; confirm with `auditctl -l`.
4. Generate the event, then attribute it with `ausearch -k <key> -i`.
5. Once stable, set `-e 2` for production immutability; tune buffer/rotation if events are lost.

## Quality standards

- Every rule carries a descriptive `-k` key so the trail is searchable.
- Persist rules in `rules.d`; never rely on runtime-only `auditctl` across reboots.
- Watch the narrowest path that meets the requirement — broad watches on busy trees lose events.
- Ship the log off-box: an attacker with root can delete `/var/log/audit/`.

## Anti-patterns

- Auditing read (`-p r`) on hot files — floods the log and drops events.
- Leaving `-e 2` set during rule development (every edit then needs a reboot).
- Treating `ausearch` output without `-i` as final — numeric IDs hide the real user.
- Ignoring a nonzero `lost` count in `auditctl -s`.

## Outputs

- The rule added (runtime and/or persistent) and its key.
- The `ausearch`/`aureport` evidence attributing an event.
- Verification that the rule loaded and the daemon is healthy (no losses).

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
