# Improvement backlog — 31 October 2026

Owner for every item: Peter Bamuhigire / Linux engine maintainer. Due: this cycle; re-audit
2026-11-07. Target remains 95/100 raw; contributions name dimensions, not guaranteed points.
Every change is repository or fixture scoped. Rollback for each item is a reviewed `git revert`
of its commit; no host is changed, so no host rollback exists. Ten items are selected. Work
that is structural, needs a lab, or crosses engines is in `06-next-cycle.md`.

## Selected items (execution order)

| Item / priority | Gap and root cause | Exact change and hypothesis | Acceptance evidence | Risk and stop condition / target |
|---|---|---|---|---|
| P2-01 P0 | D1. Five procedures name the SSH hardening drop-in `99-hardening.conf`; OpenSSH keeps the first value, so cloud-image defaults win. Root cause: the procedure was written from the file layout, never checked against effective values, and no check read the procedures. | Rename the drop-in to `00-linux-skills-ssh.conf` in all five files, state the precedence rule where the file is first created, and replace the non-converging remediation line with a check that finds the competing definition. Hypothesis: the documented drop-in then yields the intended `sshd -T` value on a host that ships `50-cloud-init.conf`. | New `tests/test_ssh_dropin_precedence.py`: fails on the unfixed docs (3 failures recorded in `samples/d1-ssh-dropin-baseline.log`), passes after; negative control proves the fixture detects the failure. | Documentation only. Stop if `sshd -T` rejects the documented block. Safety, output readiness, skill depth. |
| P2-02 P0 | D3. `sk-pg-backup` writes role hashes and dumps world-readable, can leave partial dumps and reports success on a failed rotation. Root cause: the 29 October backup repair was scoped to the MySQL script; the sibling had no fixture, so the same class stayed. | Private 0700 staging directory, `umask 077`, dumps written by the root shell from `pg_dump` standard output into staging then renamed, validated retention with a script-name-only pattern, retention errors fail the run, sanitised file names. Hypothesis: every artefact is 0600 in a 0700 directory and a failed run leaves no file that looks like a backup. | New stub-based `tests/test_pg_backup.py`: modes, partial-dump cleanup, retention validation, retention failure exit, name sanitising, dry-run writes nothing. Baseline modes recorded. | Stub fixture only; a real restore is `NOT_ASSESSED`. Stop if any artefact is not 0600. Safety, output readiness, applied proof. |
| P2-03 P1 | D5. Both backup scripts `source` a root-run configuration file without trust checks; `sk-pg-backup` loads it after the flags so it overrides them. Root cause: configuration loading was copied between scripts and never reviewed as an input boundary. | Add `sk_source_trusted_config` to `common.sh` (regular file, not a symlink, owned by root or the caller, not writable by group or others, parent directory likewise); use it in both scripts; load configuration before flags in `sk-pg-backup`. | Cases in `scripts/tests/common-sh.test.sh`: accepted, group-writable, world-writable, foreign owner, symlink, missing; static test that no script sources a configuration path directly. | A deployment with a group-writable file now stops with a clear message. Stop if a mode-0644 root-owned file is rejected. Safety. |
| P2-04 P1 | D4. Non-root audit fallback uses an unvalidated predictable `/tmp` directory. Root cause: K01 validated the cleanup registry and left this second `/tmp` use. | Resolve the fallback under the already-validated `SK_TEMP_BASE`, create it 0700, verify owner, mode and not-a-symlink, and drop audit writes (with one warning) if it is untrusted. | Fixture cases with a scratch `TMPDIR`: created private; pre-existing foreign-mode directory rejected; symlink rejected; audit line written when trusted. | Audit lines may move for non-root runs; root path unchanged. Stop if a root run changes behaviour. Safety. |
| P2-05 P1 | D2. The dnf automatic evidence command prints nothing on dnf5 hosts. Root cause: the reference was written for dnf4 and never compared with the dnf5 unit names the same skill mentions. | Split the reference by dnf generation: package, timer and service unit, configuration file, and the matching `journalctl -u` unit; state that `dnf-automatic.timer` is an alias on dnf5. RHEL generation checked against Red Hat documentation (currentness record). | Observed unit and journal behaviour on Fedora 44 (sample); Red Hat documentation source recorded with access date; validators pass. | The RHEL-family claim rests on documentation, not a RHEL host: labelled. Stop if the source contradicts the split. Skill depth, currency. |
| P2-06 P1 | D7. PostgreSQL skill has no private-dump guidance and no timed, verified restore procedure. Root cause: PostgreSQL was documented as a command list; the recovery contract was added only for MySQL. | Add a permissions rule and a "Verify a logical backup" procedure to `references/backup-and-pitr.md` (scratch cluster or database, elapsed time, object and row reconciliation, evidence to record), linked from `SKILL.md`; align the script manifest row. | Reading against the MySQL procedure; fixture proves the script side (P2-02). Actual restore `NOT_ASSESSED` (no PostgreSQL lab permitted): stated in the text. | A procedure not exercised in a lab; labelled so. Stop if it contradicts P2-02 behaviour. Production and handoff. |
| P2-07 P2 | D10 and coverage. `linux-server-provisioning`, `linux-access-control`, `linux-postgresql` have no routing fixtures. Root cause: fixtures were added only for skills touched on 29 October. | Add three positives and two owned negatives for each (15 fixtures), raise the fixture count in `quality-baseline.json`. No ranker tuning to fit the cases. | `routing_smoke_test.py` valid count, P@3, and coverage rising from 11/48; failures reported, not hidden. | If a case fails, fix the skill description or drop the case with a reason; never weaken the ranker. Taxonomy and routing, applied proof. |
| P2-08 P2 | Hygiene debt carried from 29 October: 5 dangling paths, 10 dangling anchors, 10 duplicate References headings; D6 stale hard-coded PHP path. Root cause: the gate blocks regression, not repayment. | Repair link targets and anchors to the real headings, merge duplicate References sections without deleting content, replace the PHP path with the installed-path rule; write a pass-2 metrics baseline and point the CI hygiene gate at it so the repayment cannot regress. | `kaizen_metrics.py` before/after, same parser; `test_kaizen_metrics`; CI workflow diff. | Historical wave documents point at files that never existed in this tree: repaired by retargeting, not by inventing content. Hygiene. |
| P2-09 P2 | Currency. Ten source rows expired; the 29 October matrix did not cover PHP, MySQL, PostgreSQL, Nginx or Apache support windows. | Re-verify against primary sources; record source, access date, support state and review date in `currency.md`; update `Last verified` only where verified. | Fetched primary sources listed with dates; unverifiable items `NOT_ASSESSED`. | A source that cannot be fetched stays `NOT_ASSESSED`. Standards currency. |
| P2-10 P2 | D8. The MySQL backup procedure never says what the backup account may do. | Add a least-privilege account section sourced from the MySQL reference manual; mark the grants as documentation-derived, not lab-tested. | Source and access date recorded; text says untested here. | Dropped to `06-next-cycle.md` if the source cannot be fetched. Production and handoff. |

## Five Whys

D1 and D3 (critical):

1. Why can an operator leave SSH passwords on, and why can a dump be read by any user? The
   procedure names a file that loses precedence, and the script writes under a default umask.
2. Why was neither caught? Both were judged by whether the commands ran, not by the effective
   state (`sshd -T`, file modes).
3. Why only effective-state checks for MySQL? The 29 October work reproduced and fixed the
   defects it found in the MySQL path; it did not search the sibling script or the sibling
   procedures for the same pattern.
4. Why no search? There was no fixture or scanner for the class, so nothing made the pattern
   visible when it was fixed once.
5. Process cause: a fix was closed on the instance, not on the class. The repair is a fixture
   per instance now (P2-01, P2-02) and a scan for the class (SSH drop-in naming scan, "no script
   sources a configuration path directly"), recorded in `06-next-cycle.md` for the remaining
   scripts.

D4 and D5 follow the same trace: validated temporary ancestry was added to one library function
and not applied to the two other places that trust a path.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
