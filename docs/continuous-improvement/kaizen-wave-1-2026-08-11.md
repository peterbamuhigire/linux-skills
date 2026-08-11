# Linux-skills Kaizen Wave 1 report

Assessment date: 2026-08-11
Repository: `C:\wamp64\www\linux-skills`
Scope: assigned Wave 1 P0 repairs and the smallest safe P1 evidence improvement
Owner: Peter Bamuhigire / repository maintainer

## Executive result

The P0 portability and platform-evidence repair is implemented. The repository
now has runner-neutral entry-point language in its canonical policy and hub,
an explicit platform matrix, and a disposable `ubuntu-24.04` CI route for the
Bash suites. A fixture-only dry-run/rollback validator covers package, service,
firewall, storage, and recovery planning without executing a host action.

The Windows host still cannot supply Linux system evidence. The Bash suites and
LXD harness remain `NOT ASSESSED`; they are not reported as passes. The Wave 1
report score is therefore held at the diagnostic raw baseline of `62.0`
([initial assessment](../../../KAIZEN-INITIAL-ASSESSMENT.md)), with the
exercise publication cap applied as `min(62.0, 55.0) = 55.0`. The permanent
Linux engine cap of `65` remains unchanged in the repository policy
([engine audit rule](../../linux-sysadmin/SKILL.md#engine-audits)). The target
of `95` is not achieved.

No required file was unavailable. The assignment prompt, initial assessment,
standards register, repository controllers, and all five required
skills-web-dev skill files were available and read before editing.

## Baseline inventory, score, and maturity

The frozen portfolio assessment records `44` active Linux skills plus one
template, `44/44` active contracts, `25/25` routing fixtures, zero source
guardrail findings, raw diagnostic score `62.0`, exercise-published score
`55.0`, and maturity `L2 — repeatable workflow with platform execution
unassessed` ([initial assessment](../../../KAIZEN-INITIAL-ASSESSMENT.md)).

The pre-edit working tree was clean and aligned with its remote branch:
`main...origin/main` ([baseline status command evidence](#baseline-and-change-control)).
The baseline assessment identifies two related causes: Claude-centric setup/path
language in canonical surfaces and no demonstrated disposable Linux execution
route for high-risk operational suites.

### Baseline evidence boundary

| Evidence class | Baseline state | Interpretation |
| --- | --- | --- |
| Structural | Contracts, routes, and source guardrail passed | Useful repository evidence; not proof of Linux runtime behaviour |
| Behavioural | No representative dry-run/rollback fixture | Outcome evidence gap |
| Render | `NOT ASSESSED` | No visual artefact is in scope |
| System | Bash and LXD execution `NOT ASSESSED` on Windows | No package, service, firewall, storage, or recovery operation was run |
| Production | `NOT ASSESSED` | No target host or operator outcome was supplied |

## Files changed

- [`AGENTS.md`](../../AGENTS.md): made canonical policy runner-neutral, added
  portable entry points, and linked the platform evidence standard.
- [`README.md`](../../README.md): repaired discovery/setup wording, corrected a
  broken Digital Research sentence, exposed the fixture command, and linked the
  platform matrix.
- [`linux-sysadmin/SKILL.md`](../../linux-sysadmin/SKILL.md): replaced the
  fixed Claude setup path in the canonical hub with a resolved `SKILLS_ROOT`
  flow and an explicitly optional Claude adapter.
- [`docs/engine-design/spec.md`](../../docs/engine-design/spec.md): changed the
  runtime and installation contract from Claude-specific assumptions to
  capability/runner-neutral language.
- [`scripts/setup-claude-code.sh`](../../scripts/setup-claude-code.sh): retained
  it as a clearly labelled Claude adapter and made its checkout root overridable
  through `LINUX_SKILLS_ROOT`.
- [`docs/continuous-improvement/platform-test-matrix-2026-08.md`](platform-test-matrix-2026-08.md): added the evidence-class and platform matrix.
- [`.github/workflows/bash-suites.yml`](../../.github/workflows/bash-suites.yml): added the minor-pinned `ubuntu-24.04` disposable CI route.
- [`tests/fixtures/safe-operation-evidence.json`](../../tests/fixtures/safe-operation-evidence.json): added fictional, fixture-only scenario data.
- [`scripts/validate_safe_operation_fixture.py`](../../scripts/validate_safe_operation_fixture.py): added a read-only validator that never executes fixture text.
- [`tests/test_safe_operation_fixture.py`](../../tests/test_safe_operation_fixture.py): added deterministic positive, mutation-rejection, and unassessed-status tests.

No sibling repository or workspace-level report was modified.

## Improvement register

### P0-09 — portable entry points and explicit platform evidence

| Field | Wave 1 record |
| --- | --- |
| Gap | Portability and system-evidence dimensions: canonical policy and setup guidance centred Claude discovery and a fixed `~/.claude/skills` path; Bash/system suites had no repository-local matrix or disposable CI route. Baseline system execution was `NOT ASSESSED` ([assessment gap](../../../KAIZEN-INITIAL-ASSESSMENT.md)). |
| Root cause | Routing/documentation and proof failure. A Claude adapter was treated as the default entry point, while the available Windows host could not execute `/bin/bash` or LXD. |
| Exact change | Updated `AGENTS.md`, `README.md`, `linux-sysadmin/SKILL.md`, `docs/engine-design/spec.md`, and the optional `scripts/setup-claude-code.sh`; added `docs/continuous-improvement/platform-test-matrix-2026-08.md` and `.github/workflows/bash-suites.yml`. |
| Hypothesis | A fresh agent can start from `AGENTS.md` and `linux-sysadmin/SKILL.md` without assuming Claude or a fixed home path, while Linux suites have a reproducible disposable route. |
| Owner | Peter Bamuhigire / Linux engine maintainer |
| Measure | Structural gates remain `44/44`, `25/25`, and zero source findings; the matrix names every unavailable check; workflow markers include `ubuntu-24.04` and all required Bash suites. |
| Risk | The optional Claude bootstrap still has system, network, credential, and privileged-write side effects. Runner labels and action references can change outside this repository. A generic setup path could also be misunderstood as authority to mutate a host. |
| Rollback | Restore the pre-change text in the five existing files and remove the new matrix/workflow files, preserving any unrelated concurrent edits. The adapter path change is isolated to `scripts/setup-claude-code.sh`. |
| Acceptance evidence | Local structural validators, routing, source guardrail, YAML parse, and diff checks passed. The CI route exists but has no retained run URL in this Wave 1 execution. Bash/system checks remain `NOT ASSESSED`. |
| Standardisation | `AGENTS.md` and `README.md` point users to the matrix; the workflow is the repeatable release route; `NOT ASSESSED` is required when the platform is unavailable. |
| Re-audit date | 2026-08-18 |

### P1-01 — fixture-only dry-run and rollback evidence

| Field | Wave 1 record |
| --- | --- |
| Gap | Applied-proof dimension: there was no deterministic representative evidence for safe planning and rollback boundaries across package, service, firewall, storage, and recovery work. |
| Root cause | Outcome-proof failure. Static contracts described safety controls, but no bounded fixture checked that a dry-run remained non-mutating and that rollback fields were complete. |
| Exact change | Added the fictional fixture, `validate_safe_operation_fixture.py`, three unit tests, README command, and a CI step. The validator rejects host mutation, executable command fields, unsafe host markers, missing rollback fields, and any evidence status that would turn system or production checks into a pass. |
| Hypothesis | A small, labelled fixture will catch regressions in dry-run/rollback evidence without pretending to validate a real Linux host. |
| Owner | Peter Bamuhigire / Linux engine maintainer |
| Measure | The validator reports five labelled scenarios as safe fixture evidence; `unittest` reports three tests passing. Fixture status keeps system and production evidence `NOT ASSESSED` ([fixture](../../tests/fixtures/safe-operation-evidence.json)). |
| Risk | A fixture can be mistaken for a real service, firewall, storage, package, or restore test. It deliberately does not prove command correctness, distro behaviour, rollback execution, or data recovery. |
| Rollback | Remove the fixture, validator, unit test, README/CI references, and the related report claims as one bounded change. No host state needs recovery because no host action is performed. |
| Acceptance evidence | `python -X utf8 scripts/validate_safe_operation_fixture.py ...` passed; all three deterministic tests passed; the validator output explicitly states that no host action was executed. |
| Standardisation | Keep the fixture under `tests/fixtures/`, run it in the disposable CI route, and preserve the evidence-class vocabulary in the platform matrix. |
| Re-audit date | 2026-08-25 |

## Before/after measures

| Measure | Before | After | Evidence and limit |
| --- | --- | --- | --- |
| Active catalogue | `44` plus one template | Unchanged | Contract validator output and [quality baseline](../../quality-baseline.json); no catalogue change was needed |
| Contract coverage | `44/44` | `44/44` | `scripts/validate_skills.py --baseline quality-baseline.json`, exit `0` |
| Routing coverage | `25/25`, precision `1.000` | `25/25`, precision `1.000` | `scripts/routing_smoke_test.py`, exit `0` |
| Source guardrail | `0` findings | `0` findings | `scripts/source_ingestion_guardrail.py`, exit `0` |
| Canonical entry point | Claude-oriented setup/path language | `AGENTS.md` → `linux-sysadmin/SKILL.md`; runner-specific setup optional | [AGENTS](../../AGENTS.md), [README](../../README.md), [hub](../../linux-sysadmin/SKILL.md) |
| Platform status | Scattered limitation; no matrix or CI route | Explicit matrix plus `ubuntu-24.04` workflow route | [platform matrix](platform-test-matrix-2026-08.md), [workflow](../../.github/workflows/bash-suites.yml) |
| Dry-run/rollback proof | No representative fixture | Five fictional scenarios validated; no host action | [fixture](../../tests/fixtures/safe-operation-evidence.json), validator and unit-test results below |
| Linux system execution | `NOT ASSESSED` | `NOT ASSESSED` pending CI/Linux run | The new route is available; availability is not execution evidence |
| Production evidence | `NOT ASSESSED` | `NOT ASSESSED` | No target host or real operator outcome was supplied |

### Re-score and maturity decision

The provisional raw re-score is held at `62.0`, equal to the diagnostic raw
baseline, because the documentation and fixture measures improved but the
release-blocking Linux system evidence remains unavailable. This is a deliberate
no-inflation decision, not a claim that the changes had no value. The Wave 1
published score remains `55.0` under the assignment-only cap. The maturity level
remains `L2`: the workflow is repeatable and more explicit, but live platform,
rollback, recovery, independent-agent, and production evidence are not yet
demonstrated.

The target `95` remains an improvement target only. It is not an achieved score.

## Test commands and results

### Baseline and change control

| Command | Result |
| --- | --- |
| `git status --short --branch` before edits | Exit `0`; `## main...origin/main` with no changed paths |
| `git log -5 --oneline --decorate` | Exit `0`; baseline inspected before edits |
| `git status --short` after edits | Only the files listed in [Files changed](#files-changed) are changed or untracked |
| `git diff --check` | Exit `0`; Git emitted only existing-style LF/CRLF conversion warnings for edited text files |

### Cross-platform and canonical validators

| Command | Exit | Raw result summary |
| --- | ---: | --- |
| `python -X utf8 scripts/validate_skills.py --baseline quality-baseline.json` | `0` | `44` active, `1` template, `44` fully compliant, no failures |
| `python -X utf8 scripts/routing_smoke_test.py` | `0` | `25/25` fixtures passed; top-three precision `1.000` |
| `python -X utf8 scripts/source_ingestion_guardrail.py` | `0` | `0` findings |
| `python -X utf8 C:\wamp64\www\skills-web-dev\skills\sdlc-meta\skill-engine-audit\scripts\engine_compliance.py --root . --active-root . --details` | `0` | `44` skills, `44` fully compliant, no failure counts |
| `python -X utf8 C:\wamp64\www\skills-web-dev\skills\sdlc-meta\skill-writing\scripts\quick_validate.py linux-sysadmin` | `0` | Skill is valid |
| `python -X utf8 C:\wamp64\www\skills-web-dev\skills\sdlc-meta\skill-writing\scripts\contract_gate.py --skill linux-sysadmin` | `0` | `0` errors, `0` warnings; no Evidence Produced table was scanned for this hub |
| `python -X utf8 scripts/validate_safe_operation_fixture.py tests/fixtures/safe-operation-evidence.json` | `0` | Five test-labelled scenarios passed; no host action executed |
| `python -X utf8 -m unittest discover -s tests -p 'test*.py' -v` | `0` | `3` tests passed |
| `python -m json.tool tests/fixtures/safe-operation-evidence.json` | `0` | JSON parse passed |
| `python -c "import yaml; ..."` for `.github/workflows/bash-suites.yml` | `0` | YAML parse passed and route markers were present |
| `python -m py_compile scripts/validate_safe_operation_fixture.py tests/test_safe_operation_fixture.py` | `0` | Python syntax passed |

### Unavailable Linux checks

The following commands were attempted only to establish availability. Each
returned exit `1` before the script body ran with
`WSL ... execvpe(/bin/bash) failed: No such file or directory`:

- `bash scripts/tests/check-distro-matrix.sh`
- `bash scripts/tests/common-sh.test.sh`
- `bash scripts/tests/install-skills-bin.test.sh`
- `bash scripts/tests/run-test.sh --suite foundation --image ubuntu:24.04`
- `bash -n scripts/setup-claude-code.sh` (syntax-only check)

These are `NOT ASSESSED`, not failed repository behaviour. No package,
service, firewall, storage, filesystem, recovery, installer, or production
operation was executed on this host.

## Safety, provenance, and anti-slop review

Safety status: `Needs Review` for the changed Claude adapter surface. The full
adapter was inspected and still contains pre-existing remote installation,
global package installation, SSH-key generation, and privileged writes in
[`scripts/setup-claude-code.sh`](../../scripts/setup-claude-code.sh). The Wave 1
change only labels that script as optional and makes its checkout root
overridable; it adds no new package or remote endpoint. The adapter was not
executed.

The new fixture and validator are safe for this scope: data is explicitly
`fictional-test-data`, execution mode is `read-only-simulation`, every scenario
sets `host_mutation` to false, and system/production evidence remains
`NOT ASSESSED` ([fixture](../../tests/fixtures/safe-operation-evidence.json)).
The CI installer suite is intentionally confined to its disposable CI job by
the workflow design; no CI run was available in this Wave 1 context.

Anti-slop review found no fabricated operational result. Numeric measures in
this report point to repository files or command output. The report separates
structural, behavioural, render, system, and production evidence. No direct
quote, external standard claim, real host identity, credential, or production
outcome was invented.

## Claude, Codex, and generic-agent compatibility

| Entry path | Status | Boundary |
| --- | --- | --- |
| Claude Code | Existing `CLAUDE.md` and `setup-claude-code.sh` remain available as optional adapters | The adapter is not the canonical skill contract; its execution remains safety-reviewed and unexecuted |
| Codex | `AGENTS.md` → `linux-sysadmin/SKILL.md` is explicit and does not require a special directory | Fresh live Codex discovery was not executed as a separate vendor test; mark that outcome `NOT ASSESSED` |
| Generic agent | `AGENTS.md`, `README.md`, and direct `SKILL.md` loading provide the manual fallback | No universal automatic instruction discovery was claimed; runner behaviour remains `NOT ASSESSED` |

## Remaining backlog

### P0

- Execute `.github/workflows/bash-suites.yml` and retain the CI run URL, commit,
  runner image, and exit state. Do not report the route as passed before that
  evidence exists.
- Re-run the Bash suites in a disposable Linux environment and record the
  actual Bash, distro, and image identity. The Windows host remains outside this
  evidence class.

### P1

- Use the disposable route to exercise one actual read-only or dry-run path for
  each high-risk family, then add rollback/recovery evidence only where the
  command and environment are explicitly bounded. Keep real system tests out of
  the Windows workflow.
- Add an independent fresh-context review of the matrix and fixture so the
  fixture is not mistaken for system or production proof.

### P2

- Validate a real Fedora/RHEL-family environment for SELinux, firewalld, httpd,
  NetworkManager, and migrated script behaviour; retain the existing rule that
  one-family evidence does not pass the other family.
- Review whether immutable action digests or a digest-pinned container should
  replace the current minor-pinned runner label after the first CI run.
- Revisit the Claude adapter's remote installer, credential, and privileged-write
  boundaries before treating it as safe for unattended use.

## Standardisation and next-wave recommendations

The successful learning is standardised in the repository router (`AGENTS.md`),
the operator guide (`README.md`), the canonical hub, the platform matrix, the
CI workflow, and the deterministic fixture validator. The smallest useful next
wave is to obtain the missing disposable-Linux evidence and have a fresh agent
re-audit the distinction between fixture, system, and production results. Do
not increase the score until those evidence boundaries are checked again.

Next re-audit dates are 2026-08-18 for the P0 route and 2026-08-25 for the P1
fixture evidence, matching the portfolio Wave 1 schedule.
