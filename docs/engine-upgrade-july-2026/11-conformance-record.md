# July 2026 Conformance Record

Author: Peter Bamuhigire, [techguypeter.com](https://techguypeter.com), +256 784 464 178.

Date: 2026-07-13
Benchmark: canonical `skills-web-dev` skill-writing, composition, engine-audit, anti-slop, and slop-audit contracts.

## Before state

Filesystem discovery found 43 active `SKILL.md` entrypoints and no templates. The canonical read-only scanner reported 0 fully compliant skills and 277 findings:

| Finding | Count |
|---|---:|
| Capability contract | 29 |
| Decision rules | 43 |
| Degraded mode | 26 |
| Five anti-patterns | 42 |
| Invalid frontmatter YAML | 4 |
| Identity mismatch caused by invalid YAML | 4 |
| Input contract | 42 |
| Entrypoint over 500 lines | 1 |
| Portable metadata | 43 |
| Trigger description | 43 |

The principal causes were long non-trigger descriptions, YAML punctuation errors, absent portable metadata, prose-only inputs and outputs, missing decision/degraded/capability contracts, shallow anti-pattern lists, and no executable routing or structural regression gate.

## Implemented cohorts

- Categories 01-05: provisioning, access, networking, web/mail, services, and virtualisation.
- Categories 06-10: storage, security, observability, recovery, Bash, and repository automation.
- Categories 11-15: databases, containers, backups, performance/kernel, compliance, and auditing.
- Shared layer: `linux-sysadmin`, the two `meta` skills, authoring standard, template, validator, zero-debt baseline, routing fixtures, CI, and maintainer documentation.

Every active skill now has neighbour-aware routing, explicit input/output/evidence contracts, an authority boundary, degraded behaviour, domain decisions, stop and recovery behaviour, five corrected anti-patterns, a worked example, and directly linked references. Numbered specialists retain their two-family distro matrix as the first H2.

## Final evidence

The release gate records the exact final output of:

- `scripts/validate_skills.py --baseline quality-baseline.json`
- `scripts/routing_smoke_test.py`
- canonical `engine_compliance.py --active-root . --details`
- canonical `quick_validate.py` for all 43 skill directories
- `scripts/tests/check-distro-matrix.sh`
- applicable repository shell/unit checks and `git diff --check`

The machine baseline requires 43 active skills, one template, no structural findings, and 25/25 routing fixtures at top-three precision 1.0. Any future finding fails CI; the baseline contains no waiver counts.

| Gate | Final result |
|---|---|
| Local validator | 43/43 compliant; failure counts `{}` |
| Canonical engine scanner | 43/43 compliant; failure counts empty |
| Canonical quick validator | 43/43 skill directories passed |
| Routing smoke test | 25/25 fixtures; top-three precision 1.000 |
| Entrypoint limit | Maximum 453 lines |
| Distro-matrix invariant | 40 passed, 0 failed; routing hub skipped by design |
| Bash syntax | 25/25 repository shell files passed `bash -n` |
| Safety review | `Safe`; hazard hits were protective examples or explicit anti-patterns, with no secret signature |
| Anti-slop audit | Grade A; zero banned-term additions and no evidence-free filler found in the changed contracts |

The Linux-only `common-sh.test.sh` was attempted under Git Bash. Its filesystem-mode and distro-detection checks are not assessable on this Windows host; WSL, Docker, and LXD are unavailable. No Bash implementation file changed in this conformance upgrade, and the environment-independent distro-matrix and syntax gates passed.

## Outside conformance

Live Fedora/RHEL-family execution remains unassessed, as documented in `docs/multi-distro/plan.md`. Expanding executable `sk-*` coverage and adding more observed incident examples are capability work, not conformance debt.
