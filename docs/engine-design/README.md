# linux-skills engine design

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This directory is the design reference for the `linux-skills` script and installer
conventions. It was drafted in April 2026 for Ubuntu/Debian servers; the engine now
supports both the Debian and RHEL families (see [`../multi-distro/plan.md`](../multi-distro/plan.md)),
and the spec and inventory below keep their original wording where it has not been revised.

Read these documents before writing any new script or skill in this repo. They
are the source of truth for conventions; skill files and scripts must match.

## Contents

| File | Purpose |
|---|---|
| [`spec.md`](spec.md) | The engine specification: installation model, standard flags, `common.sh` library contract, manifest format, script template, safety rules. |
| [`script-inventory.md`](script-inventory.md) | The planned catalogue of 88 scripts, ranked by priority and grouped by theme. It is a roadmap, not a list of what ships; for what ships see Status below. |
| [`skill-authoring-standard.md`](skill-authoring-standard.md) | The local skill contract and release gates for active `SKILL.md` files, with the commands that check them. |

## Status

- **Date drafted:** 2026-04-10
- **Authored by:** brainstorming session with Claude Code, informed by 9 books:
  *Pro Bash*, *Linux Command Line and Shell Scripting Bible*, *Wicked Cool
  Shell Scripts*, *Linux Command Lines and Shell Scripting* (Vickler),
  *Beginner's Guide to the Unix Terminal*, *Ubuntu Server Guide* (Canonical),
  *Linux Network Administrator's Guide*, *Linux System Administration for the
  2020s*, *Mastering Ubuntu* (Atef).
- **Scripts shipped (31 October 2026):** 26 `sk-*` sources
  (`find . -name 'sk-*' -type f` from the repository root), 18 under `scripts/` and 8 beside
  their skills; 13 are tier 1 (`scripts/install-skills-bin --list`). The inventory's other
  entries remain planned.
- **Validation and evidence:** the README's [Validation](../../README.md#validation) section
  lists the registered checks; the October 2026 records are under [`../kaizen/`](../kaizen/).

## How to use this design

- **Writing a new script?** Read `spec.md` first. Every script must obey the
  standard flags, source `common.sh`, match the script template, and be listed
  in `script-inventory.md`.
- **Writing a new skill?** Read `spec.md` §7 (Skill manifest format). Every
  skill that ships scripts must declare them in a `## Scripts` section so the
  installer can find them.
- **Installing on a new server?** Run `install-skills-bin core` once, then let
  individual skills lazy-install their own scripts on first use.
