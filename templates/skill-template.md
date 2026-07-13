---
name: skill-name
description: Use when [positive trigger]; distinguishes this workflow from [nearest neighbour] by [observable boundary].
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
  portable: true
  compatible_with:
    - claude-code
    - codex
---

# Skill Name

State the Linux operation and the operator outcome in one sentence.

## Distro support

| Concern | Debian / Ubuntu | RHEL family |
|---|---|---|
| Package | `package-name` | `package-name` |
| Service | `service-name` | `service-name` |

<!-- dual-compat-start -->
## Use When

- Name a concrete request that belongs here.

## Do Not Use When

- Route the closest neighbouring request to `neighbour-skill`.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---:|---|
| Server facts | System inspection or operator | yes | Stop before family-specific or mutating action. |

## Workflow

1. Inspect the current state without mutation.
2. Select the branch from the decision table and stop if its prerequisite is missing.
3. Apply only authorised work; recover with the named rollback or restoration step.
4. Verify the observable acceptance conditions.

## Quality Standards

- Name the domain-specific validation and release gates.

## Anti-Patterns

- Name a concrete wrong command or workflow. Fix: state the safe replacement.
- Name a second domain failure. Fix: state its correction.
- Name a third domain failure. Fix: state its correction.
- Name a fourth domain failure. Fix: state its correction.
- Name a fifth domain failure. Fix: state its correction.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Named result | Operator | State the observable check. |

## Evidence Produced

| Category | Artefact | Acceptance condition |
|---|---|---|
| Correctness | Verification record | Commands, exit status, and observed state are recorded. |

<!-- dual-compat-end -->

## Capability Contract

Read and search are required. Mutation, production access, destructive action, and publication require explicit authority.

## Degraded Mode

When execution or system access is unavailable, return a qualified command plan and mark checks `not assessed`; never turn missing evidence into a pass.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Observable condition | Domain action | Named wrong-choice failure |

## Worked Example

Give an input, the selected decision branch, the operator action, recovery behaviour, and the observable result.

## References

- [Domain reference](references/domain-reference.md)
