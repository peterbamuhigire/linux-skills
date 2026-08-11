# Linux-skills platform test matrix

Assessment date: 2026-08-11
Scope: repository validators, Bash suites, disposable execution, and
fixture-only safety evidence
Owner: Linux engine maintainer

This matrix prevents a structural or fixture check from being read as live
Linux or production evidence. A missing runtime is `NOT ASSESSED`, not a pass.

## Evidence labels

| Label | Meaning |
| --- | --- |
| Structural | Files, contracts, routes, links, or source guardrails were checked without exercising a Linux host. |
| Behavioural | A deterministic fixture or test observed a defined input/output or failure-path result. |
| Render | A human-visible or exported artefact was opened and inspected. |
| System | A disposable or target Linux environment executed the operating workflow. |
| Production | A real target environment and operator/user outcome were verified. |

## Current matrix

| Check | Windows working tree | Disposable Linux route | Evidence boundary |
| --- | --- | --- | --- |
| Skill contracts and baseline count | `PASS` when the documented Python command is run | Same command in existing quality workflow | Structural only |
| Routing fixtures | `PASS` when the documented Python command is run | Same command in existing quality workflow | Structural/routing only |
| Source-ingestion guardrail | `PASS` when the documented Python command is run | Same command in existing guardrail workflow | Structural/provenance scan only |
| Distro-matrix Bash invariant | `NOT ASSESSED` on this Windows host; `/bin/bash` is unavailable | `.github/workflows/bash-suites.yml`, `ubuntu-24.04` runner | System branch remains unverified until CI evidence is retained |
| `common.sh` Bash suite | `NOT ASSESSED` on this Windows host; `/bin/bash` is unavailable | `.github/workflows/bash-suites.yml`, `ubuntu-24.04` runner | Bash behaviour is not inferred from PowerShell or Git Bash |
| Installer Bash suite | `NOT ASSESSED` on this Windows host; it writes Linux system paths | `.github/workflows/bash-suites.yml`, disposable CI job | The suite may mutate only its disposable CI job, never this checkout host |
| LXD integration harness | `NOT ASSESSED`; `lxc` is unavailable on the host | `scripts/tests/run-test.sh --suite foundation --image ubuntu:24.04` on a Linux host with LXD | Requires a disposable Linux runtime; no local pass is implied |
| Safe operation fixture validator | `PASS` for fixture-only validation | Also runnable in CI | Behavioural fixture evidence; no system state is asserted |
| Optional Claude bootstrap safety surface | Static inspection only; adapter not executed | No workflow step invokes the adapter | Remote install, SSH-key, privileged-write, exact-target, dry-run, and recovery behaviour require static evidence or a separately approved disposable run |
| Render evidence | `NOT ASSESSED` | `NOT ASSESSED` | No visual artefact is in scope |
| Production evidence | `NOT ASSESSED` | `NOT ASSESSED` | No target host, service, or operator outcome was supplied |

## Pinned disposable route

`.github/workflows/bash-suites.yml` uses the minor-pinned GitHub-hosted runner
label `ubuntu-24.04`. It runs the distro-matrix, `common.sh`, and installer Bash
suites in a disposable CI job. The workflow is a route to evidence, not evidence
that this Windows run has already passed. Retain the CI run URL and exit state
when it is executed.

The existing LXD harness remains an optional local Linux route. Its default image
tag is `ubuntu:24.04`; a maintainer should record the image identity and runtime
before treating an integration result as system evidence.

## Host-safety record

No package, service, firewall, storage, filesystem, recovery, or installer
operation was executed against this Windows host for this matrix. The fixture
validator reads JSON and checks safety invariants only. System and production
claims remain `NOT ASSESSED` until a disposable or target environment supplies
the corresponding evidence.

The optional Claude bootstrap is not a CI step. Its static safety tests inspect
the source for explicit authority and exact-target gates, reject curl-piped
shell installation and implicit existing-checkout pulls, and confirm that its
dry-run branch precedes host actions. Bash syntax and runtime behaviour remain
`NOT ASSESSED` on this Windows host.
