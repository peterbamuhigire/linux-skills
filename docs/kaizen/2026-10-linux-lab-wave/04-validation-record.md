# Validation record — Linux lab wave, 31 October 2026

Every result below comes from a command run on this machine after the last edit to a skill, script, procedure or
test (the evidence files themselves were written after it; the gates were run again after they were). Raw output
is in `samples/`. A check that could not run is `NOT_ASSESSED` with the exact reason.

## Registered gates and suites, after the last edit

Output: [samples/registered-gates-final.log](samples/registered-gates-final.log). Baseline for comparison:
[samples/registered-gates-baseline.log](samples/registered-gates-baseline.log).

| Command | Exit | Baseline | Final |
|---|---:|---|---|
| `python3 -X utf8 scripts/validate_skills.py --baseline quality-baseline.json` | 0 | 48 compliant | 48 compliant |
| `python3 -X utf8 scripts/routing_smoke_test.py` | 0 | 95/95 valid; P@1 82/95 (0.863); P@3 1.000; 14/48 at 3+2 | 109/109 valid; P@1 96/109 (0.881); P@3 1.000; 17/48 at 3+2 |
| `bash scripts/tests/check-distro-matrix.sh` | 0 | 41 passed | 41 passed |
| `python3 -X utf8 scripts/validate_safe_operation_fixture.py tests/fixtures/safe-operation-evidence.json` | 0 | pass | pass |
| `python3 -X utf8 scripts/source_ingestion_guardrail.py` | 0 | 0 findings | 0 findings |
| `python3 scripts/check_marketplace.py` | 0 | 397/5000 package files | 439/5000 package files |
| `node scripts/generate-plugin-manifest.js ... --check` | 0 | current, 45 skills | current, 45 skills |
| `bash scripts/tests/common-sh.test.sh` | 0 | 42 passed | 45 passed |
| Full suite, real pytest (shared venv, `-p no:cacheprovider`, `PYTHONDONTWRITEBYTECODE=1`) | 0 | 102 passed, 1 skipped | 119 passed, 9 skipped, 28 subtests passed |
| `python3 scripts/kaizen_metrics.py --as-of 2026-10-31 --baseline <pass-2 metrics-final.json> --output <file> --quiet` | 0 | hygiene gate pass | hygiene gate pass; prints nothing (new `--quiet`) |

The 9 skips are the opt-in lab tests (7 in `tests/test_distro_labs.py`, 2 in `tests/test_mysql_backup.py`); they
need Podman and local images and are run separately below.

## Lab suites, run after the last edit

Both used a copy of the final tree (`LINUX_SKILLS_LAB_REPO`), rootless Podman 5.8.9, local images only.

| Suite | Command | Result |
|---|---|---|
| Distro labs (Debian 12 and Fedora 44) | `LINUX_SKILLS_LAB=1 python -m pytest -rP tests/test_distro_labs.py` | **7 passed in 201 s**; 150 `PASS` lines, 0 `FAIL` ([log](samples/lab-distro-suite-final.log)) |
| MySQL 8.4 labs | `LINUX_SKILLS_MYSQL_BACKUP_LAB=1 LINUX_SKILLS_LAB_PREFIX=lskw- python -m pytest tests/test_mysql_backup.py` | **2 passed in 70 s** ([log](samples/lab-mysql84-suite-final.log)) |

What the seven distro labs assert, per image (`debian:bookworm` with OpenSSH 9.2, PostgreSQL 15.19, ShellCheck
0.9.0; `fedora:44` with OpenSSH 10.2, PostgreSQL 18.6, dnf5 5.4.6.0, ShellCheck 0.11.0):

| Lab | Debian 12 | Fedora 44 |
|---|---|---|
| SSH drop-in beside a cloud-init `PasswordAuthentication yes` file; blocks run as written | `sshd -T` values, password login refused, allowed key works, outsider and root refused, rollback works, old name `99-hardening.conf` loses, syntax error caught by `sshd -t` with no reload attempted | same, with the documented reload and rollback blocks exiting 0 as written |
| `sk-pg-backup` against a real PostgreSQL | dry run writes nothing; 0700 and 0600; globals with a SCRAM hash; `pg_restore --list` per dump; repeat; retention prunes only its own files; seven controlled failures; no client warning | same |
| Documented restore on a second instance | globals exit 0 with the documented harmless error; both databases restored; eleven reconciliation figures equal; second `--create` and truncated dump fail; `-j` from standard input refused | same |
| Automatic updates | documented block applied; dry run names `label=Debian-Security` and `codename=bookworm-security`; the pending security upgrade is listed | not applicable (dnf-automatic was verified separately, see the baseline sample) |
| ShellCheck `--severity=warning` over 41 shell sources | exit 0 | exit 0 |

## Fail-before evidence (the same checks against the 29 October text)

| Check | Unfixed result | Sample |
|---|---|---|
| Fedora SSH reload and rollback blocks | exit 5, `Unit ssh.service not found` | [baseline](samples/lab-ssh-dropin-fedora44-baseline.log) |
| Debian automatic updates, driver against the previous procedure | 4 checks FAIL; `No packages found ...` with tzdata pending | [driver before fix](samples/lab-unattended-upgrades-debian12-driver-before-fix.log) |
| Debian `sk-pg-backup` client warning | `could not change directory to "/root"` in the real run | [baseline](samples/lab-pg-backup-debian12-pg15-baseline.log) |
| ShellCheck | 28 warnings, exit 1 (0.9.0 and 0.11.0) | [0.9.0](samples/lab-shellcheck-0.9.0-summary-baseline.log), [0.11.0](samples/lab-shellcheck-0.11.0-baseline.log) |
| Static tests | `test_unattended_upgrades_docs` 7 subtest failures; `test_ssh_dropin_precedence` 2 failures; `test_distro_parity` 8 violations; `test_kaizen_metrics` 3 failures; `common-sh.test.sh` 1 failure | recorded in [03-experiment-log.md](03-experiment-log.md) |

## Containers and the host

- `podman ps --all` after the last run lists no container; `podman ps --all --format '{{.Names}}' | grep -c '^lskw-'`
  prints 0. Every container was named `lskw-`, and each was removed by name with `podman rm --force`.
- One anonymous volume was left by an early MySQL probe that was removed without `--volumes`; it was found at the
  cleanup check, identified as that probe's data (created 18:22, MySQL files inside) and removed with
  `podman volume rm`. `podman volume ls` is empty. No network was left (`podman network ls` shows only the default).
- The local image list is unchanged from the start (seven entries, the same IDs); nothing was pulled.
- No `sudo`, no `systemctl` on the host, no package, user, cron, firewall or SELinux change, and no `sk-*` script
  run on the host. The installed copies in `/usr/local/bin` and `/usr/local/lib/linux-skills` were not touched, so
  they are older still than the repository (see the [operator note](operator-note.md)).

## NOT_ASSESSED, with the exact reason

| Item | Reason |
|---|---|
| `sudo bash scripts/tests/install-skills-bin.test.sh` | CI runs it under `sudo`; `sudo` is prohibited on this host |
| Enterprise RHEL, Rocky, Alma, CentOS Stream, Debian 13, Ubuntu 22.04 and 24.04 | no image on the machine and none pulled. Ubuntu's `Allowed-Origins` form in the rewritten procedures is marked "not run in a lab" |
| Real cloud image with cloud-init, enforcing SELinux, firewalld, UFW, nftables | an unprivileged container offers none of them; `50-cloud-init.conf` is imitated |
| ACME issuance and renewal, Active Directory, hosted CI | out of scope for the wave |
| Real disk exhaustion, production-size backups, remote object-store outage | a file-size limit (`ulimit -f`) stands in for a full disk; sizes were kilobytes |
| The 22 other `sk-*` scripts | they need LVM, auditd, nftables, kernel modules or a network device |
| External links (303), live Claude or Codex plugin loading, `claude plugin validate` | not fetched or run; unchanged from earlier cycles |
| Any model call, Tier 3 behavioural run, comparative model review | none made |

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
