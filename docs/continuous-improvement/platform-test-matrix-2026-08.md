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

## 2026-10-29 Linux re-assessment

This dated addendum supersedes the Windows-only runtime limitations above for
these specific tests. It does not rewrite the historical Windows evidence.
Host: Fedora Linux 44; rootless Podman. The repository was mounted read-only
with SELinux mount labelling disabled for the test container only. No host
service, package or firewall mutation occurred.

| Check | Debian bookworm container | Fedora 44 container | Limit |
|---|---|---|---|
| `common-sh.test.sh` | 29 pass / 0 fail | 29 pass / 0 fail | Shell primitives/fixtures, not every operational script |
| `install-skills-bin.test.sh` | 21 pass / 0 fail | 21 pass / 0 fail after container-only diffutils install | Root inside disposable container; all installer targets temporary |
| Missing-cmp path | Pass | Pass | Exit 5 before destination mutation; help/list remain usable |
| ShellCheck 0.9.0 | Pass for common.sh, sk-audit.sh, installer and both changed shell suites | Not separately run | Eight changed files including backup, distro gate and web fixture; not an engine-wide lint pass |
| Python suite on Fedora host | Not run in this container | 73 tests and eight subtests pass on host; one opt-in lab skipped | Temporary venv; host/service effects stubbed |
| Native service/reboot/SELinux/ACL integration | `NOT_ASSESSED` | `NOT_ASSESSED` | Containers share the host kernel and do not prove boot or MAC behaviour |
| Production operations | `NOT_ASSESSED` | `NOT_ASSESSED` | No production target was supplied |

Image identities inspected during this run:

- Debian: `docker.io/library/debian@sha256:a0039cc6bb3eb2215aabcd3437cce8808a3858d86bf483eee2ee14fe4d2551c2`.
- Fedora: `quay.io/fedora/fedora@sha256:474e0ab5a1e59c215e59f281b1fe49f2866ec20f773533f5cca851cc830c5c2b`.

The Debian container installed ShellCheck from its configured distro repository;
the Fedora container installed diffutils. Images identify the base, not a
fully reproducible dependency snapshot. The Fedora base without diffutils
first failed idempotency; the dependency gate was then fixed and negative/normal
paths retested. No failure was suppressed to obtain these totals.

The Bash workflow now includes a digest-pinned Fedora fixture job alongside
Ubuntu. Local execution is recorded here; a GitHub-hosted workflow result is
not implied. See the [audit](kaizen-2026-10-29.md) for scope, commands and open gates.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.

The completed [Portfolio cycle](../kaizen/2026-10-engine-kaizen/05-final-report.md) adds an actual MySQL second-instance restore and dual-family PHP/Nginx upstream rollback. These disposable tests do not close full production hardening evidence.
