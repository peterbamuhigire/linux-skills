# Frozen baseline — 31 October 2026

Snapshot: `f904f7bf8ce2e9c0ca12d838d31885af5af76d61` (`main`), clean tree. Measured
before any change in this pass. This file is not edited after it is committed; final scores
are in `05-final-report.md`.

Scores are evidence-based reviewer judgements out of 100, equally weighted, on the ten Standard
dimensions. The 29 October final column is shown for comparison; a lower pass-2 baseline is the
result of defects found by this pass's fresh observation, not of any change to the engine since.

| Standard dimension | 29 Oct final | Pass 2 baseline | Named evidence and one-line deficiency |
|---|---:|---:|---|
| Doctrine | 85 | 85 | `AGENTS.md`, safety contract and Kaizen skill are explicit and unchanged; applied unevenly (D1 contradicts the engine's own checklist) |
| Taxonomy and routing | 75 | 72 | 48 skills, 80 fixtures, P@1 67/80, P@3 80/80; 37 skills lack 3+2 fixtures; ranker puts the Netmiko skill first for an `sshd` prompt (D10) |
| Skill depth | 75 | 72 | Contradictory SSH naming across five procedures (D1); no dnf5 unit guidance (D2); no PostgreSQL restore verification (D7) |
| Applied proof | 65 | 60 | MySQL restore proven once on 29 October and carried forward; `sk-pg-backup` has no fixture at all; no new lab possible this pass |
| Standards currency | 65 | 65 | Dated matrix from 29 October is inside its 5 November review; 10 historical source rows still expired |
| Output readiness | 80 | 70 | `sk-pg-backup` output is world-readable and can leave partial dumps (D3); SSH runbook leaves password login enabled on cloud images (D1) |
| Accessibility and inclusion | 65 | 65 | Plain-text output and explicit unknown states; no practitioner accessibility test |
| Production and handoff | 75 | 72 | MySQL restore specified and timed; PostgreSQL restore is one sentence (D7); backup-account privileges unstated (D8) |
| Hygiene | 75 | 75 | 5 dangling local paths, 10 dangling anchors, 10 duplicate References headings, 10 expired source rows (same parser, same counts as 29 October) |
| Safety and integrity | 80 | 65 | Four open safety findings: D1, D3, D4, D5; D1 and D3 are release blockers whatever the score |

Raw mean: **70.1** (701 / 10). Published score `min(raw, 65)` = **65.0**. Cap calculation:
`min(70.1, 65) = 65`. 29 October final for comparison: raw 74.0, capped 65.0. Target for the plan
remains 95/100 raw; it is not an achieved score.

## Frozen measured inputs

Source: `metrics-baseline.json` (same parser as the 29 October baseline, run 2026-10-31).

- Active skills 48 (44 specialists, the hub, three meta skills); one template excluded.
- Registered validator: 48 compliant, exit 0. Routing: 80/80 valid, P@1 67/80 (0.8375), P@3 80/80.
- Fixture kinds: positive 44, negative 23 (owned negatives), collision 5, failure-path 5,
  limited-capability 3. Skills meeting 3 positive + 2 owned negative: **11 of 48**.
- Distro matrix: 41 pass, 0 fail.
- Worked examples: 48 of 48; 153 paragraph blocks, 331 non-blank lines; medians 2 and 4.5.
- Hygiene: machine-specific absolute inline links 0; dangling local paths 5; dangling local
  anchors 10; skills with duplicate canonical headings 10; expired structured source rows 10;
  external link reachability `NOT_ASSESSED` (288 external links not fetched).
- Scripts: 26 distinct `sk-*` files by `git ls-files` (27 manifest rows; `sk-mysql-backup` is listed
  under two skills). Scripts with a failure or rollback fixture: 2 (`sk-mysql-backup` lab,
  `sk-audit` SSH fixture); `sk-pg-backup` none.
- Python tests: 62 `unittest` tests pass; 8 more pass through a stand-in runner; 2 parametrised
  cases and the pytest-only lab are `NOT_ASSESSED` (no pytest on this host).
- Dangling cross-engine references: the development source-register path cited in
  `16-network-equipment/network-config-validation/SKILL.md` resolved on 29 October; not re-checked
  here (no sibling checkout is read in this pass).

## Blockers

D1 and D3 are safety and integrity failures in operator-facing output. They are in the backlog
as P0 and must be fixed and verified, or escalated, before this pass can report done.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
