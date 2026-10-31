# Scope and evidence — Kaizen pass 2, 31 October 2026

Engine: Linux Skills (Chwezi Core Systems). Router: `AGENTS.md`; hub skill `linux-sysadmin`.
This is a continuation of the 29 October cycle in `docs/kaizen/2026-10-engine-kaizen/`, not a
first cycle. Its open items were the primary backlog input; each was re-checked before use.

## Step 0 — preconditions

| Item | Value |
|---|---|
| Starting branch / HEAD | `main` at `f904f7bf8ce2e9c0ca12d838d31885af5af76d61` |
| `git status --porcelain` before any action | 0 lines (clean tree; no carried-in uncommitted files) |
| Branch created | `kaizen/2026-10-pass2`, from the same HEAD |
| Evidence folder | `docs/kaizen/2026-10-engine-kaizen-pass-2/` |
| Read first | 29 October `05-final-report.md`, `06-next-cycle.md`, `01-baseline-scorecard.md`, `02-improvement-backlog.md`, `04-validation-record.md`, `currency.md`, `portfolio-refresh.md`; `docs/audits/2026-09-06-kaizen.md`; commit `e101a9f`; `meta/kaizen-improvement-system/SKILL.md`; `linux-sysadmin/kaizen-operations-loop.md`; the Portfolio Kaizen Standard and the currentness gate |

Live-host boundary for this pass. The machine is a working Fedora 44 workstation running MySQL,
PostgreSQL, Apache and PHP-FPM. No `sudo`, no service, firewall, package, user, cron or SELinux
change, and no `sk-*` script was run except against `PATH` stubs inside a scratch directory. No
container was started: none was already present, and the brief forbids creating a lab. Every
live-host, enterprise-RHEL, restore and ACME check is therefore `NOT_ASSESSED` unless stated.
The only reads of live state were `rpm -q`, `ls`, `systemctl is-enabled`/`list-timers` and
`journalctl -u` for the dnf automatic units (defect D2), and `sshd -T -f <fixture>` against a
throwaway configuration tree (defect D1).

## Registered validators at baseline (HEAD `f904f7b`, before any change)

| Command | Exit | Result |
|---|---:|---|
| `python3 -X utf8 scripts/validate_skills.py --baseline quality-baseline.json` | 0 | 48 active skills, 1 template, 48 compliant |
| `python3 -X utf8 scripts/routing_smoke_test.py` | 0 | 80/80 valid; expected-target P@1 67/80 (0.838); P@3 80/80; 11/48 skills meet 3 positive + 2 owned negative |
| `bash scripts/tests/check-distro-matrix.sh` | 0 | 41 passed, 0 failed |

Other registered checks (CI workflow list) run at baseline:

| Command | Exit | Result |
|---|---:|---|
| `python3 -X utf8 scripts/validate_safe_operation_fixture.py tests/fixtures/safe-operation-evidence.json` | 0 | five fixture cases pass |
| `python3 -X utf8 scripts/source_ingestion_guardrail.py` | 0 | 0 findings |
| `python3 scripts/check_marketplace.py` | 0 | 369/5000 package files; 745/5000 checkout entries |
| `node scripts/generate-plugin-manifest.js --engine . --root . --exclude docs,scripts,templates,tests,commands,meta,notes,prompts --check` | 0 | plugin.json current, 45 skills |
| `bash scripts/tests/common-sh.test.sh` | 0 | 29 passed, 0 failed |
| Nine `unittest`-compatible test modules, run one by one | 0 | 62 tests, all OK |
| `test_validate_skills`, `test_admin_activity`, `test_codex_model_policy` through a minimal stand-in runner (pytest is not installed) | 0 | 8 passed; 2 parametrised cases skipped by the runner, `NOT_ASSESSED` |
| `bash -n` over 36 tracked shell sources | 0 | 0 failures (syntax only) |
| `python3 scripts/kaizen_metrics.py --as-of 2026-10-31 --baseline docs/kaizen/2026-10-engine-kaizen/metrics-baseline.json` | 0 | hygiene regression gate: pass; output frozen as `metrics-baseline.json` in this folder |

`NOT_ASSESSED` at baseline, with the exact reason:

- `python -m pytest -q`, `LINUX_SKILLS_MYSQL_BACKUP_LAB=1 ...`: `ModuleNotFoundError: No module named 'pytest'`; the lab also needs Podman containers, which this pass may not create.
- `sudo bash scripts/tests/install-skills-bin.test.sh`: CI runs it under `sudo`; `sudo` is prohibited here.
- ShellCheck: `shellcheck: command not found`; the previous cycle used a disposable Debian container.
- `claude plugin validate .` and live marketplace loading: not re-run; the 29 October observation stands.
- Hosted CI for the new commits: nothing is pushed in this pass.

## Step 1 — three practitioner tasks

The engine's own routing ranker (`scripts/routing_smoke_test.py`, a lexical stand-in for the model
reading skill descriptions) was run on each request, and the chosen skills were then read in full.

### Task 1 — hardened baseline, Debian host with Nginx, PHP-FPM, MySQL, then RHEL family

Request: firewall, SSH, TLS via ACME, automatic security updates, both families.
Ranker top four: `linux-server-provisioning`, `linux-mysql-mariadb`, `linux-file-integrity`,
`linux-server-hardening`. The hub's decision table names `linux-security-analysis` then
`linux-server-hardening`; `linux-firewall-ssl`, `linux-webstack` and `linux-package-management`
are the correct supporting skills but none ranks in the top four. Provisioning first is defensible
for a fresh host; `linux-file-integrity` is noise from the word "hardened".

Skills read: `linux-server-provisioning`, `linux-server-hardening`, `linux-firewall-ssl`,
`linux-package-management`, `linux-access-control` (reference table), `linux-cloud-init`.

Judgement against the standard (preview-first, bounded, reversible, verified, correct on both
families): the 29 October paired plan gives target, preconditions, sequence and rollback. The
executable procedures underneath it are uneven. SSH policy is the clearest case: the engine's own
hardening checklist is correct and the provisioning runbook is wrong (defect D1). The automatic
update evidence step is wrong on current Fedora (defect D2).

### Task 2 — `sk-mysql-backup`, restore to a second instance, timed and verified

Ranker top four: `linux-disaster-recovery`, `linux-mysql-mariadb`, `kaizen-improvement-system`,
`linux-bash-scripting`. Both recovery skills are valid owners.

Read: `scripts/sk-mysql-backup.sh` (334 lines) and `references/backup-and-restore.md`. The
29 October repair holds on reading: private staging directory, `umask 077`, cleanup on failure,
validated retention, and a restore procedure that names the isolated target, elapsed time and
reconciliation. The existing lab evidence (`docs/kaizen/2026-10-engine-kaizen/samples/`) is the only
restore proof; this pass could not repeat it (no container permitted), so the restore result is
carried forward, not re-verified. Gaps found while reading: no least-privilege backup account is
specified (D8); the sourced configuration file is not trust-checked (D5).

The sibling task for PostgreSQL, run because `sk-pg-backup` is a **core** script installed by
`install-skills-bin core`, exposed the main findings of this pass (D3, D7).

### Task 3 — 502 after a PHP upgrade

Ranker top four: `linux-webstack`, `linux-filesystem-snapshots`, `linux-log-management`,
`cisco-ios-patterns`. Primary route correct; the next three are weak, but the hub worked example
names `linux-service-management` and `linux-log-management` as neighbours and the existing
collision fixture covers it. `references/php-upgrade-502.md` gives an ordered, evidence-first tree,
branches on the observed error, defines one change with before/after, and has a rollback that
restores vhost, pool and runtime together. No defect found. The disposable lab is simulated and
was not re-run (needs a container): carried forward from 29 October.

## Defect register

Severity: critical = a release blocker on safety or integrity grounds; major = wrong or unsafe
result on a common path; minor = misleading or incomplete without direct harm.

| ID | Sev. | Where | Defect and evidence |
|---|---|---|---|
| D1 | Critical | `01-provisioning-and-bootstrap/linux-server-provisioning/references/provisioning-steps.md` lines 121-171; `.../post-install-verification.md` line 89; `07-security-and-hardening/linux-server-hardening/SKILL.md` line 172; `notes/server-security.md` line 101; `02-users-access-and-secrets/linux-access-control/references/users-sudoers-pam.md` line 504 | Five procedures name the hardening drop-in `99-hardening.conf`. OpenSSH keeps the first value obtained across `Include` files in lexical order, so a cloud image's `50-cloud-init.conf` (`PasswordAuthentication yes`) wins. Fixture on OpenSSH 10.2: `sshd -T` returned `passwordauthentication yes` with the `99-` name and `no` with a `00-` name. The engine's own `hardening-checklist.md` already says so and uses `00-linux-skills-ssh.conf`: the engine contradicts itself. The remediation text (`post-install-verification.md` line 89) tells the operator to edit the same file again, so it cannot converge. [Sample](samples/d1-ssh-dropin-baseline.log). |
| D3 | Critical | `scripts/sk-pg-backup.sh` lines 191, 218, 238, 267 | Same class as the repaired MySQL defect, in a core script. No `umask`; backup directory created 0755; `pg_dumpall --globals-only` (role password hashes) redirected by the root shell into a 0644 file; dump files 0644; a failed `pg_dump` leaves a partial file named like a good backup; retention is unvalidated and its `find` errors go to `/dev/null` inside a pipeline whose status is ignored, so a run reports success. Stub fixture: directory 755, globals 644, run reported "Score: 100%". [Sample](samples/d3-pg-backup-modes-baseline.log). Inferred, not run: on a stock host `sudo -u postgres pg_dump --file=` cannot write into a root-created directory, so the first real run fails after the globals file is already world-readable. |
| D5 | Major | `scripts/sk-mysql-backup.sh` line 100; `scripts/sk-pg-backup.sh` line 101 | `source "$CONFIG_FILE"` as root without checking owner or mode: any writer of `/etc/linux-skills/*.conf` gets root code execution. `sk-pg-backup.sh` also loads the file after the flag loop (line 159), so configuration overrides command-line flags; the MySQL script orders them the other way. |
| D4 | Major | `scripts/lib/common.sh` lines 689-698 | Non-root audit-log fallback is `/tmp/linux-skills-$USER`, created with `mkdir -p`, without owner, mode or symlink validation. The same file validates every ancestor of `TMPDIR` for the cleanup registry (lines 56-80), so this is a leftover of the class closed there. Read from code; not reproduced, because it would write to the host `/tmp`. |
| D2 | Major | `01-provisioning-and-bootstrap/linux-package-management/references/dnf-reference.md` lines 53-57 | The evidence command `journalctl -u dnf-automatic -n 50` returns `-- No entries --` on a dnf5 host while `journalctl -u dnf5-automatic` shows the run (Fedora 44, dnf5 5.4.6.0; `dnf-automatic.timer` is a symlink to `dnf5-automatic.timer`). The same skill says Fedora 41+ uses dnf5. A "no entries" result reads as "updates never ran". [Sample](samples/d2-dnf-automatic-journal-baseline.log). |
| D7 | Major | `11-databases-and-caching/linux-postgresql/SKILL.md` lines 213-230; `references/backup-and-pitr.md` lines 14-60 | The PostgreSQL skill documents commands that write dumps to the working directory under the caller's umask, and has no restore-verification procedure with timing and reconciliation. MySQL gained one on 29 October. The scratch-restore advice is one sentence. |
| D8 | Minor | `11-databases-and-caching/linux-mysql-mariadb/references/backup-and-restore.md` | The examples use `/root/.mysql-backup.cnf` but never state what privileges the backup account needs (`mysqldump` on 8.0.21 and later needs `PROCESS` unless `--no-tablespaces`; routines and events need further grants). A practitioner defaults to root. Not changed this pass unless time allows; see backlog. |
| D6 | Minor | `07-security-and-hardening/linux-server-hardening/SKILL.md` line 198 | Hard-codes `/etc/php/8.3/fpm/php.ini` while the 502 reference tells the operator never to assume a PHP minor version. The hardening checklist already uses `$PHP_VER`. |
| D9 | Minor | `scripts/sk-mysql-backup.sh` lines 34-36 and 56-57 against line 100 | Help text says the configuration file is "overridable by environment variables"; sourcing the file after the defaults means the file overrides the environment. |
| D10 | Minor | routing ranker | Lexical ranker puts `netmiko-ssh-automation` first for "Disable SSH password authentication with a drop-in file" (`linux-access-control` second, `linux-server-hardening` third). The netmiko description already says "not for Linux host automation". `linux-server-provisioning`, `linux-access-control` and `linux-postgresql` have 0 positive and 0 owned-negative fixtures. |

Points where guidance was missing, contradictory or ignored: SSH drop-in naming (contradictory,
D1); PostgreSQL backup permissions and restore verification (missing, D3, D7); backup-account
privileges (missing, D8); dnf5 unit and package names (missing, D2).

Not assessed, with reason: `sk-capture.sh` pcap file mode (needs root and `tcpdump`); the other 22
scripts' failure and rollback behaviour (no lab); SELinux enforcing behaviour of the web stack on
RHEL; ACME renewal; Cisco appliance behaviour.

## Addendum written during Step 4 (original text above is unchanged)

- **Test count corrected.** The table above says nine `unittest` modules gave 62 tests. Summing the
  per-module results actually recorded (1, 8, 9, 10, 4, 9, 10, 6) gives **57** tests from eight modules;
  the ninth module, `test_validate_skills`, uses pytest-style functions and ran 0 tests under `unittest`.
  The 8 stand-in-runner passes are separate. Final comparisons use 57.
- **D3, partial dump.** The first baseline stub ignored `pg_dump --file=`, so it showed the directory and
  file modes but not the partial file. After the stub was made faithful, the case "a failed dump leaves
  no partial file" failed against the previous script as claimed ([old vs new](samples/p2-02-pg-backup-old-vs-new.log)).
- **D4 reproduced.** Running the new audit cases against the previous `common.sh` created
  `/tmp/linux-skills-<user>` mode 755 with a 644 audit log ([sample](samples/p2-04-audit-fallback-old-vs-new.log));
  the two paths were removed afterwards.
- **Installed copies are stale (new, host-level).** `/usr/local/bin/sk-mysql-backup` is version 0.3.0 and
  `/usr/local/lib/linux-skills/common.sh` dates from 15 June and lacks the temporary-directory validation, so the
  29 October repairs are not live on this workstation. `install-skills-bin --list` reports `yes` for an
  installed script that differs from the repository copy ([sample](samples/host-installed-copies-stale.log)).
  The installer would refuse to overwrite it without `--force`. Not fixed this pass (it would be an eleventh
  item); recorded in `06-next-cycle.md` with a decision for Peter.
- **`sk-capture.sh` (new, unverified).** Its default output directory is `/var/log/linux-skills` and it starts
  `tcpdump` without `-Z`; the `tcpdump` manual on this host says privilege dropping to user `tcpdump` is enabled by
  default before savefiles open. Failure and pcap mode need root: `NOT_ASSESSED`, in `06-next-cycle.md`.
- **Ranker artefacts (D10 detail).** Lexical ranking lists `linux-mysql-mariadb` in the top three for
  PostgreSQL prompts (its description names `linux-postgresql`) and `netmiko-ssh-automation` for SSH user
  prompts. Recorded, not tuned.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
