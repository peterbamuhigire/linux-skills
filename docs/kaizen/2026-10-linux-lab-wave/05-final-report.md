# Lab wave final report — 31 October 2026

Linux Skills, special wave on top of pass 2: rootless Podman labs on Debian 12, Fedora 44 and MySQL 8.4 for the
standing P1. **The 95/100 raw target is not achieved.** The labs turned most of the pass-2 `NOT_ASSESSED` items into
measured results, and found one critical and one major defect that fixtures had hidden. Both are fixed and verified in a
container. No enterprise RHEL, Ubuntu, Debian 13 or production host was run, and no host was changed or certified.

Branches: started on `main` at `74e2b6d`; work on `kaizen/2026-10-linux-wave` (ten items in eleven code and test
commits, one baseline commit and the evidence commits). Nothing was pushed, tagged or merged. The checkout is returned to
`main` at the end of the run.

## Scores

Ten equally weighted Standard dimensions; reviewer judgements with the named evidence, not percentages of anything. The
wave baseline is below pass 2's final because the labs found defects pass 2 could not see; it was measured before any fix.

| Dimension | 29 Oct final | Pass 2 final | Wave baseline | Wave final | Evidence and remaining deficiency |
|---|---:|---:|---:|---:|---|
| Doctrine | 85 | 85 | 85 | 85 | Unchanged; conformance of the 22 unexercised scripts to the shared contract is still unmeasured |
| Taxonomy and routing | 75 | 74 | 74 | 76 | 109 fixtures, P@1 0.881 (was 0.863), P@3 1.000, 17 of 48 skills at 3+2 (was 14); ranker artefacts untouched |
| Skill depth | 75 | 78 | 76 | 80 | Debian automatic updates, RHEL SSH unit and MySQL account page now match what ran; Ubuntu forms remain unrun |
| Applied proof | 65 | 68 | 68 | 78 | Nine repeatable lab tests on three images with fail-before evidence for each fix; no enterprise RHEL, no cloud image, 22 scripts unexercised |
| Standards currency | 65 | 72 | 72 | 72 | No source row changed; lab observations recorded in `currency.md`, not as register rows |
| Output readiness | 80 | 78 | 74 | 80 | Documented SSH and automatic-update procedures now produce their stated effect on both families in the lab; `sk-pg-backup` output verified; Ubuntu unrun |
| Accessibility and inclusion | 65 | 65 | 65 | 65 | Plain text, explicit unknown states; no practitioner accessibility test |
| Production and handoff | 75 | 77 | 77 | 80 | PostgreSQL restore procedure run, timed and reconciled; operator note; installed copies on the workstation stay stale |
| Hygiene | 75 | 82 | 82 | 84 | ShellCheck zero-warning gate, service-unit parity test, `--quiet`; external links not fetched |
| Safety and integrity | 80 | 77 | 70 | 79 | W1 and W2 fixed and verified; die banner corrected; 22 scripts without failure fixtures; installed copies stale |

Raw mean: 29 Oct final **74.0**; pass-2 final **75.6**; wave baseline **74.3** (743/10); wave final **77.9** (779/10).
Published score `min(raw, 65)`: **65.0** at all four points. The wave moved the raw mean 3.6 points above its own fresh
baseline and 2.3 above pass 2, and the 17.1-point gap to 95 is not hidden by the cap.

## Measured inputs, baseline against final

Both columns come from commands run in this wave ([metrics-baseline.json](metrics-baseline.json),
[metrics-final.json](metrics-final.json), [registered-gates-final.log](samples/registered-gates-final.log)).

| Measure | Baseline | Final |
|---|---|---|
| Registered gates | 8 of 8 exit 0 | 10 of 10 exit 0 (adds the full suite and the quiet metrics run) |
| Full suite (real pytest) | 102 passed, 1 skipped | 119 passed, 9 skipped (the skips are the opt-in labs, run separately: 7 + 2 passed) |
| Routing P@1 / P@3 | 82/95 (0.863) / 95/95 | 96/109 (0.881) / 109/109 |
| Owned negatives (forbidden neighbour absent at 3) | 29 of 29 | 34 of 34 |
| Skills at 3 positives and 2 owned negatives | 14 of 48 | 17 of 48 |
| Worked-example depth | 48/48; 153 paragraphs; medians 2 and 4.5 | unchanged |
| Machine-specific links, dangling paths, dangling anchors | 0, 0, 0 | 0, 0, 0 |
| Duplicate contract headings, expired source rows | 0, 0 of 10 | 0, 0 of 10 |
| ShellCheck warnings (0.9.0 and 0.11.0) | 28 | 0 |
| Unpaired Debian-only service units in matrices | 8 uses in 7 skills | 0 |

## Lab results

| What was verified for real | Image | Result |
|---|---|---|
| SSH drop-in beside a cloud-init `PasswordAuthentication yes` file, blocks run as written, real logins | `debian:bookworm` (OpenSSH 9.2), `fedora:44` (OpenSSH 10.2), real systemd | Passes in both after LW-02. `00-linux-skills-ssh.conf` wins; the old `99-hardening.conf` loses (`sshd -T` and a real password login both show it); a syntax error stops at `sshd -t` with no reload; Fedora's plain reload with a bad file stops `sshd`, Debian's refuses it |
| `sk-pg-backup` on a real PostgreSQL | Debian 12 / PostgreSQL 15.19; Fedora 44 / PostgreSQL 18.6 | Modes 0700 and 0600, globals with a SCRAM hash, `pg_restore --list` gate, repeat, retention (only its own files), seven controlled failures (database stopped, missing database, unwritable path, write failure, truncated dump, untrusted config, bad retention), all without a published partial file |
| PostgreSQL "Verify a logical backup", step by step on a second instance | same | Restore in about 0.3 s; eleven reconciliation figures equal the dump-time figures; documented harmless error appears; second `--create` and truncated dump fail; `-j` from standard input refused |
| `sk-mysql-backup`: backup, restore to a second instance, repeat, GPG and rclone failures | `mysql:8.4` (8.4.13) | Passes (existing lab, 52 s) |
| The pass-2 least-privilege backup account | `mysql:8.4` | The page's `CREATE USER` and `GRANT` work; every schema archived; restore reconciles rows, triggers, routines, events, views; eight write attempts refused; both narrowing traps reproduced; `PROCESS` found optional |
| Debian automatic security updates, documented block and verify command | `debian:bookworm` | Fixed: the dry run lists the pending security upgrade. The previous text printed `No packages found` |
| dnf5 automatic updates guidance | `fedora:44` (dnf5 5.4.6.0) | Holds as written (units, alias, preset, journal pattern) |
| ShellCheck 0.9.0 and 0.11.0 over 41 shell sources | both | 0 findings at warning level; the 28 baseline warnings were all false positives |

## Kept changes

All ten kept; none reverted. Detail in [03-experiment-log.md](03-experiment-log.md), checks in
[04-validation-record.md](04-validation-record.md).

| Commit | Item | Retained change |
|---|---|---|
| `131abe1` | LW-00 | Frozen baseline, observation evidence, backlog |
| `2293b73`, `cf670be` | LW-03 | `tests/test_distro_labs.py`, `tests/lab_support.py`, drivers in `tests/labs/`; PostgreSQL restore page records the lab result |
| `af0e9e0` | LW-09 | `kaizen_metrics.py --quiet` |
| `a31dc52` | LW-06 | `die` reports its own cause; no wrong line and command in the failure banner |
| `fe5f9f9` | LW-04 | Least-privilege MySQL account lab test; page corrected on `PROCESS` |
| `92bafbd` | LW-01 | Debian automatic updates: `Origins-Pattern` with `#clear`, Ubuntu form scoped, verify step that keeps the origins line; static test and lab driver |
| `dad557e` | LW-02 | SSH unit named `sshd`; unit row in two matrices; `sshd -t &&` before every reload after an edit; two static tests |
| `ae84c01` | LW-08 | Service-unit parity test; five matrix rows |
| `85a96dd` | LW-05 | `sk-pg-backup` runs client calls from `/`; usage text says what a failed run leaves |
| `4dabff3` | LW-07 | ShellCheck gate in both families; 25 reasoned inline directives |
| `16e45f2` | LW-10 | Fourteen routing fixtures for three skills; fixture count pinned |

The evidence commits (these files, `metrics-final.json`, samples) follow this ledger; find them with
`git log --oneline -- docs/kaizen/2026-10-linux-lab-wave/05-final-report.md`.

## Critical and major defects

| ID | Status |
|---|---|
| W1 (critical) Debian automatic updates match no security archive | Fixed and verified: documented Debian block, dry run lists the pending upgrade (lab 1 passed, 124 s); driver fails against the previous text. Ubuntu: `NOT_ASSESSED` |
| W2 (major) `systemctl reload ssh` fails on the RHEL family, in apply and rollback | Fixed and verified on Fedora 44: the blocks exit 0 as written. Enterprise RHEL: `NOT_ASSESSED` |

Minor W3 (MySQL `PROCESS` note), W4 (Debian client warning), W5 (die banner), W6 (usage wording) fixed; the ShellCheck
warnings were false positives and are now annotated.

## Residual risk and scope

- **Stale installed copies** on the workstation, one change older than before; see the [operator note](operator-note.md).
- Containers are not machines: no real boot, no enforcing SELinux, no firewall, a file-size limit for a full disk,
  kilobytes of data. Fedora and Debian 12 are two members of two families.
- The Ubuntu `Allowed-Origins` form in the rewritten procedures was kept from the earlier text and is marked as not run.
- 22 `sk-*` scripts were still never run. This is a repository change; it is not approval to apply a runbook to
  production without each procedure's own preconditions.

## Cross-engine

No sibling checkout was edited. A read-only search found the same two faults in the engineering catalogue (four
Ubuntu-pattern sites, four `reload ssh` sites); exact files in [06-next-cycle.md](06-next-cycle.md).

## Model currentness

No model-policy change is proposed or made, and the wave made no model call. Comparative quality, cost and latency review
is `NOT_ASSESSED`; the 29 October dated review stands.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
