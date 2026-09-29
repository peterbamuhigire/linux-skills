---
name: skill-writing
description: Use when creating or upgrading a portable Linux operations skill in this engine under the canonical chwezi-dev-engine skill-writing standard; distinguishes authoring contracts from executing `linux-sysadmin` workflows and from the read-only `skill-safety-audit` review gate.
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

Pointer stub. The canonical standard is `chwezi-dev-engine/skills/sdlc-meta/skill-writing` ([canonical on GitHub](https://github.com/peterbamuhigire/chwezi-dev-engine/blob/main/skills/sdlc-meta/skill-writing/SKILL.md); local path `C:\wamp64\www\chwezi-dev-engine\skills\sdlc-meta\skill-writing\SKILL.md`). Load it first; this file keeps a portable minimum and this engine's delta.
<!-- dual-compat-start -->
## Use When
- Creating a specialist Linux skill or changing an existing skill's trigger, contract, references or routing fixtures.
## Do Not Use When
- Execute Linux administration through `linux-sysadmin`; use `skill-safety-audit` for a read-only review of unsafe instructions.
## Required Inputs
| Artefact | Source/provider | Required? | If absent |
|---|---|---:|---|
| Reusable problem, trigger prompts and neighbour descriptions | Requester and live catalogue | Yes | Stop; search the catalogue before drafting. |
| Canonical skill-writing standard | chwezi-dev-engine checkout or GitHub | Yes | Apply the portable minimum and mark canonical-only checks `NOT ASSESSED`. |
## Workflow
1. Read the canonical standard, then this engine's delta; inspect the closest neighbours.
2. Write the input, output, evidence, capability, degraded-mode and decision contracts before the procedure.
3. Run `python -X utf8 scripts/validate_skills.py --baseline quality-baseline.json` and `python -X utf8 scripts/routing_smoke_test.py` (Linux-native tests run on Linux), then `python -X utf8 meta/skill-writing/scripts/quick_validate.py <skill-dir>`.
4. Stop on any finding or routing collision; recover by fixing the named contract and rerun, never by weakening the gate.
## Outputs
| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Skill directory and routing fixtures | Maintainer and router | Validators pass and the expected skill ranks in the top three. |
## Evidence Produced
| Evidence | Artefact and format | Consumer | Acceptance condition |
|---|---|---|---|
| Validation and routing record | Command output | Release owner | Zero findings; unrun checks marked `NOT ASSESSED`. |
<!-- dual-compat-end -->
## Quality Standards
- Portable minimum, applied even when the canonical is unreachable: frontmatter uses only approved keys and `name` matches the folder.
- The description starts `Use when`, stays within 350 characters and names a neighbour, with no workflow steps.
- `SKILL.md` stays within 500 lines; deep detail sits in references one level deep, linked directly.
- Every new or changed skill gets positive, negative and collision routing fixtures.
- Bundled scripts run through their interpreter, for example `python -X utf8 scripts/<name>.py`.
- No book extractions or copied third-party text; paraphrase and attribute.
- British English, the imperative mood, and `NOT ASSESSED` for any check not run.
## Engine-Local Delta
- Keep `## Distro support` as the first H2 of every specialist skill; route family differences through `common.sh` primitives in `sk-*` guidance; manual commands stay the baseline and scripts are optional.
- Never mutate a server while writing a skill; keep the author metadata keys; follow the [local authoring standard](../../docs/engine-design/skill-authoring-standard.md) and [skill template](../../templates/skill-template.md).
## Capability Contract
Read and search are required. Editing files and running validators need explicit permission for the authoring task; publishing, deletion and release changes need separate authorisation.
## Degraded Mode
If the canonical standard is unavailable, apply the portable minimum, return the narrowest qualified result, and mark each canonical-only check `NOT ASSESSED`; never report it as passed.
## Decision Rules
| Condition | Action | Failure or risk avoided |
|---|---|---|
| An existing skill owns the trigger and output | Normalise it in place; put branch-only detail in a linked reference | Duplicate routes and oversized entrypoints |
## Anti-Patterns
- Copying the canonical body into this engine. Fix: link the canonical and keep only the delta here.
- Writing only positive triggers. Fix: name the neighbour and add a collision fixture.
- Treating an unrun validator as a pass. Fix: record `NOT ASSESSED` with the reason.
- Granting edit rights to a review procedure. Fix: default review and audit to read-only.
- Weakening a baseline to clear a finding. Fix: repair the named contract instead.
## Worked Example
For slow PostgreSQL queries, inspect `linux-postgresql` and `linux-perf-profiling`; route query diagnosis to the former and host-wide attribution to the latter, and add a collision fixture for the ambiguous prompt.
## References
- [Canonical skill-writing standard](https://github.com/peterbamuhigire/chwezi-dev-engine/blob/main/skills/sdlc-meta/skill-writing/SKILL.md)
- [Local authoring standard](../../docs/engine-design/skill-authoring-standard.md)
- [Skill template](../../templates/skill-template.md)
- [Skill safety audit](../skill-safety-audit/SKILL.md)
