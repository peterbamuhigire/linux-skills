# Validation record — 31 October 2026

Run from the repository root on branch `kaizen/2026-10-pass2`, Fedora 44 workstation, Python 3.14,
Node 22, Bash 5. Only repository fixtures, `PATH` stubs and temporary directories were used. No
`sudo`, no container, no service, firewall, package, cron or SELinux change, no paid model call.
The final full run is in [registered-gates-final.log](samples/registered-gates-final.log).

## Registered validators (engine prompt)

| Exact command | Baseline (f904f7b) | Final |
|---|---|---|
| `python3 -X utf8 scripts/validate_skills.py --baseline quality-baseline.json` | exit 0; 48 compliant, 1 template | exit 0; 48 compliant, 1 template |
| `python3 -X utf8 scripts/routing_smoke_test.py` | exit 0; 80/80 valid, P@1 67/80 (0.838), P@3 80/80; coverage 11/48 | exit 0; 95/95 valid, P@1 82/95 (0.863), P@3 95/95; coverage 14/48; owned negatives 29 |
| `bash scripts/tests/check-distro-matrix.sh` | exit 0; 41 passed, 0 failed | exit 0; 41 passed, 0 failed |

## Other checks run

| Command | Baseline | Final |
|---|---|---|
| `bash scripts/tests/common-sh.test.sh` | exit 0; 29 passed | exit 0; 42 passed (foreign-owner and root-branch cases print `[SKIP]`: a non-root run cannot exercise them) |
| `python3 -X utf8 -m unittest tests/<module>.py`, each of the eight modules that existed | 57 tests, all OK | the same eight modules, all OK |
| New `unittest` modules: `test_ssh_dropin_precedence` 6, `test_pg_backup` 15, `test_mysql_backup_config` 4, `test_script_trust_boundaries` 3 | not present | 28 tests, all OK; total 85 unittest tests |
| `tests/test_validate_skills.py`, `test_admin_activity.py`, `test_codex_model_policy.py` through a 60-line stand-in runner (pytest is not installed) | 8 passed, 2 parametrised cases skipped by the runner | 8 passed, the same 2 skipped |
| `python3 -X utf8 scripts/validate_safe_operation_fixture.py tests/fixtures/safe-operation-evidence.json` | exit 0 | exit 0 |
| `python3 -X utf8 scripts/source_ingestion_guardrail.py` | exit 0; 0 findings | exit 0; 0 findings |
| `python3 scripts/check_marketplace.py` | exit 0; 369/5000 package files; 745/5000 checkout entries | exit 0; 394/5000 and 928/5000 |
| `node scripts/generate-plugin-manifest.js --engine . --root . --exclude docs,scripts,templates,tests,commands,meta,notes,prompts --check` | exit 0; 45 skills | exit 0; 45 skills |
| `bash -n` over every tracked `.sh` and `scripts/install-skills-bin` (36 files) | 0 failures | 0 failures (syntax only; not runtime proof) |
| `python3 scripts/kaizen_metrics.py --as-of 2026-10-31 --baseline <baseline JSON> --output <file>` | gate `pass` | gate `pass`; see below |

The stand-in runner implements only `tmp_path`, `pytest.raises`, `pytest.mark.skipif` and
`pytest.skip`. Its results are labelled as such and do not replace `python -m pytest -q`.

## Same-parser hygiene measures

From `scripts/kaizen_metrics.py`; baseline file [metrics-baseline.json](metrics-baseline.json), final
[metrics-final.json](metrics-final.json). The 29 October final and these two share the parser.

| Measure | 29 Oct final | Pass 2 baseline | Pass 2 final |
|---|---:|---:|---:|
| Fixtures / expected-target P@1 / P@3 | 80 / 67 (0.838) / 80 | 80 / 67 / 80 | 95 / 82 (0.863) / 95 |
| Skills with 3 positives + 2 owned negatives | 11 of 48 | 11 of 48 | 14 of 48 (of the 16 skills touched in this pass, 7 meet it; see below) |
| Owned-negative fixtures; forbidden neighbours absent at top 3 | 23; 23 | 23; 23 | 29; 29 |
| Dangling local paths / anchors | 5 / 10 | 5 / 10 | 0 / 0 |
| Skills with duplicate canonical headings | 10 | 10 | 0 |
| Expired structured source rows | 10 | 10 | 0 |
| Machine-specific absolute inline links | 0 | 0 | 0 |
| Worked examples present | 48 of 48 | 48 of 48 | 48 of 48 (depth proxies unchanged: medians 2 and 4.5) |
| External links, reachability | 288, `NOT_ASSESSED` | 288, `NOT_ASSESSED` | 303, `NOT_ASSESSED` (source links added to references and evidence documents) |

## Touched-skill fixture coverage

`metrics-final.json` lists 16 touched skills (diff against `f904f7b`). Seven meet 3 positives and 2 owned
negatives: `linux-access-control`, `linux-bash-scripting`, `linux-mysql-mariadb`, `linux-package-management`,
`linux-postgresql`, `linux-server-hardening`, `linux-server-provisioning`. Nine do not: `linux-cloud-init`,
`linux-config-management`, `linux-disaster-recovery`, `linux-dns-server`, `linux-mail-server`,
`linux-network-admin`, `linux-observability`, `linux-secrets`, `linux-virtualization`. Eight of the nine
changed only by renaming a second `References` heading and one by an anchor repair in a reference file; the
three skills with substantive content changes got fixtures. The nine remain open in `06-next-cycle.md`.

## New automated checks that guard recurrence

- `tests/test_ssh_dropin_precedence.py`: scans six procedures for a hardening drop-in numbered 50 or
  higher and for disagreeing names, and asks `sshd -T` for the effective value of the documented
  blocks beside a competing `50-cloud-init.conf`. Skipped, not passed, where `sshd` or `ssh-keygen`
  is absent.
- `tests/test_script_trust_boundaries.py`: fails when a shipped script sources any variable path other
  than `SK_LIB`; its detector is itself tested on positive and negative samples.
- `tests/test_pg_backup.py` and `tests/test_mysql_backup_config.py`: stub-based behaviour and
  configuration-trust cases, pinned to the repository library.
- `scripts/tests/common-sh.test.sh`: 13 new cases for `sk_source_trusted_config` and the audit fallback.
- CI: `.github/workflows/skill-quality.yml` runs the new `unittest` modules through `python -m pytest -q`
  and the hygiene gate now compares against `metrics-final.json`, so repaying link, anchor, heading and
  source debt cannot silently regress.

## Failure-path evidence

Each new gate was run against the pre-fix state and failed for the intended reason: SSH procedures 3 of 6
failing with `'yes' != 'no'` ([sample](samples/d1-ssh-dropin-baseline.log)); `sk-pg-backup` 10 of 11
cases failing, directory 755 and files 644 ([sample](samples/p2-02-pg-backup-old-vs-new.log),
[modes before](samples/d3-pg-backup-modes-baseline.log), [after](samples/d3-pg-backup-modes-after.log));
audit fallback 3 of 3 cases failing against the previous library
([sample](samples/p2-04-audit-fallback-old-vs-new.log)); the static detector flagging the previous
`source "$CONFIG_FILE"` lines in both backup scripts.

## NOT_ASSESSED, with the exact reason

| Check | Reason |
|---|---|
| `python -m pytest -q` | `ModuleNotFoundError: No module named 'pytest'`; two parametrised cases remain unrun |
| `LINUX_SKILLS_MYSQL_BACKUP_LAB=1 ... tests/test_mysql_backup.py` (real backup and restore) | needs Podman containers and pytest; no container may be created in this pass; carried from 29 October, not re-run after the `load_config` change |
| `sudo bash scripts/tests/install-skills-bin.test.sh` | CI runs it under `sudo`; `sudo` prohibited. Its first checks need no root, but the install steps do |
| ShellCheck | `shellcheck: command not found` |
| Real PostgreSQL dump, restore, timing | no PostgreSQL lab; the live PostgreSQL on this workstation must not be touched |
| Debian 13 and enterprise RHEL host hardening, ACME renewal, SELinux, firewalld or UFW lockout recovery | no disposable VM; host changes prohibited |
| RHEL-family `dnf-automatic` units on a RHEL host | documentation-sourced only; dnf5 half observed on Fedora 44 |
| `sk-capture` default output and pcap mode | needs root and `tcpdump` |
| Hosted CI for the new commits | nothing is pushed in this pass |
| Claude and Codex live marketplace load; model-currentness comparison | not re-run; 29 October evidence stands; no paid model call |
| Foreign-owner and root-branch cases in `common-sh.test.sh` | non-root session; written, printed as skipped |
| External link reachability (303 links) | not fetched |

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
