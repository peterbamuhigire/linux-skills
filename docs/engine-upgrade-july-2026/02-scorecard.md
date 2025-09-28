# Scorecard

Raw weighted total: 66/100. Capped audit total: 56/100. The cap is applied because this audit intentionally exposes the path from current state to 95+ rather than awarding production-certification scores.

| Dimension | Raw score | Points |
| --- | --- | --- |
| Richness | 14/20 | 14 |
| Robustness | 16/20 | 16 |
| World-Class Output Capability | 13/20 | 13 |
| Architecture & Discoverability | 10/15 | 10 |
| Composability & Reuse | 8/15 | 8 |
| Currency & Compliance | 5/10 | 5 |

## Richness

Raw score: 14/20.

The engine has 43 SKILL.md files, 98 reference-file hits, 0 template-file hits, and 0 example-file hits. This gives it substantial domain coverage, but the richness score is held back where references are not converted into reusable examples, current-source registers, or complete model outputs.

Top deficiencies:

- The README itself flags pending live validation on Fedora/RHEL-family hosts, which caps confidence in the two-family promise.
- Only a small subset of scripts has been migrated to the common primitives and tests.
- Compliance coverage exists but needs machine-readable benchmark mappings, rollback drills, and evidence packs.

## Robustness

Raw score: 16/20.

Robustness is supported by routers/governance files (7 read), scripts/tests where present (38 script or script-like files), and explicit anti-slop or quality gates in the repository. It is limited by missing live validation, missing negative fixtures, weak automated checks, or incomplete failure-mode coverage depending on the engine.

Top deficiencies:

- The README itself flags pending live validation on Fedora/RHEL-family hosts, which caps confidence in the two-family promise.
- Only a small subset of scripts has been migrated to the common primitives and tests.
- Compliance coverage exists but needs machine-readable benchmark mappings, rollback drills, and evidence packs.

## World-Class Output Capability

Raw score: 13/20.

The engine can produce credible specialist output in its domain, but the audit asks whether the output is indistinguishable from a top-tier firm. The current blocker is usually the same pattern: not enough finished exemplars, proof packs, rendered outputs, evaluator simulations, or audited workbooks to demonstrate repeatable excellence.

Top deficiencies:

- The README itself flags pending live validation on Fedora/RHEL-family hosts, which caps confidence in the two-family promise.
- Only a small subset of scripts has been migrated to the common primitives and tests.
- Compliance coverage exists but needs machine-readable benchmark mappings, rollback drills, and evidence packs.

## Architecture & Discoverability

Raw score: 10/15.

The structure is discoverable enough to route by filesystem and frontmatter, but there are 0 skills missing name frontmatter and 0 missing description frontmatter. Empty directories (0) and large local project/example surfaces can also reduce routing clarity.

Top deficiencies:

- The README itself flags pending live validation on Fedora/RHEL-family hosts, which caps confidence in the two-family promise.
- Only a small subset of scripts has been migrated to the common primitives and tests.
- Compliance coverage exists but needs machine-readable benchmark mappings, rollback drills, and evidence packs.

## Composability & Reuse

Raw score: 8/15.

Reuse is visible through references, templates, scripts, examples, cross-engine trigger blocks, and local governance. The gap is less about having reusable pieces and more about proving they compose into complete delivery workflows with stable contracts and acceptance criteria.

Top deficiencies:

- The README itself flags pending live validation on Fedora/RHEL-family hosts, which caps confidence in the two-family promise.
- Only a small subset of scripts has been migrated to the common primitives and tests.
- Compliance coverage exists but needs machine-readable benchmark mappings, rollback drills, and evidence packs.

## Currency & Compliance

Raw score: 5/10.

Currency and compliance depend on dated source registers, official standards, live-rate or platform refresh protocols, and release gates. The score is constrained when standards are named but not tied to dated verification, reviewer sign-off, or automated freshness checks.

Top deficiencies:

- The README itself flags pending live validation on Fedora/RHEL-family hosts, which caps confidence in the two-family promise.
- Only a small subset of scripts has been migrated to the common primitives and tests.
- Compliance coverage exists but needs machine-readable benchmark mappings, rollback drills, and evidence packs.
