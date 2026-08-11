# Linux-skills Kaizen Wave 2 report

Assessment date: 2026-08-11
Repository: `C:\wamp64\www\linux-skills`
Scope: fresh safety re-audit of the optional Claude bootstrap, pinned CI route,
platform matrix, and related deterministic tests
Owner: Peter Bamuhigire / repository maintainer

## Executive result

Wave 2 corrected the Wave 1 safety finding in the optional
`scripts/setup-claude-code.sh` adapter. Remote installation, SSH-key creation,
checkout selection, and privileged writes now require separate explicit
authority flags. A real run requires exact target flags and a new recovery-file
path. `--dry-run` validates the plan before the first real-run mutation.

The adapter no longer contains a fetched shell-script pipeline, an empty
SSH-key passphrase argument, an implicit pull of an existing checkout, or the
old legacy privileged fallback. A cloned checkout must use an explicit GitHub
URL and an operator-supplied 40-hex commit. The Claude package must use an
operator-supplied exact `X.Y.Z` version and npm lifecycle scripts are disabled.
These controls are source-level and syntax evidence. The adapter was not run.

The pinned CI route and platform matrix were independently checked. The
workflow YAML and required step markers pass, but no retained CI run exists in
this Wave 2 context. Linux runtime, system, production, and LXD evidence remain
`NOT ASSESSED`.

## Fresh re-audit findings

Wave 1 changed the adapter's label and checkout-root override, but the source
still allowed the following paths:

- a NodeSource shell script fetched and piped into Bash;
- global npm installation without an explicit package version;
- SSH-key generation with an empty passphrase argument;
- a default `$HOME/.ssh/id_ed25519` target without an explicit target flag;
- `git pull` for an existing checkout;
- privileged installer, symlink, copy, and registry writes without separate
  action-level authority; and
- no retained pre-change recovery record.

Those findings were confirmed by reading the Wave 1 working-tree diff and the
full adapter source. The existing Wave 1 fixture only described fictional
package, service, firewall, storage, and recovery plans; it did not inspect the
Claude adapter.

The Wave 1 score records also need reconciliation. The portfolio report records
Linux diagnostic raw `70.0`, while the repository-local Wave 1 report deliberately
holds its raw re-score at `62.0` because live platform evidence was absent
([portfolio report](../../../KAIZEN-WAVE-1-REPORT.md), [repository Wave 1 report](kaizen-wave-1-2026-08-11.md)).
Wave 2 does not invent a replacement raw score. The exercise-published score
remains capped at `55.0` under the assignment rule in the initial assessment
([initial assessment](../../../KAIZEN-INITIAL-ASSESSMENT.md)).

## Wave 1 challenge and result

The primary negative control inserted a synthetic remote-shell line into a
copy of the adapter source. The new static audit detected both the remote curl
tool and fetched shell execution. A second negative control changed the CI
runner label from `ubuntu-24.04` to `ubuntu-latest`; the CI audit rejected the
mutation. These controls are implemented in
[`tests/test_bootstrap_safety_static.py`](../../tests/test_bootstrap_safety_static.py)
and run without invoking Bash, sudo, git, npm, SSH, or a package manager.

The portability challenge found two Bash launchers on Windows. The system WSL
launcher could not provide `/bin/bash` and returned exit `1` before the script
body ran. Git Bash was available and its syntax-only check of the changed
adapter returned exit `0`. Git Bash syntax is structural evidence, not Linux
system evidence. No bootstrap action or host mutation was executed.

## Exact Wave 2 files

Wave 2 changed only this repository. The Wave 1 files already present in the
working tree were preserved unless the listed safety documentation needed the
new contract.

- [`scripts/setup-claude-code.sh`](../../scripts/setup-claude-code.sh)
- [`tests/test_bootstrap_safety_static.py`](../../tests/test_bootstrap_safety_static.py)
- [`AGENTS.md`](../../AGENTS.md)
- [`CLAUDE.md`](../../CLAUDE.md)
- [`README.md`](../../README.md)
- [`linux-sysadmin/SKILL.md`](../../linux-sysadmin/SKILL.md)
- [`docs/engine-design/script-inventory.md`](../../docs/engine-design/script-inventory.md)
- [`docs/continuous-improvement/platform-test-matrix-2026-08.md`](platform-test-matrix-2026-08.md)
- this report

The Wave 1 CI workflow was inspected but not edited:
`.github/workflows/bash-suites.yml`.

## Improvement actions

### P0-LINUX-BOOTSTRAP: harden the optional Claude adapter

| Field | Wave 2 record |
| --- | --- |
| Gap | The optional adapter could perform remote installation, create an SSH key, pull an existing checkout, and write privileged paths without distinct authority or retained recovery evidence. The Wave 1 report recorded this surface as `Needs Review` ([Wave 1 safety section](kaizen-wave-1-2026-08-11.md#safety-provenance-and-anti-slop-review)). |
| Root cause | The adapter predated the runner-neutral Wave 1 entry-point repair. Its interactive prompts and environment default were treated as sufficient authority, and no static gate covered the adapter's high-risk calls. |
| Change | Replaced `scripts/setup-claude-code.sh` with explicit action flags, exact path validation, separate network/user/privileged/SSH-key authority flags, dry-run planning, GitHub host-key verification, exact commit and package-version inputs, retained clone staging, no existing-checkout pull, and a recovery manifest written before real actions. Updated the canonical and Claude controller wording in `AGENTS.md`, `CLAUDE.md`, `README.md`, and `linux-sysadmin/SKILL.md`; updated the script inventory. |
| Hypothesis | Requiring the operator to name each action, target, authority, remote revision, package version, and recovery file will prevent an unattended runner from silently selecting a host target or mutable remote input. |
| Owner | Peter Bamuhigire / Linux engine maintainer |
| Measure | Static audit has zero findings; Bash syntax check exits `0`; existing fixture and new safety tests exit `0`; the test suite reports `10` tests. Evidence: [static tests](../../tests/test_bootstrap_safety_static.py) and the command ledger below. |
| Risk | The adapter is now intentionally less convenient. Package repository provenance, npm registry behaviour, sudo policy, actual SSH host-key state, and recovery execution remain runtime concerns. |
| Rollback | Revert only the adapter and its safety documentation/test changes after reviewing any affected operator workflow. Do not restore the old implicit pull, remote shell pipeline, empty-passphrase generation, or unconditional privileged fallback. Failed clones retain their staging path for inspection; the adapter never auto-resets user data. |
| Acceptance evidence | Required markers, malformed remote-shell rejection, mutable CI-runner rejection, exact target checks, no-empty-passphrase check, no-pull check, recovery-file check, YAML/matrix checks, and `bash -n` all pass. The adapter itself remains unexecuted. |
| Standardisation | The explicit authority and recovery contract is now discoverable from `AGENTS.md`, `CLAUDE.md`, `README.md`, the Linux hub, the adapter help text, and the static safety gate. |
| Re-audit | 2026-08-25, with a disposable Linux run only if an authorised test host and retained recovery evidence are available. |

### P0-LINUX-CI-MATRIX: validate the disposable CI evidence route

| Field | Wave 2 record |
| --- | --- |
| Gap | Wave 1 added a disposable CI route and platform matrix, but no retained CI run was available. A route declaration cannot be treated as system evidence. |
| Root cause | Evidence and execution were separated in the matrix, but the Wave 2 audit had no external CI result to attach. |
| Change | Added the optional bootstrap safety row and explicit static-evidence boundary to [`platform-test-matrix-2026-08.md`](platform-test-matrix-2026-08.md), and added workflow/matrix assertions to [`test_bootstrap_safety_static.py`](../../tests/test_bootstrap_safety_static.py). The existing workflow remains unchanged. |
| Hypothesis | A static contract will prevent a future report from calling the `ubuntu-24.04` route passed before a real run is retained. |
| Owner | Peter Bamuhigire / Linux engine maintainer |
| Measure | YAML parses; runner `ubuntu-24.04`, timeout `15`, read-only contents permission, all four required workflow commands, `NOT ASSESSED`, LXD, and production labels are present; the workflow does not invoke the Claude adapter. |
| Risk | The runner label is explicit, but the `actions/checkout@v4` reference is still a mutable action tag. CI-host behaviour and action provenance are not established by local parsing. |
| Rollback | Revert only the matrix note and static assertions if the CI contract is intentionally redesigned. Keep the evidence-class distinction and the adapter safety tests. |
| Acceptance evidence | YAML parse and workflow/matrix static checks exit `0`; no CI run URL is claimed. |
| Standardisation | The matrix remains the authority for structural, behavioural, render, system, and production evidence labels. The workflow is a route to evidence, not evidence itself. |
| Re-audit | 2026-08-25, after a retained CI run or an explicit external blocker record. |

## Before, Wave 1, and Wave 2 measures

| Measure | Before Wave 1 | Wave 1 | Wave 2 | Evidence boundary |
| --- | --- | --- | --- | --- |
| Active contracts | `44/44` | `44/44` | `44/44` | Structural validator; no catalogue change ([quality baseline](../../quality-baseline.json)). |
| Routing fixtures | `25/25` | `25/25` | `25/25` | Routing smoke test; no Linux execution claim. |
| Source-ingestion findings | `0` | `0` | `0` | Repository guardrail; not a runtime safety certification. |
| Existing local fixture tests | No Wave 1 safe-operation fixture | `3` tests | `3` existing tests still pass | Fixture-only behavioural evidence; system and production remain unassessed ([Wave 1 report](kaizen-wave-1-2026-08-11.md)). |
| Safety/static test suite | No adapter-specific gate | No adapter-specific gate | `7` adapter/CI tests plus `3` existing fixture tests, `10` total | Source inspection, mutation controls, and deterministic Python tests; no host mutation. |
| Remote shell install | Present in the Wave 1 adapter source | `Needs Review` | No fetched shell execution pattern | Static source gate; remote package and repository provenance still need runtime review. |
| SSH-key path | Default home path and empty-passphrase argument in the Wave 1 adapter | `Needs Review` | Exact key flag, exact path, overwrite refusal, interactive passphrase, verified known-hosts path | Static source evidence; key creation and host verification not executed. |
| Existing checkout mutation | Wave 1 adapter pulled an existing checkout | `Needs Review` | Existing checkout is not pulled; new clone requires an exact commit and retained staging | Static source/syntax evidence; no clone executed. |
| Privileged writes | Direct sudo package, installer, registry, and legacy fallback paths | `Needs Review` | Separate privileged authority, exact installer/registry targets, recovery record before mutation | Static source evidence; sudo policy and rollback execution unassessed. |
| CI route | Workflow existed, no retained run | Route existed, no retained run | YAML and contract markers pass, no retained run | System evidence is still `NOT ASSESSED`. |
| Bash/LXD/system behaviour | `NOT ASSESSED` | `NOT ASSESSED` | `NOT ASSESSED`; Git Bash `bash -n` is structural only | No package, service, firewall, storage, recovery, or LXD operation was run. |

The Wave 1 portfolio report's Linux raw `70.0` and repository-local raw `62.0`
remain unreconciled. Wave 2 does not award a new raw score. Published exercise
score remains `55.0`; the permanent repository policy remains unchanged.

## Test commands and exits

| Command | Exit | Result and evidence boundary |
| --- | ---: | --- |
| `python -X utf8 -m unittest discover -s tests -p 'test*.py' -v` | `0` | `10` deterministic tests passed, including malformed remote-shell and mutable-runner negative controls. |
| `python -X utf8 scripts/validate_safe_operation_fixture.py tests/fixtures/safe-operation-evidence.json` | `0` | Five fictional dry-run/rollback scenarios passed; validator states no host action was executed. |
| `python -X utf8 -m py_compile scripts/validate_safe_operation_fixture.py tests/test_safe_operation_fixture.py tests/test_bootstrap_safety_static.py` | `0` | Python syntax passed. |
| `python -m json.tool tests/fixtures/safe-operation-evidence.json` | `0` | Fixture JSON parsed. |
| `"C:\\Program Files\\Git\\bin\\bash.exe" -n scripts/setup-claude-code.sh` | `0` | Changed adapter parsed by Git Bash; syntax evidence only. |
| Git Bash `setup-claude-code.sh --dry-run` with the existing repository as the exact target | `0` | Printed the complete plan and explicitly reported that no host action was called. |
| Git Bash `setup-claude-code.sh --yes --skills-root /c/wamp64/www/linux-skills` without action flags | `2` | Expected negative control: `--yes` was refused because `git-action` was not explicit. |
| `python -X utf8 scripts/validate_skills.py --baseline quality-baseline.json` | `0` | `44` active skills and `44` fully compliant under the existing baseline. |
| `python -X utf8 scripts/routing_smoke_test.py` | `0` | `25/25` routing fixtures passed; top-three precision `1.000`. |
| `python -X utf8 scripts/source_ingestion_guardrail.py` | `0` | `0` findings. |
| `python -X utf8 C:\\wamp64\\www\\skills-web-dev\\skills\\sdlc-meta\\skill-engine-audit\\scripts\\engine_compliance.py --root . --active-root . --details` | `0` | `44` skills, `44` fully compliant, no failure counts. |
| Python YAML parse and workflow/matrix assertions | `0` | Runner, timeout, permission, required steps, evidence labels, and no-bootstrap-in-CI contract passed. |
| `git diff --check HEAD` | `0` | No whitespace errors; Git emitted only LF/CRLF conversion warnings for edited text. |
| `bash -n scripts/setup-claude-code.sh` through the WSL launcher | `1` | Expected unavailable-platform evidence: `/bin/bash` could not be started. The script body did not run. |
| `shellcheck scripts/setup-claude-code.sh` | `NOT ASSESSED` | `shellcheck` is not installed on this Windows host. |
| `.github/workflows/bash-suites.yml` on GitHub Actions | `NOT ASSESSED` | No retained run URL, runner log, or exit state was available. |
| `scripts/tests/check-distro-matrix.sh`, `common-sh.test.sh`, `install-skills-bin.test.sh`, and LXD harness | `NOT ASSESSED` | Linux runtime evidence was not executed on this host; the installer suite remains confined to the disposable CI route. |

## Safety and anti-slop findings

Safety status: `Needs Review` for runtime execution, and structurally accepted
for the changed adapter contract. The repository safety guardrail reports `0`
source-ingestion findings. The static audit inspected the changed adapter,
controller wording, matrix, workflow contract, fixture validator, and new test.

Resolved safety findings:

- No fetched shell script is executed.
- Network access is separately authorised from user-owned and privileged writes.
- GitHub SSH checks require an existing known-hosts file with strict host-key checking.
- New keys cannot overwrite the exact target; non-interactive generation is refused.
- Existing checkouts are never pulled by this adapter.
- New clones use retained staging, an exact commit, and a verification step before move.
- The npm package requires an exact version and disables install scripts.
- Privileged install and registry actions require a separate authority flag.
- A new recovery record is written before a real run, and failed staging is retained.

Residual safety findings:

- Actual sudo policy, package repository trust, npm registry response, SSH-key
  creation, GitHub host verification, exact commit fetch, and recovery are not
  assessed on this host.
- The CI action reference remains `actions/checkout@v4`; immutable action-SHA
  provenance was not established.
- The adapter does not provide package rollback. Its recovery record names this
  boundary and points the operator to the host package history and change record.

Anti-slop result: no new external statistic, person, organisation, statute,
court case, or URL was introduced. Numeric claims in this report point to local
reports, repository files, or command evidence in the adjacent table. The
report separates structural, behavioural, render, system, and production
states. It does not convert Git Bash syntax, a YAML parse, a fixture, or a
workflow declaration into Linux, LXD, or production evidence.

## Portability status

| Runner | Status | Boundary |
| --- | --- | --- |
| Claude Code | Optional adapter contract updated; live Claude discovery and adapter execution are `NOT ASSESSED` | `CLAUDE.md` is a thin overlay. The canonical skills do not require the adapter. |
| Codex | Canonical route remains `AGENTS.md` to `linux-sysadmin/SKILL.md` | Fresh live Codex discovery was not executed; status is `NOT ASSESSED`. |
| Generic agent | Manual route remains root guidance followed by the selected `SKILL.md` | No universal automatic instruction discovery is claimed. |

## Residual backlog

### P0

- Retain a real GitHub Actions run for `.github/workflows/bash-suites.yml`,
  including runner, commit, logs, and exit state.
- Obtain an authorised disposable Linux run for the Bash suites. Keep Linux/LXD
  system behaviour `NOT ASSESSED` until that evidence exists.
- Obtain an approved source/provenance record for the exact npm package version
  and repository commit before any real bootstrap run.

### P1

- Run the adapter in a disposable environment with a non-production checkout,
  pre-created known-hosts file, test SSH key, and retained recovery record.
- Exercise both Debian-family and RHEL-family package branches, including
  controlled failure and recovery. One family must not stand in for the other.
- Install `shellcheck` in an approved disposable Linux validation environment
  and retain its result.

### P2

- Reconcile the portfolio raw score `70.0` with the repository-local raw score
  `62.0` before the next portfolio report.
- Review whether the CI action reference should move from a mutable major tag to
  an issuer-verified immutable digest. No digest is invented in this report.
- Re-test Claude, Codex, and generic-agent instruction discovery after vendor
  documentation or runner changes.

### Explicitly `NOT ASSESSED`

Linux package, service, firewall, storage, filesystem, SSH-key, privileged-write,
rollback, recovery, CI-run, LXD, production, render, live Claude, live Codex,
generic-runner, package-provenance, and shellcheck evidence remain unexecuted or
unretained. The Wave 2 acceptance claim is limited to source, fixture, Python,
YAML, routing, catalogue, engine, and syntax evidence listed above.
