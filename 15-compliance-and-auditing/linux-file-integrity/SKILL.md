---
name: linux-file-integrity
description: Use when establishing, checking, tuning, or safely updating an AIDE baseline on Debian/Ubuntu or RHEL-family hosts. Covers drift triage, scheduling, and off-box trust; use linux-auditd-rules for attribution and linux-benchmark-scanning for scoring.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
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

<!-- dual-compat-start -->
## Use When

- Installing AIDE and building the first baseline on a known-clean host.
- Running a drift check (`aide --check`) and triaging the report.
- Accepting legitimate changes by updating the baseline.
- Tuning `/etc/aide.conf` rule groups, or scheduling nightly checks.
- Deciding how to store the baseline DB safely off-box.

## Do Not Use When

- The task is attributing *who* changed a file; use `linux-auditd-rules` (auditd).
- The task is a benchmark/compliance scan with a score; use `linux-benchmark-scanning`.
- The task is rootkit signature scanning; use `linux-intrusion-detection` (rkhunter/chkrootkit).

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Known-clean attestation and trusted package/deployment state | Host owner and provenance records | baseline only | Stop; do not establish or update trust. |
| Monitored paths, attributes, exclusions, and alert destination | Control owner | yes | Run read-only config review only. |
| Baseline location/checksum, change ticket, and accept/escalate authority | FIM custody/change process | update only | Preserve current baseline and escalate drift. |

## Capability Contract

Default assessment is read-only: read/search AIDE config, database metadata, and drift output. Installation, baseline creation/replacement, config edits, scheduling, and accepting changes require explicit authority. A drift investigation never updates the baseline implicitly.

## Degraded Mode

Without a trusted baseline, report FIM as unavailable rather than clean. Without off-box comparison or provenance, qualify trust. If noisy paths prevent a complete run, list exclusions and unassessed scope; never convert it to a pass.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Build baseline | Proceed only from a known-clean, patched, attested state. | Blessing attacker modifications. |
| Drift severity | Escalate executable/config hash or ownership changes; contextualise expected volatile attributes. | Missing high-impact tampering. |
| Accept change | Require ticket, package/deployment evidence, and reviewed diff before update. | Blind re-baselining. |
| Baseline custody | Store checksum/database in a separately protected or off-box location. | Attacker rewriting evidence. |

## Workflow

1. Read/search host provenance, AIDE config, baseline custody, and last result; stop if known-clean status is unavailable for baseline work.
2. Define monitored attributes and justified exclusions, then validate configuration syntax.
3. With authority, build the baseline, checksum/copy it to protected custody, and run a clean check.
4. Generate an authorised canary change and confirm AIDE reports it; restore the canary and verify expected state.
5. Schedule bounded checks and alerting, then inspect first execution and delivery.
6. Triage every drift item against trusted package/deployment/change evidence. Block baseline update for unexplained drift.
7. Recover from a bad configuration/baseline by restoring the last trusted database/config and rerunning the canary; update trust only with explicit acceptance authority.

## Quality standards

- Build the baseline only on a host you *know* is clean.
- Treat any hash change in `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`, `/usr/local/*bin` as critical until proven benign.
- Keep a written log of every accepted baseline update and why.
- Protect or externalise the baseline DB so it cannot be silently rewritten.

## Anti-Patterns

- Baselining an exposed, unattested host. Fix: rebuild/attest or validate against trusted package and deployment sources first.
- Re-baselining to silence suspicious drift. Fix: investigate and require evidence-backed acceptance.
- Keeping a writable trusted DB beside the target. Fix: protect separately and retain an off-box checksum/copy.
- Watching volatile trees without exclusions. Fix: scope attributes and exclude justified churn paths.
- Treating "no differences" as host security proof. Fix: state only that monitored attributes match the trusted baseline.
- Updating without a ticket. Fix: record approver, reason, diff, and provenance before database replacement.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Baseline custody record | Control owner | Known-clean basis, config, database path/checksum, protected copy, scope, and exclusions are recorded. |
| Drift triage | Incident/change owner | Each change has severity, provenance, accept/escalate decision, and approver where applicable. |
| Scheduled-check evidence | Operator | Canary detection, run status, alert delivery, and unassessed paths are documented. |

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| FIM evidence pack | Contains baseline checksum/custody, config validation, clean and canary checks, redacted drift report, change provenance, and acceptance/escalation record. |

## Worked Example

After an authorised package update changes `/usr/bin/example`, compare package provenance and the AIDE attributes, verify the ticket and signature, accept only that reviewed delta, protect the new database checksum off-box, and rerun a clean check.
<!-- dual-compat-end -->

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
