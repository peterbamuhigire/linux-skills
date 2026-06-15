---
name: linux-file-integrity
description: File Integrity Monitoring (FIM) with AIDE on Debian/Ubuntu and RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Build the baseline database (aideinit / aide --init), run drift checks (aide --check), accept legitimate changes (aide --update), schedule nightly checks with a systemd timer or cron, tune /etc/aide.conf (or /etc/aide/aide.conf.d/) rule groups, handle the RHEL vs Debian packaging and path differences, and store the baseline DB safely off-box so an attacker cannot edit it. AIDE answers "which files changed since we last knew they were good?" — pair it with linux-auditd-rules for attribution and linux-benchmark-scanning for compliance scoring.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Linux File Integrity Monitoring (AIDE)

## Distro support

Two-family skill. **AIDE** runs on both families, but the packaging and paths
differ more than most tools: Debian/Ubuntu wraps AIDE in helper scripts
(`aideinit`, `update-aide.conf`) and splits config into `/etc/aide/` with a
`aide.conf.d/` drop-in dir; the RHEL family ships plain upstream AIDE with a
single `/etc/aide.conf` and uses `aide --init` directly. Body uses
Debian/Ubuntu; substitute per this matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Install | `apt install aide aide-common` | `dnf install aide` |
| Main config | `/etc/aide/aide.conf` (+ `aide.conf.d/`) | `/etc/aide.conf` (single file) |
| Build baseline | `aideinit` (wrapper) | `aide --init` |
| New DB path | `/var/lib/aide/aide.db.new` | `/var/lib/aide/aide.db.new.gz` |
| Trusted DB path | `/var/lib/aide/aide.db` | `/var/lib/aide/aide.db.gz` |
| Regenerate config | `update-aide.conf` | edit `/etc/aide.conf` directly |
| Run check | `aide --check` | `aide --check` (same) |
| Accept changes | `aideinit` + copy, or `aide --update` | `aide --update` + copy |

AIDE answers **"which files have changed since we last knew they were
good?"** It hashes watched paths into a baseline database, then reports drift
on each check. It is the *drift* layer of compliance auditing; pair it with
attribution (`linux-auditd-rules`, auditd) and benchmark scoring
(`linux-benchmark-scanning`, OpenSCAP/Lynis). See
[`../../docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Installing AIDE and building the first baseline on a known-clean host.
- Running a drift check (`aide --check`) and triaging the report.
- Accepting legitimate changes by updating the baseline.
- Tuning `/etc/aide.conf` rule groups, or scheduling nightly checks.
- Deciding how to store the baseline DB safely off-box.

## Do not use when

- The task is attributing *who* changed a file; use `linux-auditd-rules` (auditd).
- The task is a benchmark/compliance scan with a score; use `linux-benchmark-scanning`.
- The task is rootkit signature scanning; use `linux-intrusion-detection` (rkhunter/chkrootkit).

## Required inputs

- Whether the host is known-clean (a baseline built on a compromised host is worthless).
- Which paths matter (system binaries, `/etc`, web root) and which are noisy (logs, caches).
- Whether a reported change is legitimate (accept it) or suspicious (investigate).

## Workflow

1. Install AIDE and build the baseline on a freshly provisioned, not-yet-exposed host.
2. Smoke-test: `aide --check` reports no differences; touch a file and confirm it appears.
3. Tune the config so deploys and log churn don't flood the report.
4. Schedule a nightly check that mails or alerts only on real drift.
5. On a report: triage by path (binary drift = critical), then either accept (`aide --update`) or escalate.
6. Store the baseline DB off-box; an on-box DB an attacker can rewrite is no integrity check.

## Quality standards

- Build the baseline only on a host you *know* is clean.
- Treat any hash change in `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`, `/usr/local/*bin` as critical until proven benign.
- Keep a written log of every accepted baseline update and why.
- Protect or externalise the baseline DB so it cannot be silently rewritten.

## Anti-patterns

- Running `aideinit`/`aide --init` on a server already exposed to the internet.
- Re-baselining blindly after a suspicious change ("make the alert go away").
- Leaving the trusted DB world-readable/writable on the same host AIDE protects.
- Watching `/var/log`, `/tmp`, `/proc` without `!` ignores — every run then reports noise.

## Outputs

- The baseline state (built, verified) or the drift report with a triage verdict per path.
- The accept/escalate decision and, if accepted, the logged reason.
- Confirmation the DB is stored safely off-box.

## References

- [`references/aide-reference.md`](references/aide-reference.md) — install, init, config tuning, reading the report, accepting changes, scheduling (timer/cron), and off-box DB storage, both families.

**This skill is self-contained.** Every command below is standard AIDE on its
family (see **Distro support** for the package and path substitutions). The
`sk-*` scripts in the **Optional fast path** section are convenience
wrappers — never required.

## AIDE: install and build the baseline

> Build the baseline on a host you **know** is clean — right after
> provisioning, before it is ever exposed. Baselining a compromised host just
> records the compromise as "normal."

```bash
# Debian/Ubuntu
sudo apt install aide aide-common
sudo aideinit                                       # 1-10 min: hashes watched paths
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# RHEL family
sudo dnf install aide
sudo aide --init
sudo cp /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
```

Smoke test:

```bash
sudo aide --check        # expect: "found NO differences"
sudo touch /etc/test-aide && sudo aide --check   # now reports test-aide added
sudo rm /etc/test-aide
```

## AIDE: run a check

```bash
sudo aide --check                     # full check; exit 0 = clean, 1-15 = drift, 16+ = error
sudo aide --check --log-level=warning # quiet, for cron
sudo aide --check --limit='^/etc/ssh' # one path
```

Reading the report (flag string, exit codes) and the per-path triage flow are
in [`references/aide-reference.md`](references/aide-reference.md).

## AIDE: accept legitimate changes (update the baseline)

After a confirmed-legitimate change (package upgrade, config edit), refresh
the baseline so the next run starts clean:

```bash
# Debian/Ubuntu
sudo aideinit && sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# RHEL family
sudo aide --update && sudo cp /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

sudo aide --check        # confirm: no differences

# Log the accepted change
echo "$(date -Iseconds) aide baseline updated after nginx upgrade" \
    | sudo tee -a /var/log/linux-skills/aide-baseline-updates.log
```

## AIDE: tune the config

The Ubuntu package splits config into `/etc/aide/aide.conf` plus
`/etc/aide/aide.conf.d/` drop-ins (regenerate with `update-aide.conf`); the
RHEL family uses a single `/etc/aide.conf`. Rules pair a path with a named
check group:

```
/etc/ssh/   NORMAL        # perms+owner+group+size+mtime+hashes
/var/log/   Logs          # perms+owner only (logs grow legitimately)
!/var/cache               # ignore (the ! prefix)
```

The full rule-group catalogue, a ready-to-drop strict ruleset, and ignore
lists are in [`references/aide-reference.md`](references/aide-reference.md).

## AIDE: schedule nightly checks

```bash
sudo tee /etc/cron.daily/aide-check > /dev/null <<'EOF'
#!/bin/bash
# Nightly AIDE check — mail the report only when drift is found
set -u
REPORT=$(aide --check 2>&1 || true)
if echo "$REPORT" | grep -q "found differences"; then
    echo "$REPORT" | mail -s "AIDE Report $(hostname) $(date +%Y-%m-%d)" root
fi
EOF
sudo chmod +x /etc/cron.daily/aide-check
```

A systemd-timer alternative and a critical-paths-only filter are in
[`references/aide-reference.md`](references/aide-reference.md). Ensure an MTA
delivers root mail to a human — see `linux-mail-server`.

## AIDE: store the baseline off-box

The trusted DB is the only thing that makes AIDE trustworthy. An attacker who
edits both a binary *and* the on-box DB defeats the check silently. Copy the
DB to a write-once or remote location after every (re)baseline, and compare
against that copy before trusting a check. Detail in
[`references/aide-reference.md`](references/aide-reference.md).

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-file-integrity` installs:

| Task | Fast-path script |
|---|---|
| First-time AIDE install + init + nightly schedule | `sudo sk-file-integrity-init` |
| Run AIDE check, classify drift, alert on binary changes | `sudo sk-file-integrity-check` |

These are optional wrappers around `aide`. The commands above are the source
of truth. (The script sources are declared in the
`linux-intrusion-detection` manifest, which retains them for backward
compatibility; this skill documents their use.)

## Scripts

These scripts are declared in the `linux-intrusion-detection` skill's
manifest (they predate this category and are kept there to avoid breaking
existing installs). Install them via:

```bash
sudo install-skills-bin linux-intrusion-detection
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-file-integrity-init | scripts/sk-file-integrity-init.sh | no | Initialize the AIDE database on a known-clean host, verify the baseline, and install a nightly check. |
| sk-file-integrity-check | scripts/sk-file-integrity-check.sh | no | Run an AIDE check, summarize the changes, classify them (config/log/binary), and alert on binary drift. |
