# Linux Skills documentation index

Author: Peter Bamuhigire, [techguypeter.com](https://techguypeter.com), +256 784 464 178.

This index lists what is under `docs/` and which records are current. The skills, scripts and routing live outside this folder; start from the [README](../README.md) (at a glance, three start steps, a contents list and a task-to-skill table) or [`AGENTS.md`](../AGENTS.md). Every measured figure for the engine, and the command that produced it, is in the README's [Validation](../README.md#validation) section.

## Current records: October 2026 Kaizen

| Folder or file | What it holds |
|---|---|
| [`kaizen/2026-10-engine-kaizen/`](kaizen/2026-10-engine-kaizen/) | 29 October first cycle: scope, baseline scorecard, backlog, experiment log, validation record, [final report](kaizen/2026-10-engine-kaizen/05-final-report.md), [next cycle](kaizen/2026-10-engine-kaizen/06-next-cycle.md), currency record, [portfolio refresh](kaizen/2026-10-engine-kaizen/portfolio-refresh.md) |
| [`kaizen/2026-10-engine-kaizen-pass-2/`](kaizen/2026-10-engine-kaizen-pass-2/) | 31 October pass 2, same file set, plus [documentation follow-ups](kaizen/2026-10-engine-kaizen-pass-2/07-docs-followups.md) from the documentation wave |
| [`kaizen/2026-10-linux-lab-wave/`](kaizen/2026-10-linux-lab-wave/) | 31 October lab wave (Debian 12, Fedora 44 and MySQL 8.4 in rootless Podman), same file set, plus the [operator note](kaizen/2026-10-linux-lab-wave/operator-note.md) |
| [`kaizen/2026-10-readme-kaizen/`](kaizen/2026-10-readme-kaizen/readme-kaizen-record.md) | 31 October README kaizen: the [record](kaizen/2026-10-readme-kaizen/readme-kaizen-record.md) of the README restructure (metrics before and after, what moved, the conventions to follow). A scoped cycle, so it publishes no score |
| [`updates/`](updates/) | Dated notes for operators: [PHP security and runtime upgrades](updates/2026-10-22-php-security-and-runtime-upgrades.md), [short user script paths](updates/2026-10-24-short-user-script-paths.md), [Kaizen pass 2](updates/2026-10-31-kaizen-pass-2.md) |
| [`security/`](security/) | [Vulnerability triage runbook](security/current-vulnerability-triage.md) and its [dated source register](security/source-register-2026-10-29.md) |
| [`continuous-improvement/`](continuous-improvement/) | Standards and records that the cycles use: [platform test matrix](continuous-improvement/platform-test-matrix-2026-08.md), [two-family validation and recovery](continuous-improvement/two-family-validation-and-recovery.md), [safe reversible operations](continuous-improvement/safe-reversible-operations-standard.md), [incident learning](continuous-improvement/incident-learning-standard.md), [product audit checklist](continuous-improvement/linux-product-audit-checklist.md), the [29 October interim record](continuous-improvement/kaizen-2026-10-29.md) and the [Codex model review](continuous-improvement/model-review-2026-10-29.md) |

The README's [Quality and improvement](../README.md#quality-and-improvement) section holds the latest published score. [What the October 2026 kaizen improved](../README.md#what-the-october-2026-kaizen-improved), the [open findings](../README.md#open-findings-that-matter-to-a-user) and the calendar of [date-triggered gates](../README.md#date-triggered-gates) follow it as separate sections.

## Reference

| File | What it holds |
|---|---|
| [`engine-design/`](engine-design/README.md) | The script and installer specification, the planned script inventory and the [skill authoring standard](engine-design/skill-authoring-standard.md) |
| [`multi-distro/plan.md`](multi-distro/plan.md) | The Debian and RHEL-family design and phasing |
| [`marketplace.md`](marketplace.md) | Claude Code and Codex plugin packaging, the file ceiling and what was and was not tested |
| [`agent-runtime-safety.md`](agent-runtime-safety.md), [`approval-enforcement.md`](approval-enforcement.md), [`approval-adapter.json`](approval-adapter.json) | Safety contract for agent runs and the approval adapter |
| [`control-plane-adoption.md`](control-plane-adoption.md) | How the shared control plane applies to this engine |
| [`operations/system-admin-activity.md`](operations/system-admin-activity.md) | Administration activity records |
| [`ai-prompting/`](ai-prompting/domain-prompt-compilation-contract.md) | The contract for generating a ready-to-paste operational prompt |
| [`references.md`](references.md) | The full list of books, adapted repositories, tool projects, standards and product documentation behind the engine (moved out of the README) |

## Historical records

These are kept as dated records and are not revised. Some name a workstation path or a Windows path from the time they were written, and some describe a state of the engine that no longer holds (for example an Ubuntu/Debian-only scope or a smaller skill count). Use the current records above for the present state.

| Folder | Period and content |
|---|---|
| [`analysis/`](analysis/README.md) | April 2026 readiness analysis |
| [`evaluation/2026-04-13/`](evaluation/2026-04-13/executive-summary.md) | April 2026 evaluation and reading list |
| [`superpowers/`](superpowers/plans/) | April and June 2026 plans and design specs |
| [`engine-upgrade-july-2026/`](engine-upgrade-july-2026/00-executive-summary.md) | July 2026 upgrade study and conformance record |
| [`audits/2026-09-06-kaizen.md`](audits/2026-09-06-kaizen.md) | September 2026 Kaizen audit |
| `continuous-improvement/` | The August and September 2026 wave records ([wave 1](continuous-improvement/kaizen-wave-1-2026-08-11.md), [wave 2](continuous-improvement/kaizen-wave-2-2026-08-11.md), [adoption plan](continuous-improvement/kaizen-adoption-2026-08.md), [book-driven record](continuous-improvement/book-driven-kaizen-2026-09-01.md), [skills-kaizen](continuous-improvement/skills-kaizen/)) |
