# Pass 2 final report — 31 October 2026

Linux Skills, second Kaizen cycle under the Portfolio Kaizen Standard. **The 95/100 raw target is not
achieved.** Both critical defects found by a fresh observation (an SSH hardening procedure that left
password login enabled on cloud images, and a core PostgreSQL backup script that wrote world-readable
role password hashes) are fixed and verified inside fixture boundaries. Nothing was run on a real
PostgreSQL server, enterprise RHEL host or container, and no production host was changed or certified.

Branches: started on `main` at `f904f7b`; work on `kaizen/2026-10-pass2` (10 item commits plus
evidence commits). Nothing was pushed, tagged or merged. The checkout is returned to `main` at the
end of the run.

## Scores

Ten equally weighted Standard dimensions; reviewer judgements with the named evidence, not
percentages of anything. The pass-2 baseline is lower than the 29 October final because the fresh
observation found defects that cycle did not; it was measured before any change.

| Dimension | 29 Oct final | Pass 2 baseline | Pass 2 final | Evidence and remaining deficiency |
|---|---:|---:|---:|---|
| Doctrine | 85 | 85 | 85 | Unchanged. The checklist and runbooks now agree on SSH precedence; conformance across all 26 scripts is unmeasured |
| Taxonomy and routing | 75 | 72 | 74 | 95 fixtures, P@1 0.863, P@3 1.000, 14 of 48 skills at 3+2; 34 lack it; ranker artefacts recorded, not tuned |
| Skill depth | 75 | 72 | 78 | SSH, dnf generations, PostgreSQL private dumps and restore verification, MySQL backup account; worked-example depth unchanged (medians 2 and 4.5) |
| Applied proof | 65 | 60 | 68 | 28 new stub and `sshd -T` tests, each failing before its fix; no PostgreSQL lab, MySQL lab not re-run |
| Standards currency | 65 | 65 | 72 | Ten expired rows to zero (8 verified, 2 partial); PHP, PostgreSQL, MySQL, Nginx, Apache windows dated; host applicability still unassessed |
| Output readiness | 80 | 70 | 78 | `sk-pg-backup` output private and verified-before-publish; SSH runbook effective; not every output type executed |
| Accessibility and inclusion | 65 | 65 | 65 | Plain text, explicit unknown states; no practitioner accessibility test |
| Production and handoff | 75 | 72 | 77 | Operator note, PostgreSQL restore procedure (untested), backup-account spec; installed copies on the workstation remain stale |
| Hygiene | 75 | 75 | 82 | Paths 5 to 0, anchors 10 to 0, duplicate headings 10 to 0, expired rows 10 to 0, CI ratchet; external links not fetched |
| Safety and integrity | 80 | 65 | 77 | D1, D3, D4, D5 fixed within tested limits; 22 scripts without failure fixtures, `sk-capture` unverified, stale installed copies |

Raw mean: 29 Oct final **74.0**; pass-2 baseline **70.1** (701/10); pass-2 final **75.6** (756/10).
Published score `min(raw, 65)`: **65.0** at all three points (`min(75.6, 65) = 65`). Net of the
defects this pass found, the engine is 1.6 raw points above the 29 October final and 5.5 above
its own fresh baseline. The cap is a reporting ceiling and does not hide the 19.4-point gap to 95.

## Kept changes and evidence

All ten items kept; none reverted. Detail in [03-experiment-log.md](03-experiment-log.md), checks in
[04-validation-record.md](04-validation-record.md), sources in [currency.md](currency.md).

| Commit | Item | Retained change |
|---|---|---|
| `39b11fe`, `da3f050` | P2-00 | Frozen baseline, defect register, backlog |
| `6f30e09` | P2-01 | SSH drop-in renamed to `00-linux-skills-ssh.conf` in five procedures; precedence rule and non-looping remediation; `test_ssh_dropin_precedence.py` |
| `cae7544` | P2-02 | `sk-pg-backup` private staging, 0600/0700, `pg_restore --list` gate, validated retention, name sanitising; `test_pg_backup.py` |
| `ec2a269` | P2-03 | `sk_source_trusted_config`; both backup scripts use it; flags-over-file; helper-missing guard; static guard test |
| `054c45c` | P2-04 | Audit-log fallback under validated temp base, 0700, owner and symlink checked |
| `9ce3518` | P2-05 | dnf automatic-update guidance split by dnf generation; journal pattern that works on both |
| `62f2e56` | P2-06 | PostgreSQL private-dump rule and "Verify a logical backup" procedure |
| `221871c` | P2-07 | 15 routing fixtures for provisioning, access control, PostgreSQL |
| `fc0c8af` | P2-08 | Link, anchor and heading debt repaid; stale PHP path fixed |
| `1ef490f` | P2-09 | Ten source rows re-verified; pass-2 currency record; RHEL 9 PostgreSQL stream guidance |
| `d42cd1f` | P2-10 | MySQL backup-account privileges and the schema-visibility trap |

The final evidence commit (these seven files, samples, the operator note, the router pointer and the
CI ratchet) follows this ledger; find it with `git log --oneline -- docs/kaizen/2026-10-engine-kaizen-pass-2/05-final-report.md`.

Routing fixtures: the three skills with substantive changes now meet 3 positives and 2 owned negatives.
Of the 16 skills the diff touches, 7 meet it; the other nine had a heading renamed or a link repaired
and are listed in [04-validation-record.md](04-validation-record.md) and `06-next-cycle.md`.

## Critical defects

| ID | Status |
|---|---|
| D1 SSH drop-in loses to cloud-init | Fixed and verified: `sshd -T` effective value `no` with the documented drop-in beside `50-cloud-init.conf` (OpenSSH 10.2, fixture). Real cloud-image host: `NOT_ASSESSED` |
| D3 `sk-pg-backup` world-readable role hashes | Fixed and verified with stubs: directory 700, files 600, no staging left, failed or unreadable dumps never published. Real PostgreSQL run: `NOT_ASSESSED` |

Major defects D2, D4, D5 fixed and verified within the stated limits; minor D6, D8, D9 fixed; D7 fixed
as an untested procedure; D10 recorded (ranker artefact), not tuned.

## Residual risk and scope

- **Stale installed copies.** The workstation's installed `sk-mysql-backup` (0.3.0) and `common.sh`
  (June) predate the 29 October repairs and this pass; `install-skills-bin --list` does not show the
  difference. See the decision in [06-next-cycle.md](06-next-cycle.md) and the [operator note](../../updates/2026-10-31-kaizen-pass-2.md).
- Files written by the earlier `sk-pg-backup` keep their old modes until an operator tightens them.
- `sk-capture` may fail to write its default output under `tcpdump`'s default privilege drop: unverified.
- The PostgreSQL restore procedure and the MySQL grants are documentation-derived and untested on a server.
- This is a repository change. It is not approval to apply a runbook to production without the
  per-host preconditions each procedure states.

## Cross-engine

No sibling checkout was read or edited. Mismatches, with exact files on this side, are in
[06-next-cycle.md](06-next-cycle.md): engine names after the upstream renames (`AGENTS.md` lines 46, 59,
175), the network skill's development-register citation, Nginx branch policy, and the shared safety
model. The research engine's `AGENTS.md` changed on disk while this pass ran; it was not touched.

## Model currentness

No model-policy change is proposed or made; this pass made no model call. The Claude runtime keeps its own
selection. A comparative quality, cost and latency review is `NOT_ASSESSED`; the 29 October dated review stands.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
