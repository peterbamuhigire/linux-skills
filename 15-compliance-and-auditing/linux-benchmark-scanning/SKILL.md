---
name: linux-benchmark-scanning
description: Automated security-benchmark and compliance scanning on Debian/Ubuntu and RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Run OpenSCAP (oscap xccdf eval) against SCAP Security Guide profiles — CIS Benchmarks, DISA STIG, PCI-DSS, HIPAA — produce machine-readable results.xml plus an HTML report, and generate a remediation script or Ansible playbook from the scan. Run Lynis (lynis audit system) for a fast hardening score and prioritized suggestions. Pick the right SSG datastream and profile per distro. For audit-rule definition use linux-auditd-rules; for file-hash drift use linux-file-integrity.
license: MIT
metadata:
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

## Use when

- Running a CIS / STIG / PCI-DSS scan with OpenSCAP and producing a report.
- Generating a remediation script or Ansible playbook from a scan.
- Running a quick Lynis hardening sweep to get a score and suggestions.
- Choosing the correct SSG datastream and profile for a host.

## Do not use when

- The task is defining or analysing audit rules; use `linux-auditd-rules`.
- The task is file-content drift detection; use `linux-file-integrity`.
- The task is applying hardening by hand (sysctl, SSH, SELinux); use `linux-server-hardening`.

## Required inputs

- The distro and major version (to pick the SSG datastream).
- The target benchmark/profile (CIS Level 1/2, STIG, PCI-DSS).
- Whether you want a scan only, or scan plus generated remediation.
- Whether remediation will be applied (and on a test host first).

## Workflow

1. Install the scanner and the matching SSG content for the distro/version.
2. List available profiles (`oscap info <ds.xml>`); pick the benchmark.
3. Run the evaluation, producing `results.xml` and an HTML `report.html`.
4. Review failures; generate a remediation script/playbook if needed.
5. Apply remediation on a test host, re-scan, and confirm the score improved.
6. Run `lynis audit system` for a fast second opinion and quick wins.

## Quality standards

- Always match the SSG datastream to the exact distro and version.
- Treat OpenSCAP remediation as a draft — review every change before applying to production.
- Re-scan after remediation; a score only counts if it's reproduced.
- Capture `results.xml` for the audit trail, not just the HTML report.

## Anti-patterns

- Auto-applying `--remediate` on a production host without a test run.
- Using a RHEL8 datastream against a RHEL9 host (rules silently mismatch).
- Chasing the Lynis hardening index as a target instead of fixing the underlying findings.
- Treating a passing scan as "secure" — benchmarks are a floor, not a ceiling.

## Outputs

- The profile scanned and the pass/fail summary (and the HTML/XML report paths).
- The prioritized list of failures and any generated remediation.
- The Lynis hardening index and top suggestions.
- A re-scan result confirming remediation took effect.

## References

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
