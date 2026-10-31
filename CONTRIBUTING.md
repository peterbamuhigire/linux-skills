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

```bash
python3 -X utf8 scripts/validate_skills.py --baseline quality-baseline.json
python3 -X utf8 scripts/routing_smoke_test.py
bash scripts/tests/check-distro-matrix.sh
python3 -m pytest -q
bash scripts/tests/common-sh.test.sh
git diff --check
```

The validators need `PyYAML` and the tests need `pytest`; the repository has no requirements file, so install both into a virtual environment. The README's [Validation](README.md#validation) section lists every registered check with its exact command and current result, including the checks CI also runs (marketplace and file ceiling, plugin manifest, source-ingestion guardrail, hygiene gate), the opt-in container labs, and which checks need root, Podman or PowerShell.

Run the canonical quick validator against each changed skill directory (`python3 -X utf8 meta/skill-writing/scripts/quick_validate.py <skill-directory>`) and the canonical engine scanner against `--active-root .` (`engine_compliance.py` in the engineering-catalogue checkout, under `skills/sdlc-meta/skill-engine-audit/scripts/`). Run relevant Bash syntax, unit, link, or system tests when operational content changes.

When a change touches a script, a procedure or a shell source, also run the opt-in container labs described in the README (`LINUX_SKILLS_LAB=1 python3 -m pytest -rP tests/test_distro_labs.py`). They need rootless Podman and local images, and the ShellCheck zero-warning gate runs inside them. Say in the release evidence when they were not run.

The baseline is a zero-debt assertion, not a suppression list. Do not add failure counts to it. Update the expected catalogue or fixture count only when an intentional, reviewed change alters those counts and every gate remains clean.

## Release evidence

Before committing, record the active and template counts, validator and routing results, distro test result, canonical scanner result, canonical quick-validation result, safety status, anti-slop result, and any deliberately unassessed live-system check. Review the staged diff and stage only intended files.

## Security regression evidence

Run installer tests only in a disposable container/VM as root inside that
fixture; the suite installs under temporary destinations. Include `diffutils`.
Run both Debian-family and RHEL-family images and retain image identities,
exit states and failed-path results. Do not treat an image lacking dependencies
as a successful idempotency test. ShellCheck changed shell files and run
`bash -n` across shell sources before release.

Read the [current security runbook](docs/security/current-vulnerability-triage.md)
when changing security advice. Keep source access failures and superseding
verification visible. Do not claim host patch status from an upstream version,
a cached package query, or a successful repository test.

For the October 2026 cycles, see the [29 October audit](docs/kaizen/2026-10-engine-kaizen/05-final-report.md),
the [pass 2 report](docs/kaizen/2026-10-engine-kaizen-pass-2/05-final-report.md) and the
[lab wave report](docs/kaizen/2026-10-linux-lab-wave/05-final-report.md).
Historical audit scores remain historical; a requested lower initial cap does
not authorise inventing a raw score or reporting an unachieved target.

Marketplace changes must pass `python scripts/check_marketplace.py` and the manifest generator check in CI. Keep Claude and Codex skill paths aligned without duplicating skills. The package and full checkout file ceilings are 5,000; live client loading and public listing acceptance require separate evidence. See [packaging](docs/marketplace.md).
