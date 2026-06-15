# Lynis: fast hardening sweep

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

> `[GROUNDING-GAP: Lynis — grounded on upstream docs + CIS Benchmark PDFs;
> deepen on purchase]`
>
> Lynis is grounded at the recipe level in *Fedora Linux Essentials
> Definitive Reference* (Richard Johnson) — the automated-vulnerability-
> assessment chapter, including `lynis audit system --quiet --logfile
> /var/log/lynis.log` and its role alongside OpenSCAP. The flag detail and
> report-parsing below are extended from the Lynis upstream documentation.
> Verify against your packaged Lynis version before relying on exact output.

Lynis is a host-based security auditing tool. Unlike OpenSCAP it is not tied
to a formal benchmark — it runs a broad battery of opinionated tests (file
permissions, kernel parameters, SSH config, installed packages, network
settings) and produces a numeric **hardening index** plus a prioritized list
of warnings and suggestions. It is the fast, "what should I fix next?" tool;
use it alongside OpenSCAP, which provides the formal audit trail (see
[`openscap-reference.md`](openscap-reference.md)).

## Table of contents

- [Install](#install)
- [Run an audit](#run-an-audit)
- [Reading the results](#reading-the-results)
- [The hardening index](#the-hardening-index)
- [Prioritizing suggestions](#prioritizing-suggestions)
- [Non-interactive / CI usage](#non-interactive--ci-usage)
- [Sources](#sources)

---

## Install

```bash
# Debian/Ubuntu
sudo apt install lynis

# RHEL family — EPEL on RHEL/Rocky/Alma/Oracle; main on Fedora
sudo dnf install epel-release        # skip on Fedora
sudo dnf install lynis
```

The upstream project also ships a tarball that is often newer than the
packaged version; for the latest tests, run from a cloned release. The
packaged version is fine for routine sweeps.

---

## Run an audit

```bash
# Interactive: prints colored output and pauses between sections
sudo lynis audit system

# Non-interactive (cron/CI): quiet, log to a file
sudo lynis audit system --quiet --logfile /var/log/lynis.log

# Limit to one test group (faster, targeted)
sudo lynis audit system --tests-from-group authentication
```

Lynis writes two artefacts:

- `/var/log/lynis.log` — the verbose run log.
- `/var/log/lynis-report.dat` — machine-parseable key=value report.

---

## Reading the results

Pull the headline items from the report file:

```bash
sudo grep -E 'hardening_index|^warning|^suggestion' /var/log/lynis-report.dat
```

In the on-screen output Lynis groups findings as:

- **Warnings** — issues it considers higher priority; address these first.
- **Suggestions** — hardening opportunities, each with a `TEST-ID` you can
  look up (`lynis show details <TEST-ID>`).

```bash
sudo lynis show details SSH-7408       # explain a specific suggestion
```

---

## The hardening index

At the end of a run Lynis prints:

```
  Hardening index : 67 [############        ]
```

This is a rough 0–100 directional score, **not** a compliance grade. Use it
to track progress over time (re-run after fixes and watch it climb), not as a
target in itself — gaming the index without understanding the underlying
findings produces a brittle host. A genuine CIS/STIG verdict comes from
OpenSCAP, not from this number.

---

## Prioritizing suggestions

1. Start with **warnings**, then high-impact suggestion groups: authentication
   (`AUTH-*`), SSH (`SSH-*`), kernel hardening (`KRNL-*`), file permissions
   (`FILE-*`).
2. For each, read `lynis show details <TEST-ID>` to understand the rationale.
3. Apply the fix with the appropriate skill — SSH/sysctl/SELinux hardening
   lives in `linux-server-hardening`; firewall in `linux-firewall-ssl`.
4. Re-run Lynis and confirm the warning cleared and the index rose.

Lynis findings overlap with OpenSCAP CIS rules but also catch operational
gaps (missing AIDE, no audit daemon, weak file perms) that a benchmark
profile may not flag — which is exactly why you run both.

---

## Non-interactive / CI usage

```bash
# Cron: weekly sweep, log dated
sudo tee /etc/cron.d/lynis-weekly > /dev/null <<'EOF'
0 3 * * 0 root lynis audit system --quiet --cronjob --logfile /var/log/lynis-$(date +\%F).log
EOF

# Pipeline pattern (OpenSCAP then Lynis), as in the corpus:
oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_standard \
  --results results.xml --report report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
lynis audit system --quiet --logfile /var/log/lynis.log
```

The `--cronjob` flag suppresses color and pauses for unattended runs. Ship
`/var/log/lynis-report.dat` to your SIEM for trend tracking.

---

## Sources

- Book: *Fedora Linux Essentials Definitive Reference* (Richard Johnson) —
  automated vulnerability assessment with OpenSCAP and Lynis; `lynis audit
  system --quiet --logfile /var/log/lynis.log` and the OpenSCAP+Lynis
  pipeline.
- Lynis upstream documentation: https://cisofy.com/lynis/
- CIS Benchmark PDFs — control text the Lynis tests map onto.
- `[GROUNDING-GAP: Lynis — grounded on upstream docs + CIS Benchmark PDFs;
  deepen on purchase]`
