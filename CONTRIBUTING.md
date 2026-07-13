# Contributing to linux-skills

Author: Peter Bamuhigire, [techguypeter.com](https://techguypeter.com), +256 784 464 178.

Changes must preserve the two-family Linux contract and the zero-debt July 2026 skill baseline. Read [the local authoring standard](docs/engine-design/skill-authoring-standard.md) before editing an active skill.

## Skill changes

1. Discover the current catalogue from the filesystem; do not copy the README list into tooling.
2. Start new entrypoints from [the skill template](templates/skill-template.md). Preserve domain knowledge when normalising an existing entrypoint.
3. Keep `## Distro support` as the first H2 in every numbered specialist skill. Use Debian/Ubuntu and RHEL-family branches, with manual commands as the baseline.
4. Add or update routing fixtures for positive and negative triggers, the nearest collision, limited capabilities, and failure behaviour.
5. If an operational change affects an `sk-*` script, update its documentation and tests in the same commit.
6. Run the safety review for new instructions, installers, dependencies, network actions, credential handling, or privilege changes.

## Required checks

```powershell
python -X utf8 scripts/validate_skills.py --baseline quality-baseline.json
python -X utf8 scripts/routing_smoke_test.py
bash scripts/tests/check-distro-matrix.sh
git diff --check
```

Run the canonical quick validator against each changed skill directory and the canonical engine scanner against `--active-root .`. Run relevant Bash syntax, unit, link, or system tests when operational content changes.

The baseline is a zero-debt assertion, not a suppression list. Do not add failure counts to it. Update the expected catalogue or fixture count only when an intentional, reviewed change alters those counts and every gate remains clean.

## Release evidence

Before committing, record the active and template counts, validator and routing results, distro test result, canonical scanner result, canonical quick-validation result, safety status, anti-slop result, and any deliberately unassessed live-system check. Review the staged diff and stage only intended files.
