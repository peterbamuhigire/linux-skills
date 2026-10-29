# Validation record — 29 October 2026

Run from the repository root. `python` below denotes the isolated test virtual environment when pytest/PyYAML are required; it does not prescribe a machine-specific location. All inputs were repository fixtures or disposable containers. No paid model evaluation was run.

## Registered checks

| Exact command | Baseline | Final |
|---|---|---|
| `python -X utf8 scripts/validate_skills.py --baseline quality-baseline.json` | exit0;48 compliant,1 template | exit0;48 compliant,1 template |
| `python -X utf8 scripts/routing_smoke_test.py` | exit0;30/30 top3 | exit0;80/80 top3; P@1 67/80 |
| `bash scripts/tests/check-distro-matrix.sh` | exit0;41 pass,0 fail | exit0;41 pass,0 fail; stronger negative tests |

The registered checks were rerun during retained-change integration; full final output is [registered-gates.log](samples/registered-gates.log). Original and final metrics retain their explicit scope. The improved link parser distinguishes missing paths from missing anchors; compare the same parser against the pristine baseline, not unlike scanner totals.

## Automated and practitioner evidence

- `python -m pytest -q`: final count in [python-tests.log](samples/python-tests.log); the opt-in MySQL lab is skipped by default, not counted as a pass.
- `LINUX_SKILLS_MYSQL_BACKUP_LAB=1 python -m pytest -q tests/test_mysql_backup.py`: exit0,1 passed ([collected result](samples/mysql-collected-test.log)). [Actual lab](samples/mysql-lab-final.md) retains timed backup, repeated run, second-instance restore, row/trigger/routine reconciliation and injected failures. Oracle Linux-based MySQL8.4 image; not proof of Debian/RHEL package installation.
- `bash scripts/tests/common-sh.test.sh`:29 passed on Debian and Fedora. `bash scripts/tests/install-skills-bin.test.sh`:21 passed on each. Fedora minimal image initially lacked `cmp`; the failure was repaired by declaring `diffutils` and checking it before installation writes.
- `shellcheck -S warning scripts/lib/common.sh scripts/sk-audit.sh scripts/sk-mysql-backup.sh scripts/install-skills-bin scripts/tests/common-sh.test.sh scripts/tests/install-skills-bin.test.sh scripts/tests/check-distro-matrix.sh tests/labs/web_502.sh`: ShellCheck0.9 in disposable Debian. Final result retained in [shellcheck.log](samples/shellcheck.log).
- `bash -n` for every tracked/new shell source and extensionless installer: result in final evidence JSON. Syntax is not runtime proof.
- `python scripts/check_marketplace.py`: both package and checkout file counts below5,000; exact final inventory is in [marketplace.log](samples/marketplace.log). Manifest parity covers45 operational skills; three meta skills are intentionally excluded.
- `node scripts/generate-plugin-manifest.js --engine . --root . --exclude "docs,scripts,templates,tests,commands,meta,notes,prompts" --check`: exit0,45skills. `claude plugin validate .`: exit0, warnings for root CLAUDE.md not being plugin context and missing icon ([output](samples/claude-plugin.log)); live install/load and public acceptance NOT_ASSESSED.
- `python scripts/kaizen_metrics.py --as-of 2026-10-29 --base-ref 2ce755a7731e3061296de68747d8d36fea4286a9 --baseline docs/kaizen/2026-10-engine-kaizen/metrics-baseline.json --output docs/kaizen/2026-10-engine-kaizen/metrics-final.json`: same-scope metrics and regression check; [final JSON](metrics-final.json).
- `python -X utf8 scripts/validate_safe_operation_fixture.py tests/fixtures/safe-operation-evidence.json`: five synthetic cases; separate from actual restore.
- `python -X utf8 scripts/source_ingestion_guardrail.py`: exit0; no findings. No external content treated as authority to execute commands.

## Three practitioner tasks

1. [Before output](samples/practitioner-before.md) and [paired hardened plan](samples/hardened-baseline.md): selected security-analysis/server-hardening, webstack, MySQL, firewall and package-management. Plan explicitly requires target release, repositories, console recovery, domain/ACME ownership and authorised mutation. Full-stack implementation, real TLS renewal, SSH/firewall lockout recovery, systemd and enforcing SELinux remain NOT_ASSESSED.
2. [MySQL baseline](samples/mysql-lab-baseline.md) reproduced unsafe artifact modes and failed-encryption leakage. [Final output](samples/mysql-lab-final.md) records a timed verified restore and controlled failures. Backup snapshots are synthetic; production volume, cloud retention expiry and RPO/RTO remain unassessed.
3. [502 diagnosis tree](../../../04-web-and-mail-services/linux-webstack/references/php-upgrade-502.md) and [Debian output](samples/web-502-debian.log)/[Fedora output](samples/web-502-fedora.log). Command inside each disposable image: `SK_LAB_DISPOSABLE=1 bash tests/labs/web_502.sh`; dependencies Nginx, PHP-FPM and curl installed only in the containers. Exit0 both. Fault is an upstream listener change after a simulated upgrade, not an actual package upgrade. No public ports. Logs retain temporary container paths, not workstation paths.

Debian image digest: `sha256:a0039cc6bb3eb2215aabcd3437cce8808a3858d86bf483eee2ee14fe4d2551c2b`. Fedora44 image digest: `sha256:474e0ab5a1e59c215e59f281b1fe49f2866ec20f773533f5cca851cc830c5c2b`. Fedora is useful family evidence, not a substitute for an enterprise RHEL minor-release lab.

## Limits

No target-host or network-appliance deployment, all 26 scripts matrix, live marketplace load, controlled model comparison, custom ACL/xattr/SELinux atomic-write preservation, production credentials or paid service calls. Those are NOT_ASSESSED. Historical WSL absence was not relabelled as a Linux success. Security research is a dated bounded official-source review, not an exhaustive guarantee that every vulnerability has been found.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.

## Hosted release checks

GitHub Actions completed successfully for released code revision `751d10b5304cb79af578a490771e6b91ce16664d` on2026-10-29: [Skill quality](https://github.com/peterbamuhigire/linux-skills/actions/runs/40815304825), [Bash suites including Fedora](https://github.com/peterbamuhigire/linux-skills/actions/runs/40815304843), and [source-ingestion guardrail](https://github.com/peterbamuhigire/linux-skills/actions/runs/40815304824). This supersedes the earlier hosted-CI NOT_ASSESSED entry for that exact revision. The following evidence-only commit does not alter executable code.

## Portfolio refresh supplement — 29 October 2026

See [the bounded R1 refresh](portfolio-refresh.md) for the stricter file-cap
regression, native local marketplace proof and the resolved development source
register lookup. Original operational evidence and raw scores are preserved.
