# Linux Skills Authoring Standard

Author: Peter Bamuhigire, [techguypeter.com](https://techguypeter.com), +256 784 464 178.

This repository applies the July 2026 portable skill contract to all active `SKILL.md` files. The canonical external `skills-web-dev` engine is the benchmark; this document is the small local contract and does not copy that engine.

## Active catalogue

Active skills are discovered from the filesystem as files named `SKILL.md`, excluding generated, virtual-environment, and template directories. `templates/skill-template.md` is not active. The current contract covers 43 active skills: 40 numbered specialists, `linux-sysadmin`, and two `meta` skills.

## Entrypoint contract

Every active skill must meet these gates:

- YAML uses only `name`, `description`, `license`, `allowed-tools`, and `metadata`; `name` matches the directory.
- `description` is a single line of at most 350 characters, begins `Use when`, and distinguishes the nearest neighbour.
- Metadata records Peter Bamuhigire's attribution, `portable: true`, and compatibility with Claude Code and Codex.
- Specialist skills keep `## Distro support` as the first H2 and retain both Debian/Ubuntu and RHEL-family guidance.
- Required contracts are non-empty: positive and negative triggers, inputs, workflow, quality, anti-patterns, outputs, evidence, capabilities, degraded mode, decisions, worked example, and references.
- Inputs name the artefact, source, requirement, and absent-input behaviour. Outputs and evidence name an observable acceptance condition.
- Workflows are ordered and include a decision, stop condition, recovery behaviour, and verification.
- Audit, analysis, critique, review, scanning, and planning default to read-only. Mutation, destructive action, production access, publishing, spending, and certification claims require explicit authority.
- A degraded result is narrow and qualified. Missing execution, network, access, evidence, rendering, or tooling is `not assessed`, never a pass.
- Decision tables name the choice, action, and wrong-choice failure or risk. Anti-patterns contain at least five concrete error-and-fix pairs.
- `SKILL.md` is at most 500 lines. Extracted references are directly linked and point back to their parent skill.

## Authoring and release procedure

1. Start from [the local template](../../templates/skill-template.md), then preserve the target skill's domain content and voice.
2. Compare neighbouring descriptions and add positive, negative, collision, limited-capability, and failure-path fixtures.
3. Keep manual commands authoritative. When `sk-*` behaviour changes, update the script, its documentation, and tests in the same change.
4. Run the local validator and routing smoke test. Run the canonical quick validator for each changed skill directory and the canonical engine scanner for the complete repository.
5. Run the distro-matrix test, applicable shell/unit/link checks, `git diff --check`, and the skill safety and anti-slop release reviews.
6. Do not update `quality-baseline.json` to excuse a finding. It represents zero debt and changes only when the intentional active or template count changes with complete evidence.

## Commands

```powershell
python -X utf8 scripts/validate_skills.py --baseline quality-baseline.json
python -X utf8 scripts/routing_smoke_test.py
python -X utf8 C:\Users\Peter\.claude\skills\skills\sdlc-meta\skill-engine-audit\scripts\engine_compliance.py --root . --active-root . --details
bash scripts/tests/check-distro-matrix.sh
```
