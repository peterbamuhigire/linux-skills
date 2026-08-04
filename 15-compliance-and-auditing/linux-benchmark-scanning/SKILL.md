---
name: linux-benchmark-scanning
description: Use when running read-only OpenSCAP or Lynis scans, selecting distro-matched profiles, interpreting failures, or drafting remediation on Debian/Ubuntu or RHEL-family hosts. Use linux-auditd-rules for attribution and linux-file-integrity for AIDE drift.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Linux Benchmark & Compliance Scanning

## Distro support

Two-family skill. **OpenSCAP** (`oscap`) and **Lynis** run on both families;
the difference is which **SCAP Security Guide (SSG) datastream** you point
`oscap` at — there is one per distro and major version. On the RHEL family
SSG is first-class (`scap-security-guide`, `openscap-scanner`); on
Debian/Ubuntu the packages exist but profile coverage is thinner, so Lynis
often does more of the work. Body uses the RHEL family for OpenSCAP (where
coverage is strongest) and is family-neutral for Lynis. Substitute per this
matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| OpenSCAP scanner | `apt install openscap-scanner ssg-debderived` | `dnf install openscap-scanner scap-security-guide` |
| SSG datastream dir | `/usr/share/xml/scap/ssg/content/` | `/usr/share/xml/scap/ssg/content/` |
| Datastream file | `ssg-ubuntu2204-ds.xml` (version-specific) | `ssg-rhel9-ds.xml` (version-specific) |
| List profiles | `oscap info <ds.xml>` | `oscap info <ds.xml>` (same) |
| Lynis | `apt install lynis` | `dnf install lynis` (**EPEL** on RHEL/Rocky/Alma) |
| Lynis run | `lynis audit system` | `lynis audit system` (same) |

OpenSCAP gives you **policy compliance** against a formal benchmark (CIS,
STIG, PCI-DSS) with pass/fail per rule and auto-generated remediation. Lynis
gives you a **fast, opinion-rich hardening sweep** with a numeric index and
prioritized suggestions — no formal benchmark, but excellent at surfacing
operational weaknesses (file perms, kernel params, missing tooling). Run
both: OpenSCAP for the audit trail, Lynis for the quick wins. They complement
the other two compliance layers — `linux-auditd-rules` (attribution) and
`linux-file-integrity` (drift). See
[`../../docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

<!-- dual-compat-start -->
## Use When

- Running a CIS / STIG / PCI-DSS scan with OpenSCAP and producing a report.
- Generating a remediation script or Ansible playbook from a scan.
- Running a quick Lynis hardening sweep to get a score and suggestions.
- Choosing the correct SSG datastream and profile for a host.

## Do Not Use When

- The task is defining or analysing audit rules; use `linux-auditd-rules`.
- The task is file-content drift detection; use `linux-file-integrity`.
- The task is applying hardening by hand (sysctl, SSH, SELinux); use `linux-server-hardening`.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Exact distro/version, role, scope, and benchmark/profile requirement | Inventory and control owner | yes | Stop profile selection; do not scan against a guessed datastream. |
| Scanner/content versions, profile ID, tailoring, and exceptions | Read-only package/content inspection | yes | Report coverage unavailable or run Lynis as a qualified secondary check. |
| Remediation authority, test host, rollback, and service constraints | Change record | remediation only | Generate a draft only; do not apply. |

## Capability Contract

Default to read-only: read/search installed content and run scans that do not remediate. Package installation, generated-script execution, Ansible application, service changes, and any `--remediate` action require explicit authority and a test host. A report is not certification.

## Degraded Mode

If matching SCAP content/profile is unavailable, do not substitute a different distro/version. Return a coverage gap and optionally a read-only Lynis result. Unassessed rules remain unassessed, never passed; generated remediation remains an unexecuted draft.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| OpenSCAP or Lynis | Use OpenSCAP for named policy evidence; Lynis for advisory hardening breadth. | Treating an advisory score as compliance. |
| Datastream/profile | Match exact distro major version and list profile IDs before evaluation. | Invalid or misleading results. |
| Tailoring/exception | Record business justification and expiry without rewriting raw results. | Hidden control waiver. |
| Remediation | Review generated changes, test with rollback, then rescan before production proposal. | Breaking services or claiming unverified compliance. |

## Workflow

1. Read/search the exact host identity, installed scanner/content, datastream, profiles, tailoring, and prior exceptions; stop on a distro/profile mismatch.
2. Record scope and run OpenSCAP in read-only evaluation mode, preserving XML plus human report and command metadata.
3. Classify pass, fail, error, not applicable, and not checked separately; block any compliance claim with unresolved errors or coverage gaps.
4. Optionally run read-only Lynis as a secondary advisory source and keep its findings distinct.
5. Generate remediation only when requested; review each proposed change against services, ownership, and rollback.
6. With separate authority, test remediation outside production and rescan the identical profile. Recover by reverting the test change and preserving pre/post evidence when a service or control regresses.

## Quality standards

- Always match the SSG datastream to the exact distro and version.
- Treat OpenSCAP remediation as a draft — review every change before applying to production.
- Re-scan after remediation; a score only counts if it's reproduced.
- Capture `results.xml` for the audit trail, not just the HTML report.

## Anti-Patterns

- Applying `--remediate` to production. Fix: generate, review, test, rollback-test, and rescan before proposing production change.
- Scanning with a mismatched datastream. Fix: verify distro major version, content package, and profile ID first.
- Chasing the Lynis index. Fix: prioritise named findings and risk, not the aggregate score.
- Calling a passing profile "secure". Fix: state benchmark scope, exceptions, errors, and out-of-scope threats.
- Counting errors/not-checked as passes. Fix: preserve result status and block unsupported compliance claims.
- Claiming certification from a local scan. Fix: describe assessment evidence only and defer certification to authorised assessors.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Scan evidence set | Control owner | Exact content/profile/tailoring, command, XML, human report, timestamp, and host identity are preserved. |
| Qualified findings summary | System owner | Separates pass/fail/error/not-checked/exceptions, prioritises failures, and states coverage limits. |
| Remediation draft/rescan | Change owner | Every change is reviewed/tested with rollback and identical-profile rescan, or remains clearly unexecuted. |

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Compliance scan pack | Contains scanner/content versions, datastream/profile, raw XML, report, status counts, exceptions, errors, Lynis separation, and pre/post evidence where authorised. |

## Worked Example

On RHEL 9, confirm `ssg-rhel9-ds.xml`, list the exact profile, run a read-only evaluation, preserve XML and HTML, and report errors separately. Generate remediation only as a draft unless a test-host change is explicitly authorised.
<!-- dual-compat-end -->

## References

- [`../../docs/continuous-improvement/linux-product-audit-checklist.md`](../../docs/continuous-improvement/linux-product-audit-checklist.md)

- [`references/openscap-reference.md`](references/openscap-reference.md) — install SSG, list profiles, evaluate against CIS/STIG/PCI-DSS, generate HTML reports and remediation (bash + Ansible), and pick datastreams per distro.
- [`references/lynis-reference.md`](references/lynis-reference.md) — install, `lynis audit system`, reading the hardening index, prioritizing suggestions, and CI/cron usage.
- [`../linux-auditd-rules/references/auditd-reference.md`](../linux-auditd-rules/references/auditd-reference.md) — applying SSG/CIS audit rulesets via auditd (the rule layer behind a benchmark).

**This skill is self-contained.** Every command below is standard `oscap` or
`lynis` on its family (see **Distro support** for the install and datastream
substitutions). The `sk-*` script in the **Optional fast path** section is a
convenience wrapper — never required.

## OpenSCAP: install, list profiles, scan

```bash
# RHEL family
sudo dnf install openscap-scanner scap-security-guide
# Debian/Ubuntu
sudo apt install openscap-scanner ssg-debderived

# List the profiles in your distro's datastream (pick the right ds.xml!)
oscap info /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml

# Evaluate against a CIS profile, writing machine + human reports
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --results results.xml \
  --report report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
```

`results.xml` is the audit-trail artefact; `report.html` is the readable
pass/fail breakdown. STIG, PCI-DSS, and HIPAA profiles live in the same
datastream — list them with `oscap info` and swap the `--profile` ID.

## OpenSCAP: generate remediation

```bash
# Bash remediation script from a completed scan
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --fix-type bash \
  --output remediate.sh \
  results.xml

# Ansible playbook instead
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --fix-type ansible \
  --output remediate.yml \
  results.xml
```

> Review every generated change. Apply on a **test host** first, then re-scan
> to confirm the score improved before touching production. Full datastream
> selection, profile IDs, and remediation detail in
> [`references/openscap-reference.md`](references/openscap-reference.md).

## Lynis: quick hardening sweep

```bash
sudo apt install lynis                 # dnf install lynis (EPEL on RHEL/Rocky/Alma)
sudo lynis audit system                # interactive: score + suggestions
sudo lynis audit system --quiet --logfile /var/log/lynis.log   # for cron/CI

# Results: hardening index + warnings + suggestions
sudo grep -E 'Hardening index|Warning|Suggestion' /var/log/lynis-report.dat
```

The hardening index is a quick directional score, not a benchmark. Work the
prioritized suggestions, then re-run. Detail in
[`references/lynis-reference.md`](references/lynis-reference.md).

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-benchmark-scanning` installs:

| Task | Fast-path script |
|---|---|
| Auto-pick the SSG datastream, run OpenSCAP + Lynis, summarise scores | `sudo sk-benchmark-scan --profile cis` |

This is an optional read-only wrapper around `oscap` and `lynis` — it scans
and reports, it never remediates. The commands above are the source of truth.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-benchmark-scanning
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-benchmark-scan | scripts/sk-benchmark-scan.sh | yes | Read-only compliance scan on both families: auto-detect the distro/version, locate the matching SSG datastream, run `oscap xccdf eval` against the chosen profile (CIS/STIG/PCI-DSS) into timestamped results.xml + report.html, optionally run `lynis audit system`, and print a pass/fail + hardening-index summary. Never remediates. |
