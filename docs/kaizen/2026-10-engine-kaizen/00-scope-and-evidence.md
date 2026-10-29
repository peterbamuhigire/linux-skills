# Scope and evidence — 29 October 2026

Owner: Peter Bamuhigire. Engine: Chwezi Core Systems Linux Skills.
Repository: `peterbamuhigire/linux-skills`; checkout resolved from the device
catalogue and confirmed with Git. No workstation-specific path is prescribed.

## Authority and continuity

The first instruction authorised a comprehensive security Kaizen, initial cap
45/100, target 95/100, documentation, commit and push to main. The later
Portfolio prompt enhances that instruction: use `kaizen/2026-10`, individual
kept-change commits, seven evidence files and three practitioner tasks. Peter
explicitly confirmed the new instructions do not replace the original ones.
Therefore work is staged on the Kaizen branch and verified changes will be
integrated into main and pushed without a force push or tag.

Initial `git status --short` was empty; baseline commit was
`2ce755a7731e3061296de68747d8d36fea4286a9`. There were **no pre-existing
uncommitted policy files** to exclude. At the enhanced prompt's arrival the
dirty files were this same task's changes, not unrelated user work. No .codex
policy file in this repository was changed. A previously authorised bounded
helper repaired the user-level persisted model configuration, outside Git;
this does not prove the identity of a running root session.

The enhanced workflow arrived after implementation had begun. The earlier
[retrospective review](../../continuous-improvement/kaizen-2026-10-29.md) is
preserved and is not represented as a pre-change frozen Portfolio baseline.
For the enhanced cycle, pristine HEAD was archived and measured independently;
[01-baseline-scorecard.md](01-baseline-scorecard.md) freezes that named
snapshot before the additional K04/K08/K09/K10 changes. Earlier changes are
identified as carried-in experiments in the log. No evidence is backdated.

## Preconditions inspected

- `git status --short`; `git log --oneline -20`; `git fetch origin`; branch
  created with `git switch -c kaizen/2026-10`. Original HEAD matched origin/main.
- Portfolio Kaizen Standard and currentness gate, resolved through the research
  engine catalogue; Linux AGENTS, hub, Kaizen skill and operations loop read.
- `docs/audits/2026-09-06-kaizen.md`, `git show e101a9f`, July discovery,
  scorecard/gap/conformance records, August wave records, September
  script-availability correction and current improvement records inspected.
- No prior `docs/kaizen/` directory existed in this checkout.
- September P0 duplicate fixture identities and broken route remain repaired.
  P1 dual-family applied restore evidence remains open at baseline. P2 distro
  gate remains open: it searched for RHEL anywhere in the whole file and could
  pass an empty catalogue. Windows/WSL absence is historical; this cycle uses
  native Fedora Bash plus disposable Linux containers.

## Practitioner requests and observed routes

| Request | Route selected through hub | Judgement and baseline output |
|---|---|---|
| Harden fresh Debian Nginx/PHP-FPM/MySQL, then RHEL equivalent | security-analysis → server-hardening, with webstack, mysql-mariadb, firewall-ssl and package-management | Correct composed route; no single specialist owns the whole deployment. [Baseline output](samples/practitioner-before.md) records missing platform/ACME/recovery inputs and conflicting commands |
| Run encrypted MySQL backup and restore second instance | mysql-mariadb; archive-integrity/disaster-recovery as handoffs | Correct. Actual MySQL synthetic lab, repeated/failure/restore evidence recorded in mysql-lab samples |
| 502 after PHP upgrade | webstack first; service-management and troubleshooting neighbours | Correct. Existing short debug block hard-coded PHP8.3 and restarted without testing a cause; [baseline output](samples/practitioner-before.md) |

## Defects and severity

Line numbers identify baseline HEAD; later edits may move them. Major defects
block operational use of the affected path until fixed or explicitly withheld.

| ID | Severity | Evidence location / defect |
|---|---|---|
| K01 | Critical | `scripts/lib/common.sh`, original `_sk_registry` around line 493 and `atomic_write` around 529: predictable cleanup registry and fixed temporary sidecar trusted |
| K02 | Major | `scripts/sk-audit.sh`, original SSH helper around line 79, update summary around 197, UFW around 259: wrong precedence, failed query/cached state and substring matching could mislead |
| K03 | Major | `scripts/install-skills-bin` around 178/211: cmp unavailable silently interpreted as different files |
| K04 | Major | `scripts/tests/check-distro-matrix.sh` around 62: RHEL mention anywhere accepted; empty catalogue passed; validator count summary could contradict failure |
| K05 | Major | `.github/workflows/skill-quality.yml`: Python tests omitted; external action tags mutable |
| K06 | Major | Currency evidence spread across historical references; no complete maintained host/advisory applicability register; expired records remain visible |
| K07 | Minor | `linux-sysadmin/SKILL.md` old 40/15 count; historical 88-script plan read as shipped inventory |
| K08 | Major | `linux-webstack/SKILL.md` around 162: blind PHP8.3 restart in 502 diagnosis; hardening checklist calls Ubuntu22.04/24.04 Debian versions and assumes one-family paths |
| K09 | Critical | `scripts/sk-mysql-backup.sh`, dump/archive/encryption around 178–245: plaintext artifacts inherit 022, failed GPG leaves readable archive; retention failures hidden |
| K10 | Major | `tests/fixtures/routing.json`: 30 fixtures, no skill with three positives/two owned negatives; top3 pass ratio labelled precision without P@1 |

## Lab and privacy boundary

Only synthetic data and isolated disposable containers/temporary destinations
are authorised for these experiments. No host firewall, SSH, package manager,
service, disk or production database is changed. Container root is not host
root. No public host ports or paid cloud storage are needed. Secrets generated
for fixture accounts are omitted from the evidence and never committed.
No Tier 3 behavioural model evaluation or external paid model API call is run.
Normal repository tools and existing task workers are not treated as a model
benchmark. Missing operational/model evidence remains NOT_ASSESSED.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.

## Portfolio refresh supplement — 29 October 2026

See [the bounded R1 refresh](portfolio-refresh.md) for the stricter file-cap
regression, native local marketplace proof and the resolved development source
register lookup. Original operational evidence and raw scores are preserved.
