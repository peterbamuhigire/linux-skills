# Documentation wave follow-ups — 31 October 2026

Items the documentation wave found and did not change, because the fix is a skill body, a script, a file mode, a
portfolio-managed sentence or a dated historical record. Each has the exact place and what a change would be. The
documentation edits themselves are in the README, `AGENTS.md`, `CONTRIBUTING.md`, `docs/README.md`,
`docs/engine-design/README.md` and `docs/engine-design/skill-authoring-standard.md`.

## Files and scripts

| Where | Finding | Measured | Change that would fix it |
|---|---|---|---|
| `install.sh` (and `install.ps1`) | Committed without the executable bit, so the documented `./install.sh` fails | `git ls-files -s install.sh` gives mode `100644`; `./install.sh --scope project --dry-run` exits 126 "Permission denied"; `bash install.sh --scope project --dry-run` exits 0 | `git update-index --chmod=+x install.sh` in a script change. The README documents `bash install.sh` meanwhile |
| `scripts/install-skills-bin` `--help` | Exit code 3 reads "not Debian/Ubuntu" although the engine covers both families | Seen in the usage text (carried from pass 2 and the lab wave) | Reword the usage text |
| `scripts/install-skills-bin --list` | Prints `yes` under INSTALLED? for an installed script that differs from the repository copy | Read in `scripts/install-skills-bin` `install_one` (differing files are only detected on install) | A `differs` state, as the lab wave's `06-next-cycle.md` already records |
| `scripts/setup-claude-code.sh` lines 105 to 119 | Absolute paths under one user's home | Carried from the lab wave's `06-next-cycle.md` | Make them parameters or label them as one workstation's example |
| `.claude/settings.local.json` | Tracked in Git and holds `/c/Users/...` paths | `grep` of the file | Not touched here: the documentation brief forbids it, and removing a tracked file from public history needs a decision |

## Managed router sentences in `AGENTS.md`

The shared renderer (`render_host_files.py --render-router-blocks --engine <this checkout> --dry-run`, from the frozen
snapshot of the portfolio package) proposes no change: output `{"changed": [], "dry_run": true}`. Run for real, and then
once more, it reported `{"changed": [], "dry_run": false}` both times and the file's SHA-256 did not change. The three sentences are in an older path-free form that the renderer neither
recognises nor rewrites, and they differ from the current templates:

- Line 46 names `digital-research-engine (resolve through the device catalogue)`. The template says "Digital Research
  Engine (catalogue id `digital-research-skills`; ...)". The GitHub repository is `chwezi-research-engine`.
- Line 59 names `chwezi-dev-engine/docs/engine-control-plane.json`. The template names `engine-control-plane.md`; both
  files exist in the engineering catalogue checkout.
- Line 320 appends "(resolve through the device catalogue)" to the craft-standard path.

They were left alone, as the brief requires. A portfolio decision is needed: align the templates to this older form, or
rewrite these three sentences by hand to the template wording. A non-managed sentence (the research-engine pointer in
"Baseline Skills") was corrected to use the GitHub name and the catalogue id.

## Skill bodies that still use former names

Skill content was not edited. `meta/kaizen-improvement-system/SKILL.md` lines 30, 71, 125 and 145 name
`digital-research-engine`, which is a catalogue folder name and not the GitHub repository (`chwezi-research-engine`).
`scripts/generate-plugin-manifest.js` lines 12, 13 and 28 use the same name in comments and an example.

## Dated records with workstation or Windows paths

Left as written, and marked as historical in [`docs/README.md`](../../README.md): `docs/analysis/strengths.md` line 279,
`docs/audits/2026-09-06-kaizen.md` line 5, `docs/continuous-improvement/kaizen-wave-1-2026-08-11.md` (lines 4, 156 to 158),
`kaizen-wave-2-2026-08-11.md` (lines 4, 153 to 159), `docs/engine-upgrade-july-2026/00-executive-summary.md` line 6 and the
two files under `docs/superpowers/`. `docs/engine-design/spec.md` (line 14 and the `require_debian` row) and
`script-inventory.md` keep their April 2026 Ubuntu/Debian wording; their READMEs now say so.

## An evidence statement that does not match the code

[`operator-note.md`](../2026-10-linux-lab-wave/operator-note.md) (section "Re-running the labs") says the labs "pull
nothing, publish no ports and mount no host path". That holds for `tests/test_distro_labs.py`, which copies the
repository into its containers. The MySQL labs do mount: `tests/test_mysql_backup.py` lines 95 and 217 pass
`-v <repository>:/repo:ro` and `-v <temporary lab directory>:/lab:rw`, on an internal Podman network (line 137). The
README states this as read from the code. The operator note was left as written (dated evidence); correct it in the next
cycle's edit of that folder.

## Not done

- `CHANGELOG.md`: the engine keeps none. Dated change notes live in `docs/updates/` and in each cycle's evidence folder,
  so none was created.
- `install.ps1`, the container labs and the ShellCheck gate were not run in this wave (no PowerShell; no containers by
  instruction). The README quotes the lab wave's results and labels them as taken from its validation record.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
