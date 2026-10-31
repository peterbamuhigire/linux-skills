# Next cycle and handoffs — after the lab wave

Owner: Peter Bamuhigire. Re-audit **2026-11-07** with pass 2's date, or earlier on a relevant advisory or when
PostgreSQL 14 reaches its final release (2026-11-12). The 95/100 raw target is not reached and the gap is not closed
by scoring. Items carried from earlier cycles are marked *carried*; each was checked open before it was kept.

## Decisions needed from Peter

1. **Installed copies.** Unchanged from pass 2 and now one change older: `sk-pg-backup` and `common.sh` differ again.
   `sudo install-skills-bin core --force` after reading the diff (see the [operator note](operator-note.md)). Not run: no
   `sudo`.
2. **`--no-tablespaces` for `sk-mysql-backup`.** The lab shows `PROCESS` is optional: without it `mysqldump` exits 0 with
   an access-denied line on standard error (cron mails it) and leaves out `CREATE TABLESPACE` for general tablespaces.
   Passing `--no-tablespaces` removes the noise and the need for `PROCESS`, and changes the dump for servers that use
   general tablespaces. Left as is.
3. **Globals before dumps in `sk-pg-backup`.** A run that fails on a later database leaves a globals file with no dumps.
   The usage text now says so. Publishing the whole set only at the end would remove that, at the cost of losing the
   dumps that did succeed when one database fails. Left as is.

## Open work

| Priority | Open work and acceptance evidence |
|---|---|
| P1 | *Carried.* Approved Debian 13, Ubuntu 22.04 and 24.04, and enterprise RHEL-family disposable machines: real boot, enforcing SELinux, firewall and recovery console, ACME staging renewal. Rerun `tests/test_distro_labs.py` there. Ubuntu is the open question for three changes: the `Allowed-Origins` form kept for Ubuntu (not run), whether `systemctl reload sshd` works under socket activation on 24.04, and `sshd` as an alias there. |
| P1 | Run the host-mutating scripts that an unprivileged container can run, in the same style as `sk-pg-backup`: `sk-rsync-backup` (rsync), `sk-tar-verify`, `sk-mysql-health` (the `mysql:8.4` image), `sk-perf-snapshot`, `sk-update-all-repos`. Positive, repeated-run and controlled-failure cases, with a static scanner for output modes and swallowed pipeline status. The other scripts need LVM, auditd, nftables or kernel modules. |
| P1 | `sk-capture.sh` (lines 146 to 151 and 179): default output in a root-owned 0750 directory and `tcpdump` started without `-Z`. A rootless container's root may run `tcpdump` (default `CAP_NET_RAW`): try it there to measure the privilege-drop failure and the pcap mode that pass 2 could only read about. |
| P1 | *Carried.* `install-skills-bin --list` should show a `differs` state for an installed script that differs from the repository copy; test fixture in `scripts/tests/install-skills-bin.test.sh` (needs `sudo` in its own test). |
| P1 | Production-size backup RPO and RTO, real storage exhaustion (the lab used `ulimit -f`), remote outage, retention expiry. *Carried.* |
| P2 | Give the PostgreSQL lab a second major version (the Debian 13 package, once an image exists) to show a restore into a newer major, which the restore page lists as `NOT_ASSESSED`. |
| P2 | Routing fixtures for eight skills touched only mechanically in pass 2 and still below 3+2: `linux-cloud-init`, `linux-config-management`, `linux-dns-server`, `linux-mail-server`, `linux-network-admin`, `linux-observability`, `linux-secrets`, `linux-virtualization` (31 of 48 skills lack 3+2; the lexical ranker's artefacts from pass 2 stand). |
| P2 | `install-skills-bin --help` still lists exit code 3 as "not Debian/Ubuntu". `provisioning-steps.md` still expects "PostgreSQL 14.x (22.04)" after 2026-11-12. RHEL 10 dnf-automatic unit names (carried). |
| P2 | `scripts/setup-claude-code.sh` lines 105 to 119 hold absolute paths under one user's home (skills root, SSH key, known-hosts file, recovery file). Found by the final path scan; not touched here. Decide whether they are an example for one workstation (then say so in the text) or should be parameters. |
| P2 | LSR-03 and LSR-09 partial rows from pass 2; Ubuntu CIS rows never re-fetched (carried). |

## Cross-engine mismatches and boundaries

No sibling checkout was edited. The matches below were found with a read-only `grep` over the sibling checkouts and
are the same two faults this wave fixed here; the counterpart engine's cycle owns the change.

- **Ubuntu origin pattern in the engineering catalogue (`skills-web-dev` on this machine, `chwezi-dev-engine` upstream).**
  `"${distro_id}:${distro_codename}-security"` appears in `docs/scaling-ops/05-security-hardening.md` line 146;
  `skills/devops-cloud/cicd-pipelines/references/cicd-jenkins-debian/references/jenkins-host-tuning.md` line 258 (a
  Debian-named reference); and `skills/security/linux-security-hardening/references/patch-management.md` lines 55 and 161.
  On Debian that pattern matches nothing (this repository's `samples/lab-unattended-upgrades-debian12-*.log`). Whether those
  files scope it to Ubuntu was not read in full. Counterpart side here: `provisioning-steps.md` section 5 and
  `unattended-upgrades-reference.md`.
- **`systemctl reload ssh` in the same catalogue.** `skills/security/network-security/SKILL.md` line 157,
  `skills/security/network-security/references/ssh-bastion.md` line 105 (labelled Debian 12+) and
  `skills/security/linux-security-hardening/references/pam-authentication.md` line 249. Correct on Debian, a failure on the
  RHEL family; whether each is Debian-scoped was not checked.
- **Engine names after the upstream renames** (carried): `AGENTS.md` lines 46, 59 and 175 name `digital-research-engine`
  and `chwezi-dev-engine`; local checkouts are `chwezi-research-engine` and `skills-web-dev`. Unchanged. This wave's lab
  support code finds no sibling checkout, so nothing fails on the names.
- **Shared safety model, financial backup retention, research engine currentness gate** (carried): unchanged from pass 2;
  counterpart files not read.
- **A lab pattern the Windows engine could reuse.** `tests/lab_support.py` runs a package install, then `exec`s the
  init system as PID 1 in a rootless Podman container, extracts documented fenced blocks verbatim and runs them. The
  Windows engine's counterpart (`windows-admin-engine-skills`) was not inspected; a Windows-side equivalent would need a
  Windows image, which this machine does not have.

## One small experiment for next time

On the same Podman images, run `sk-rsync-backup` (or `sk-tar-verify`) against a synthetic tree: first run, second run
(nothing to do), a changed file, a deleted source file with and without `--delete`, an unwritable destination and a
destination that disappears mid-run. Assert modes, exit codes and that nothing is deleted without the flag. If one
assertion fails, fix the script first, with a case that fails before.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
