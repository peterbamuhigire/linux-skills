---
name: skill-writing
description: Use when creating or upgrading a portable Linux operations skill in this engine; distinguishes authoring contracts from executing `linux-sysadmin` workflows and from the read-only `skill-safety-audit` review gate.
license: Complete terms in LICENSE.txt
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
  portable: true
  compatible_with:
    - claude-code
    - codex
---

# Skill Writing

Create compact, executable Linux skill contracts that route cleanly and remain useful without optional scripts.

<!-- dual-compat-start -->
## Use When

- Creating a specialist Linux skill or changing an existing skill's trigger, contract, or resources.
- Extracting an entrypoint over 500 lines into directly linked references.
- Adding routing fixtures, acceptance evidence, or a safe degraded mode to a skill.

## Do Not Use When

- Executing a Linux administration task; route through `linux-sysadmin` or the matching specialist.
- Reviewing an already written skill for unsafe instructions only; use `skill-safety-audit`.
- Changing repository-wide policy without also updating the shared authoring standard and gates.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---:|---|
| Reusable problem and candidate trigger prompts | Request or issue | yes | Stop; a skill without real prompts cannot be routed or evaluated. |
| Neighbour skill descriptions | Active filesystem catalogue | yes | Discover active `SKILL.md` files before drafting. |
| Domain procedures and safety limits | Existing skill, references, and engine policy | yes | Return a gap list; do not invent operating doctrine. |
| Runner capabilities | Task environment | conditional | Specify capability-based fallbacks without naming a runner tool. |

## Workflow

1. Discover the active catalogue and decide whether an existing skill owns the reusable problem.
2. Define positive, negative, neighbour-collision, limited-capability, and failure-path prompts.
3. Draft the input, output, evidence, capability, degraded-mode, decision, recovery, and acceptance contracts before expanding procedures.
4. Preserve the `## Distro support` matrix as the first H2 for every specialist skill; route family differences through `common.sh` primitives in `sk-*` guidance.
5. Keep the entrypoint at or below 500 lines. Extract depth to `references/`, link it directly, and add a parent link to each extracted reference.
6. Run the local validator, routing smoke test, canonical quick validator, canonical engine scanner, link checks, and distro-matrix test.
7. Stop release on any structural or routing finding. Recover by fixing the named contract or by narrowing the trigger; never lower the zero-debt baseline.

## Quality Standards

- Keep domain decisions, stop conditions, recovery steps, and observable acceptance in the entrypoint.
- Use only `name`, `description`, `license`, `allowed-tools`, and `metadata` frontmatter keys.
- Preserve manual Linux commands as the baseline; scripts are optional accelerators.
- Use British English and evidence-backed examples; qualify anything not executed or observed.

## Anti-Patterns

- Copying a generic contract into every skill. Fix: name the actual server evidence, failure, and operator decision.
- Describing only a positive trigger. Fix: distinguish the closest neighbour in `Do Not Use When` and routing fixtures.
- Claiming a check passed when execution was unavailable. Fix: mark it `not assessed` and return the narrowest useful result.
- Granting mutation rights to an audit skill. Fix: default audit, analysis, critique, and planning to read-only.
- Keeping a 600-line command catalogue in `SKILL.md`. Fix: extract it to a linked reference that points back to the parent.
- Naming a runner-specific tool in the portable procedure. Fix: state the required read, search, edit, execute, network, or delegation capability.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Normalised `SKILL.md` | Linux operator and routing hub | Local and canonical validators report no finding; entrypoint is at most 500 lines. |
| Directly linked resources | Skill user | Each link resolves and every extracted reference links back to its parent. |
| Routing fixtures | Release gate | Expected skill ranks in the top three and negative routes do not select it. |

## Evidence Produced

| Category | Artefact | Acceptance condition |
|---|---|---|
| Correctness | Validator and quick-validation output | Every changed skill passes. |
| Routing | Positive, negative, collision, degraded, and failure fixtures | No failed fixture at the documented top-three threshold. |
| Safety | Skill safety review | No unexplained installer, credential request, privilege escalation, or hidden mutation. |

<!-- dual-compat-end -->

## Capability Contract

Read and search are required. Editing is permitted only for an authorised authoring task. Execute repository validators only within the task boundary; network and delegation are optional. Never mutate a server while writing a skill.

## Degraded Mode

If editing is unavailable, return a file-specific patch plan. If execution is unavailable, mark every validator and routing check `not assessed`. If domain evidence is missing, preserve the existing procedure and report the missing decision instead of fabricating it.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Existing skill has the same trigger and output | Normalise that skill | Duplicate routes and drift |
| Stable procedure has a distinct trigger and consumer | Create one skill | Overloaded neighbour entrypoint |
| Detail is needed only after routing | Put it in `references/` | Context waste and line-limit failure |
| Instruction is runner-specific | Put it in an adapter or repository policy | Non-portable skill body |

## Worked Example

Prompt: "Add guidance for diagnosing slow PostgreSQL queries." Inspect `linux-postgresql` and `linux-perf-profiling`; route database query and configuration diagnosis to the former, host-wide bottleneck attribution to the latter, and add a collision fixture that keeps both in the top three for the ambiguous prompt.

## References

- [Local skill authoring standard](../../docs/engine-design/skill-authoring-standard.md)
- [Skill template](../../templates/skill-template.md)
- [Engine specification](../../docs/engine-design/spec.md)
