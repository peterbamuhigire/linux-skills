# Scope and evidence — Linux lab wave, 31 October 2026

Engine: Linux Skills (Chwezi Core Systems). Router: `AGENTS.md`; hub skill `linux-sysadmin`.
This is a special wave on top of the 29 October cycle (`docs/kaizen/2026-10-engine-kaizen/`) and pass 2
(`docs/kaizen/2026-10-engine-kaizen-pass-2/`). It exists to turn the standing P1, "approved isolated
Debian and RHEL-family labs with repeated-run, controlled-failure and actual restore verification",
from `NOT_ASSESSED` into measured results wherever a throwaway rootless Podman container can do it.

## Step 0 — preconditions

| Item | Value |
|---|---|
| Starting branch / HEAD | `main` at `74e2b6de09576b6058401c6c2d76a3c6c0899204` (pass 2 already merged) |
| `git status --porcelain` before any action | 0 lines (clean tree) |
| Branch created | `kaizen/2026-10-linux-wave`, from the same HEAD |
| Evidence folder | `docs/kaizen/2026-10-linux-lab-wave/` |
| Read first | the shared agent brief and the wave brief; the standard cycle prompt; 29 October and pass-2 `05-final-report.md` and `06-next-cycle.md`; `AGENTS.md` |

Lab boundary, as set by the wave brief and kept:

- Rootless Podman 5.8.9 only, local images only (`quay.io/fedora/fedora:44`, `docker.io/library/debian:bookworm`,
  `docker.io/library/mysql:8.4`, `docker.io/rclone/rclone:latest`). No image was pulled. Packages were installed
  with `apt-get` and `dnf` inside the containers; nothing was installed on the host.
- No `--privileged`, no `--network=host`, no host system path mounted, no `:z` or `:Z`. The repository reached
  containers by `podman cp` of a `git archive` copy in the scratch area (and, for the MySQL lab, a read-only bind
  mount of that copy with `label=disable`).
- Every container is named `lskw-...`. Real systemd was PID 1 in the Debian and Fedora containers (`--systemd=always`
  with a package install first, then `exec` of systemd), so `systemctl reload`, `stop` and `start` are real.
- The host was not touched: no `sudo`, no `sk-*` script run on the host, no change to `/usr/local/bin` or
  `/usr/local/lib/linux-skills`.

## Registered gates at baseline (HEAD `74e2b6d`, before any change)

Output frozen in [samples/registered-gates-baseline.log](samples/registered-gates-baseline.log).

| Command | Exit | Result |
|---|---:|---|
| `python3 -X utf8 scripts/validate_skills.py --baseline quality-baseline.json` | 0 | 48 active skills, 1 template, 48 compliant |
| `python3 -X utf8 scripts/routing_smoke_test.py` | 0 | 95/95 valid; P@1 82/95 (0.863); P@3 95/95; 14/48 skills at 3 positives + 2 owned negatives |
| `bash scripts/tests/check-distro-matrix.sh` | 0 | 41 passed, 0 failed |
| `python3 -X utf8 scripts/validate_safe_operation_fixture.py tests/fixtures/safe-operation-evidence.json` | 0 | fixture cases pass |
| `python3 -X utf8 scripts/source_ingestion_guardrail.py` | 0 | 0 findings |
| `python3 scripts/check_marketplace.py` | 0 | 397/5000 package files; 971/5000 checkout entries |
| `node scripts/generate-plugin-manifest.js ... --check` | 0 | plugin.json current, 45 skills |
| `bash scripts/tests/common-sh.test.sh` | 0 | 42 passed, 0 failed |
| Full suite, real pytest from the shared venv, `-p no:cacheprovider`, `PYTHONDONTWRITEBYTECODE=1` | 0 | **102 passed, 1 skipped**, 22 subtests passed (equals the pass-2 result) |
| `python3 scripts/kaizen_metrics.py --as-of 2026-10-31 --baseline <pass-2 metrics-final.json>` | 0 | hygiene regression gate pass; machine-specific links 0, dangling paths 0, dangling anchors 0, duplicate contract headings 0, expired source rows 0 (frozen as `metrics-baseline.json`) |

`NOT_ASSESSED` at baseline, with the reason: `sudo bash scripts/tests/install-skills-bin.test.sh` (CI runs it
under `sudo`, prohibited here); hosted CI for new commits (nothing is pushed); `claude plugin validate` and live
marketplace loading (not re-run).

## Step 1 — observation: the labs, run against the unchanged scripts and procedures

Each lab ran the repository's own text. For documents, the fenced code blocks were extracted verbatim from the
Markdown and executed; a block that cannot run as written is recorded as a defect, not edited in the lab.

| Lab | Image and versions | Result on the unchanged repository |
|---|---|---|
| SSH drop-in beside a cloud-init `PasswordAuthentication yes` file ([Debian](samples/lab-ssh-dropin-debian12-baseline.log), [Fedora](samples/lab-ssh-dropin-fedora44-baseline.log)) | `debian:bookworm`, OpenSSH 9.2; `fedora:44`, OpenSSH 10.2; real `sshd` under systemd | `00-linux-skills-ssh.conf` wins in both: `sshd -T` reports the intended values, a real `sshpass` password login is refused, key login works for the allowed user only, root and a second user are refused. The old name `99-hardening.conf` loses in both: `sshd -T` says `passwordauthentication yes` and a real password login succeeds. A syntax error is caught by the procedure's `sshd -t` before reload; no reload reached `systemctl`; the running daemon kept enforcing the previous policy. **Fedora: the procedure's `systemctl reload ssh` fails (`Unit ssh.service not found`, exit 5), in the apply step and in the rollback step (defect W2).** |
| Plain reload with a broken drop-in ([log](samples/lab-ssh-plain-reload-broken-dropin.log)) | both | Debian's unit runs `sshd -t` in `ExecReload` and refuses the reload (daemon stays active). Fedora's unit does not: the reload exits 0, `sshd` exits 255 and sits in `activating (auto-restart)`. On the RHEL family the explicit `sshd -t &&` guard is the only protection. |
| `sk-pg-backup` against a real PostgreSQL ([Debian 12, PostgreSQL 15.19](samples/lab-pg-backup-debian12-pg15-baseline.log), [Fedora 44, PostgreSQL 18.6](samples/lab-pg-backup-fedora44-pg18-baseline.log)) | systemd containers, synthetic data (5 000-row table with trigger, view, index, extension, grants; a database named `lab odd;db`) | Dry run writes nothing. Real run: directory 0700, every file 0600, no staging left, globals hold `CREATE ROLE` and a SCRAM hash, `pg_restore --list` reads both dumps, the awkward name is sanitised. Repeated run adds a second set; retention prunes only this script's expired files and leaves unrelated old files. Controlled failures all exit non-zero with nothing published: missing database (exit 1), PostgreSQL stopped (`--all` and `--db`, exit 1, directory unchanged), unwritable path (exit 1), write failure under `ulimit -f` (exit 1), truncated dump via a `pg_dump` wrapper (exit 1, `pg_restore --list` gate), world-writable config (exit 3), retention 0 (exit 2). Findings: W4, W5, W6. |
| PostgreSQL "Verify a logical backup" procedure, run step by step on a scratch instance ([Debian](samples/lab-pg-restore-debian12-baseline.log), [Fedora](samples/lab-pg-restore-fedora44-baseline.log), [parallel stdin](samples/lab-pg-restore-parallel-stdin.log)) | a second container per distro with its own empty cluster | The documented commands run as written. Globals restore returns 0 with the documented harmless `role "postgres" already exists`; `pg_restore --exit-on-error --create --dbname=postgres < dump` restores both databases in about 0.3 s; all 11 reconciliation figures (row counts, content md5, indexes, triggers, views, extensions, sequence, owner, grant) equal the dump-time figures (Fedora log). A second `--create` restore refuses; a truncated dump fails loudly; `pg_restore -j` from standard input fails with the manual's message, as the procedure says. The Debian log's single `FAIL` is a capture error in the lab driver (stderr mixed into the comparison file); the figures printed beside it are identical. |
| MySQL 8.4 backup, restore, repeat, controlled failure ([log](samples/lab-mysql84-existing-backup-restore-baseline.log)) | `mysql:8.4` (8.4.13) and `rclone` local backend | The existing opt-in lab `tests/test_mysql_backup.py` passes: encrypted backup, restore into a second instance with trigger and routine counts, repeat with distinct names, GPG failure and rclone-retention failure, invalid retention refused. 1 passed in 51.9 s. |
| MySQL least-privilege account ([log](samples/lab-mysql84-least-privilege-account.log), [PROCESS probe](samples/lab-mysql84-process-privilege-probe.log)) | `mysql:8.4` | New in this wave. The `CREATE USER` and `GRANT` lines taken verbatim from the pass-2 "Backup account" section work: every schema (including `mysql`) is in the archive, the restore reconciles rows, triggers, routines, events and views, and eight write attempts (INSERT, UPDATE, DELETE, CREATE, drop-table, CREATE USER, GRANT, `UPDATE mysql.user`) are refused. Narrowing: no `PROCESS` gives an access-denied message about tablespaces on standard error but exit 0 and a complete dump (W3); no `RELOAD` with GTIDs off needs nothing more; an account that cannot see a schema omits it and the run reports success (as documented); an account that sees a schema it cannot read stops the script with `mysqldump failed` (exit 1, as documented). |
| ShellCheck 0.9.0 over all 36 shell sources ([summary](samples/lab-shellcheck-0.9.0-summary-baseline.log), [findings](samples/lab-shellcheck-0.9.0-findings-baseline.txt)) | `debian:bookworm` | 95 findings: 0 errors, 28 warnings, 67 notes. All 28 warnings triaged: 25 are SC2034 for variables read by the sourced library (`SCRIPT_VERSION`, `YES`), 3 are SC2024 in `sk-pg-backup` where the root shell opens the file on purpose. No defect found. Notes are SC2317 (functions called through `trap`), SC2015 (`A && B || C` where `pass` cannot fail), and style items. |
| Automatic updates, Debian 12 ([shipped config](samples/lab-unattended-upgrades-debian12-shipped-config.log), [documented origins](samples/lab-unattended-upgrades-debian12-documented-origins.log)) | `debian:bookworm` | With the engine's documented `Allowed-Origins` the dry run says `No packages found that can be upgraded unattended` while `apt-get -s dist-upgrade` shows a pending security update (tzdata). The shipped Debian configuration upgrades it. **Defect W1.** |
| Automatic updates, Fedora 44 ([setup](samples/lab-dnf5-automatic-fedora44-setup.log), [evidence](samples/lab-dnf5-automatic-fedora44-evidence.log)) | `fedora:44`, dnf5 5.4.6.0 | The pass-2 guidance holds: `dnf install dnf-automatic` installs `dnf5-plugin-automatic`; `dnf-automatic.timer` is an alias; `dnf5-automatic.timer` is disabled by preset and enabling the alias creates the real symlink; defaults as stated; the real service ran and `journalctl -u 'dnf*automatic*'` shows the run while `journalctl -u dnf-automatic` prints `-- No entries --`. `dnf updateinfo list updates security` on dnf5 answers `No advisory found matching the requested name: "updates, security"` with exit 0 (the page attributes that form to Red Hat and gives the dnf5 form). |

## Defect register

Severity: critical = a release blocker on safety or integrity grounds; major = wrong or unsafe result on a
common path; minor = misleading or incomplete without direct harm.

| ID | Sev. | Where | Defect and evidence |
|---|---|---|---|
| W1 | Critical | `01-provisioning-and-bootstrap/linux-server-provisioning/references/provisioning-steps.md` lines 243-244 (section 5); `07-security-and-hardening/linux-server-hardening/references/hardening-checklist.md` lines 598-599; `01-provisioning-and-bootstrap/linux-package-management/references/unattended-upgrades-reference.md` lines 86-115 and 282-283 | The procedures tell a Debian 12 operator to allow `"${distro_id}:${distro_codename}-security"`. That expands to `o=Debian,a=bookworm-security`. Debian's security archive publishes `Origin: Debian`, `Label: Debian-Security`, `Suite: oldstable-security`, `Codename: bookworm-security`; the `a=` field is the Suite, so the pattern matches nothing. Lab: `Allowed origins are: o=Debian,a=bookworm-security, ...`, then `No packages found that can be upgraded unattended` with tzdata 2026e to 2026f pending from `bookworm-security`. Timers are active and the verify step's "Expected" text is satisfied by a run with nothing pending, so a host with no automatic security updates looks configured. Ubuntu names its suites after the codename, which is where the pattern comes from; the reference file says `Ubuntu`/`UbuntuESM` and is Ubuntu-only while the skill says "Debian and Ubuntu". Same class as pass-2 D1: a security control that is silently inert. |
| W2 | Major | `07-security-and-hardening/linux-server-hardening/references/hardening-checklist.md` lines 126, 207, 224; `01-provisioning-and-bootstrap/linux-server-provisioning/references/provisioning-steps.md` lines 170, 180; `.../post-install-verification.md` line 89; `.../linux-server-hardening/SKILL.md` matrix row "SSH hardening ... identical"; provisioning `SKILL.md` matrix has no SSH row | `systemctl reload ssh` is the Debian unit name. On the RHEL family it fails: `Failed to reload ssh.service: Unit ssh.service not found.` (exit 5) in the apply step and in the rollback step, so the file is written but not applied, and a rollback removes the file without reloading. Both skills say the SSH steps are the same on both families. `sshd` works on Fedora (real unit) and on Debian 12 (an alias created when `ssh` is enabled; `systemctl reload sshd` exited 0). On Fedora the unit has no `ExecReload=sshd -t`, so a plain reload with a bad drop-in takes the daemon down (`activating (auto-restart)`), which makes the checklist's `sshd -t &&` guard the only protection there. |
| W3 | Minor | `11-databases-and-caching/linux-mysql-mariadb/references/backup-and-restore.md` "Backup account" | The documented `GRANT` includes `PROCESS`, which exposes every session's statements. Lab: without it `mysqldump` (8.4.13) prints `Access denied; you need (at least one of) the PROCESS privilege(s) ... when trying to dump tablespaces` on standard error, still exits 0 and dumps every schema; the only loss is `CREATE TABLESPACE` statements for general tablespaces, and the `TABLESPACE` clause stays in `CREATE TABLE`. The page presents `PROCESS` as a need and omits the exit-0 behaviour. |
| W4 | Minor | `scripts/sk-pg-backup.sh` (lines 272, 292 and 315, every `sudo -u "$PG_USER"` call) | On Debian the `pg_wrapper` prints `could not change directory to "/root": Permission denied` for every client call run as `postgres` from a directory it cannot enter. Cron starts root jobs in `/root`, so each run mails two warnings per database. Fedora prints nothing. The PostgreSQL restore procedure shows the same line when run from such a directory. |
| W5 | Minor | `scripts/lib/common.sh` lines 827-854 (`_sk_cleanup`) | After every `die` the failure banner reads `FAILURE: <script> exited N at line 1` and `last command: exit "$code"`: `BASH_COMMAND` and `BASH_LINENO` are read inside the `EXIT` trap, after `die` ran, so the location is always wrong. All 26 scripts print it. |
| W6 | Minor | `scripts/sk-pg-backup.sh` usage text ("A failed run leaves nothing that looks like a backup") and lines 292-298 | Globals are published before the first dump. A failed run (missing database, write failure) leaves `globals_<timestamp>.sql` with no dumps next to it. Retention removes it later. The sentence is stronger than the behaviour. |

Also observed, not defects: Fedora `postgresql-setup --initdb` failed in a container without D-Bus
(`Failed to connect to system scope bus`, then `no db datadir (PGDATA) found`) and succeeded once
`dbus-broker` was installed. The lab prerequisite is recorded in the lab driver; the documented procedure is
for a host that has D-Bus.

Points where guidance was missing, contradictory or ignored: Debian security-suite matching (contradictory:
the reference file says Ubuntu, the procedure says Debian, W1); the SSH service name on the RHEL family
(missing, W2); what happens without `PROCESS` (missing, W3).

## Not assessed, with reason

- Full enterprise RHEL (Rocky, Alma, RHEL 9 or 10 with subscription), Debian 13, Ubuntu LTS: no image on the machine, none pulled. Fedora 44 and Debian 12 are two members of the two families, not the families.
- Real cloud image with cloud-init: the lab imitates its `50-cloud-init.conf`; cloud-init itself was not run.
- Enforcing SELinux, firewalld, nftables and UFW behaviour: not exercised in an unprivileged container.
- Active Directory join, ACME issuance or renewal, hosted CI: out of scope for the wave.
- Production-size backups, real disk exhaustion (a file-size limit stands in), remote object-store outage.
- Ubuntu's `Allowed-Origins` behaviour: no Ubuntu image; the Debian result says nothing about it.
- The other 22 `sk-*` scripts (mutating host scripts) were not run, even in containers: each needs its subsystem (LVM, auditd, nftables, kernel modules) that an unprivileged container does not provide.
