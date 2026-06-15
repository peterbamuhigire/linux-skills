# OpenSCAP: CIS / STIG / PCI-DSS scanning and remediation

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

> `[GROUNDING-GAP: CIS/OpenSCAP — grounded on upstream docs + CIS Benchmark
> PDFs; deepen on purchase]`
>
> OpenSCAP is grounded at the recipe level in *Red Hat Enterprise Linux 9 for
> SysAdmins* (Gotangco, Recipe #98 — `scap-security-guide`, `oscap info`,
> `oscap xccdf eval --profile`) and in *Fedora Linux Essentials* (the
> automated-vulnerability-assessment chapter, including `oscap xccdf eval
> --profile ... --results results.xml --report report.html`). Profile IDs,
> remediation generation, and the Debian-side datastreams below are extended
> from the OpenSCAP and SCAP Security Guide upstream docs and CIS Benchmark
> PDFs. Verify the exact datastream filename and profile IDs for your distro
> version before relying on them.

OpenSCAP is the open-source implementation of SCAP (Security Content
Automation Protocol). It evaluates a host against a formal benchmark —
CIS, DISA STIG, PCI-DSS, HIPAA — encoded as an XCCDF profile inside a SCAP
**datastream** (the SCAP Security Guide, SSG). Output is pass/fail per rule,
plus an HTML report and an auto-generated remediation script or playbook.

## Table of contents

- [Install and content](#install-and-content)
- [Pick the right datastream](#pick-the-right-datastream)
- [List profiles](#list-profiles)
- [Evaluate against a profile](#evaluate-against-a-profile)
- [Reading the report](#reading-the-report)
- [Generate remediation](#generate-remediation)
- [Scan a single rule or by reference](#scan-a-single-rule-or-by-reference)
- [The auditd rule layer behind a benchmark](#the-auditd-rule-layer-behind-a-benchmark)
- [Automating scans](#automating-scans)
- [Sources](#sources)

---

## Install and content

```bash
# RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle)
sudo dnf install openscap-scanner scap-security-guide

# Debian/Ubuntu
sudo apt install openscap-scanner ssg-debderived
```

`openscap-scanner` provides the `oscap` binary; the SSG package provides the
datastream content under `/usr/share/xml/scap/ssg/content/`.

---

## Pick the right datastream

There is **one datastream per distro and major version** — using the wrong
one silently mismatches rules. List what's installed:

```bash
ls /usr/share/xml/scap/ssg/content/
# ssg-rhel9-ds.xml  ssg-centos9-ds.xml  ssg-fedora-ds.xml ...
# ssg-ubuntu2204-ds.xml  ssg-debian12-ds.xml ...
```

Match the file to your host:

```bash
. /etc/os-release; echo "$ID $VERSION_ID"      # e.g. rhel 9.4 -> ssg-rhel9-ds.xml
```

---

## List profiles

```bash
oscap info /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
```

This prints every profile and its ID. Typical IDs (suffix after
`xccdf_org.ssgproject.content_profile_`):

| Benchmark | Example profile ID suffix |
|---|---|
| CIS Level 1 (Server) | `cis` or `cis_server_l1` |
| CIS Level 2 (Server) | `cis_server_l2` |
| DISA STIG | `stig` |
| PCI-DSS | `pci-dss` |
| HIPAA | `hipaa` |
| Standard baseline | `standard` |

The exact suffixes vary by distro/version — always confirm with `oscap info`.

---

## Evaluate against a profile

```bash
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --results results.xml \
  --report report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
```

- `--results results.xml` — machine-readable result (the audit-trail artefact).
- `--report report.html` — human-readable pass/fail breakdown with remediation
  hints per rule.

`oscap` exits non-zero when rules fail — that is expected, not an error.

Fedora example against the standard baseline (from the corpus):

```bash
oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_standard \
  --results results.xml --report report.html \
  /usr/share/xml/scap/ssg/content/ssg-fedora-ds.xml
```

---

## Reading the report

Open `report.html` in a browser. Each rule shows **pass / fail / notapplicable
/ notchecked**, its severity, and a remediation snippet. Triage:

1. **High-severity fails** — fix first (auth, SSH, sudo, SELinux/AppArmor,
   audit rules).
2. **Medium** — fix in batches, retest.
3. **notapplicable** — rule doesn't apply to this host's role; fine to skip.
4. **notchecked** — often needs a manual control; document the compensating
   control for the auditor.

Treat the benchmark as a floor: a passing scan means the baseline is met, not
that the host is secure.

---

## Generate remediation

OpenSCAP can emit a fix script from a completed scan's `results.xml`:

```bash
# Bash
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --fix-type bash \
  --output remediate.sh \
  results.xml

# Ansible
sudo oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --fix-type ansible \
  --output remediate.yml \
  results.xml
```

You can also remediate inline during a scan with `--remediate`, but **do not
do this on production blind** — it changes the system live:

```bash
sudo oscap xccdf eval --remediate --profile <id> --report report.html <ds.xml>
```

> Always: review the generated fix, run it on a **test host**, re-scan, and
> confirm the score improved before applying to production. Some remediations
> (e.g. disabling protocols, tightening PAM) can lock you out.

---

## Scan a single rule or by reference

```bash
# One rule by ID (fast iteration while remediating)
sudo oscap xccdf eval --rule xccdf_org.ssgproject.content_rule_sshd_disable_root_login <ds.xml>

# Select rules by CIS reference number
sudo oscap xccdf eval --profile <id> --report report.html \
  --rule-id-by-ref cis <ds.xml>
```

---

## The auditd rule layer behind a benchmark

Many CIS/STIG controls are *audit-rule* requirements. RHEL ships these as
ready-made auditd rulesets via the same `scap-security-guide` package
(`/usr/share/audit/sample-rules/`), which you can apply directly — see
[`../../linux-auditd-rules/references/auditd-reference.md`](../../linux-auditd-rules/references/auditd-reference.md).
OpenSCAP checks whether those rules are present; applying the sample ruleset
is how you make the corresponding rules pass.

---

## Automating scans

A nightly compliance scan, results timestamped for the audit trail:

```bash
sudo tee /etc/cron.d/oscap-nightly > /dev/null <<'EOF'
30 2 * * * root oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis \
  --results /var/log/oscap/results-$(date +\%F).xml \
  --report  /var/log/oscap/report-$(date +\%F).html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml >/dev/null 2>&1
EOF
sudo mkdir -p /var/log/oscap
```

OpenSCAP also integrates with orchestration pipelines (run a scan, normalise
`results.xml`, feed a dashboard/SIEM) — pair it with Lynis for a fuller sweep
(see [`lynis-reference.md`](lynis-reference.md)).

---

## Sources

- Book: *Red Hat Enterprise Linux 9 for SysAdmins* (Jerome Gotangco) —
  Recipe #98: `scap-security-guide`, `oscap info`, `oscap xccdf eval
  --profile` against `ssg-rhel9-ds.xml` (CIS/STIG/PCI-DSS).
- Book: *Fedora Linux Essentials Definitive Reference* (Richard Johnson) —
  automated vulnerability assessment: `oscap xccdf eval --profile ...
  --results results.xml --report report.html`.
- OpenSCAP upstream: https://www.open-scap.org/
- SCAP Security Guide (ComplianceAsCode): https://github.com/ComplianceAsCode/content
- CIS Benchmark PDFs (per-distro benchmark control text).
- `[GROUNDING-GAP: CIS/OpenSCAP — grounded on upstream docs + CIS Benchmark
  PDFs; deepen on purchase]`
