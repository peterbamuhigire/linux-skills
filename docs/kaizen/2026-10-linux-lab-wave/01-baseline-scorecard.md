# Baseline scorecard — Linux lab wave (frozen 31 October 2026, before any change)

Frozen at `main` `74e2b6d` after the observation labs in [00-scope-and-evidence.md](00-scope-and-evidence.md)
and before the first edit to a skill, script or procedure. The only working-tree change at this point is
lab plumbing in `tests/test_mysql_backup.py` (container name prefix, repository-copy override and a new
opt-in test), which is uncommitted and does not alter any measure below.

Ten equally weighted Standard dimensions. These are reviewer judgements with the named evidence, not
percentages of anything. The baseline sits below the pass-2 final because the labs found defects that
fixture testing could not (W1 to W6); it is measured before any fix, as pass 2 did.

| Dimension | Pass-2 final | Wave baseline | Evidence and deficiency |
|---|---:|---:|---|
| Doctrine | 85 | 85 | Unchanged. The checklist and runbooks agree on SSH precedence; the unit name and the Debian origin syntax are procedure faults, not doctrine faults |
| Taxonomy and routing | 74 | 74 | 95 fixtures, P@1 0.863, P@3 1.000, 14 of 48 skills at 3+2 (measured now: `routing_smoke_test.py`) |
| Skill depth | 78 | 76 | Two procedures wrong on one family each (W1 Debian origins, W2 RHEL unit); the MySQL account page over-grants and omits an exit-0 behaviour (W3) |
| Applied proof | 68 | 68 | The repository still holds stub fixtures plus one opt-in MySQL lab. The lab results in this wave are observations until the drivers are committed as repeatable tests |
| Standards currency | 72 | 72 | Unchanged; the Debian suite names and the dnf5 units were re-read in a lab but no source row was updated before the baseline |
| Output readiness | 78 | 74 | A documented Debian automatic-updates setup yields no security updates (W1); a documented RHEL SSH apply and rollback fail at the reload (W2) |
| Accessibility and inclusion | 65 | 65 | Plain text, explicit unknown states; no practitioner accessibility test |
| Production and handoff | 77 | 77 | Operator note, PostgreSQL restore procedure (now seen to run, not yet recorded in the page), backup-account spec; installed copies on the workstation remain stale |
| Hygiene | 82 | 82 | Paths 0, anchors 0, duplicate headings 0, expired rows 0 (measured now, `metrics-baseline.json`); CI ratchet in place; external links not fetched |
| Safety and integrity | 77 | 70 | Critical W1 (security control silently inert on Debian); W2 leaves a RHEL rollback unapplied; 22 scripts still without failure fixtures; installed copies stale |

Raw mean: pass-2 final **75.6**; wave baseline **74.3** (743/10). Published score `min(raw, 65)`: **65.0** at both points.

## Measured inputs (fresh, from commands run at `74e2b6d`)

| Measure | Value | Command or source |
|---|---|---|
| Validator results | 8 of 8 registered gates exit 0 | [samples/registered-gates-baseline.log](samples/registered-gates-baseline.log) |
| Full suite (real pytest) | 102 passed, 1 skipped, 22 subtests | `python -m pytest -p no:cacheprovider` from the shared venv |
| Routing precision@1 / @3 | 82/95 (0.863) / 95/95 (1.000) | `scripts/routing_smoke_test.py` |
| Owned negatives | 29 fixtures; expected target at 1: 25/29; forbidden neighbour absent at 3: 29/29 | `metrics-baseline.json` |
| Fixture coverage (3 positives + 2 owned negatives) | 14 of 48 skills | `metrics-baseline.json` |
| Worked-example depth | 48/48 skills; 153 paragraphs, 331 non-blank lines; medians 2 and 4.5 | `metrics-baseline.json` |
| Broken or machine-specific links | 0 absolute machine paths, 0 dangling paths, 0 dangling anchors; 303 external links not fetched (`NOT_ASSESSED`) | `metrics-baseline.json` |
| Dangling cross-engine references | none introduced; the catalogue-name mismatches carried from pass 2 are unchanged | pass-2 `06-next-cycle.md` |
| Expired source records | 0 of 10 dated records | `metrics-baseline.json` |
| Lab results on unchanged scripts | see the table in [00-scope-and-evidence.md](00-scope-and-evidence.md) | `samples/lab-*` |
| ShellCheck 0.9.0, 36 sources | 0 errors, 28 warnings (all triaged false positives), 67 notes | [samples/lab-shellcheck-0.9.0-summary-baseline.log](samples/lab-shellcheck-0.9.0-summary-baseline.log) |

Any safety, legal, financial, privacy or release failure is a blocker whatever the score. W1 is such a failure
for the Debian automatic-updates procedure and is the first item in the backlog.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
