# Frozen baseline — 29 October 2026

Snapshot: `2ce755a7731e3061296de68747d8d36fea4286a9`. This is the immutable
pre-task Git tree, independently archived for measurement. The supplemental
Portfolio baseline was frozen after earlier carried-in experiments, before
additional experiments selected below. It must not be described as a baseline
record written before the original task began.

Scores are evidence-based reviewer judgements out of 100, equally weighted.
No measured test pass ratio is being relabelled as a production quality score.

| Standard dimension | Raw | Named evidence and one-line deficiency |
|---|---:|---|
| Doctrine | 80 | AGENTS, Kaizen and safety contracts are explicit; implementation still violated temporary-file trust |
| Taxonomy and routing | 60 | 48 skills, 30 fixtures; P@1 25/30 and zero complete skill fixture sets |
| Skill depth | 65 | 48 worked examples; short 502 example skips causal proof and rollback |
| Applied proof | 35 | Shared fixtures exist, but no retained actual MySQL restore or whole-stack dual-family proof |
| Standards currency | 35 | Currentness rule exists; ten overdue rows in the bounded source-record scan |
| Output readiness | 45 | Complete contracts, but unsafe backup failure and misleading audit paths prevent execution readiness |
| Accessibility and inclusion | 65 | Text/manual routes and clear flags; quiet failure output and terminology still need practitioner verification |
| Production and handoff | 35 | Recovery handoff exists; actual restore, service rollback and recovery-window proof missing |
| Hygiene | 55 | Zero-debt entrypoint validation; eight dangling local links and ten duplicate References sections in broader scan |
| Safety and integrity | 30 | Authority gates present; cleanup/atomic-write/backup defects are release blockers regardless of score |

Raw mean: **56.5/100**. Standard cap: `min(56.5,65) = 56.5`.
Peter's stricter original publication cap: **`min(56.5,45) = 45/100`**.
Improvement target: **95/100 raw**. The published audit ceiling is not an
instruction to inflate raw results or conceal blockers.

## Frozen measured inputs

- Registered validator: 48 active, one template, 48 compliant; exit 0.
- Routing validator: 30/30 top3 contract passes; exit 0. Expected target
  precision@1 **25/30 = 0.833333**, expected target recall@3 **30/30 = 1**.
- Six owned negative fixtures: expected P@1 5/6, P@3 6/6; all six forbidden
  neighbours excluded from top3.
- Positive fixtures: 11; owned negatives: six; **0/48** skills satisfy at least
  three positives plus two owned negatives. This is coverage, not 48 failures.
- Distro matrix: 41 pass/0 fail; exit 0. The shallow gate itself has false negatives.
- Shell syntax: 35 files/0 failures, `bash -n`, exit 0.
- Worked examples: 48/48; 153 paragraph blocks, 331 nonblank lines; medians
  two paragraphs and 4.5 nonblank lines. These are depth proxies, not quality proof.
- Duplicate canonical H2s: ten skills, all duplicate References headings.
- Bounded inline local-link scan: zero machine-specific absolute targets,
  eight dangling targets. Reference-style/external links NOT_ASSESSED.
- Bounded `review by YYYY-MM-DD` source-row scan: ten expired rows at
  2026-10-29; CVE due dates excluded. Unstructured dates are NOT_ASSESSED.
- Source-ingestion guard: zero findings, exit 0; recovery fixture validator:
  five synthetic cases pass, exit 0. Neither proves a real restore.

Exact machine-readable detail is retained in [metrics-baseline.json](metrics-baseline.json).
The baseline counts are never replaced by final counts. WSL absence from the
older audit is not a failure of native Linux checks in this cycle.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.

## Arithmetic correction — final review, 29 October 2026

The ten frozen row scores sum to 505, so the raw mean is **50.5**, not 56.5 as originally transcribed above. The row scores and original statement are preserved for auditability. Correct Standard cap is 50.5; the requested published cap remains 45. Final comparisons use 50.5. This is an arithmetic correction, not a rescore.

The original frozen machine-readable measurement is preserved byte-for-byte in [metrics-baseline-legacy.json](metrics-baseline-legacy.json). The refined [metrics-baseline.json](metrics-baseline.json) reruns the improved parser on the same pristine commit and carries provenance: seven missing paths and ten missing anchors replace the old aggregate eight-target classification. Final comparisons use the same refined parser on both trees.
