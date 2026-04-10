# linux-skills engine design

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This directory is the design reference for turning `linux-skills` into a full
Linux server management engine for Ubuntu/Debian production servers.

Read these documents before writing any new script or skill in this repo. They
are the source of truth for conventions; skill files and scripts must match.

## Contents

| File | Purpose |
|---|---|
| [`spec.md`](spec.md) | The engine specification: installation model, standard flags, `common.sh` library contract, manifest format, script template, safety rules. |
| [`script-inventory.md`](script-inventory.md) | The curated catalogue of ~90 scripts to build, ranked by priority and grouped by theme. Every new script must exist here before being written. |

## Status

- **Date drafted:** 2026-04-10
- **Authored by:** brainstorming session with Claude Code, informed by 9 books:
  *Pro Bash*, *Linux Command Line and Shell Scripting Bible*, *Wicked Cool
  Shell Scripts*, *Linux Command Lines and Shell Scripting* (Vickler),
  *Beginner's Guide to the Unix Terminal*, *Ubuntu Server Guide* (Canonical),
  *Linux Network Administrator's Guide*, *Linux System Administration for the
  2020s*, *Mastering Ubuntu* (Atef).
- **Scripts written:** 3 of ~90 (`server-audit.sh`, `mysql-backup.sh`,
  `update-all-repos`). The rest are planned — see the inventory.
- **Next session:** execute the inventory in priority order, starting with
  tier 1 (Foundation).

## How to use this design

- **Writing a new script?** Read `spec.md` first. Every script must obey the
  standard flags, source `common.sh`, match the script template, and be listed
  in `script-inventory.md`.
- **Writing a new skill?** Read `spec.md` §7 (Skill manifest format). Every
  skill that ships scripts must declare them in a `## Scripts` section so the
  installer can find them.
- **Installing on a new server?** Run `install-skills-bin core` once, then let
  individual skills lazy-install their own scripts on first use.
