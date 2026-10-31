# README kaizen record, 31 October 2026

Author: Peter Bamuhigire, [techguypeter.com](https://techguypeter.com), +256784464178.

Peter asked for the READMEs to read smarter and better. This is a scoped micro-cycle on this engine's [`README.md`](../../../README.md): Observe, Baseline, Select, Experiment, Check, Standardise, Teach, Re-measure. It publishes no score and does not change the figures in [Quality and improvement](../../../README.md#quality-and-improvement). Branch `kaizen/2026-10-readme-kaizen`, from `main` at `cb2fbd2`.

## Observe

The README was a wall of detail between the front door and the first command.

- The first runnable command was at line 105. No contents list existed, although the `toc` metric read 1 (a false positive; see Re-measure).
- Five H2 sections held all the content. "Quality and improvement" alone held 2,570 words, mostly three H3 sections that were never split.
- 44 lines ran over 300 characters; the longest was 1,380. Install, validation, gates and improvements were all dense paragraphs and table cells.
- 1,262 words (the References section) were citations that no script, test or manifest reads.
- The README carried no author line, which `AGENTS.md` requires in document footers.

Four heading anchors are linked from other files and must not move: `#validation`, `#updating-installed-scripts`, `#quality-and-improvement` and `#what-the-october-2026-kaizen-improved`. No script, test or workflow reads README text; `scripts/kaizen_metrics.py` checks its links and anchors.

### Baseline metrics

Measured on `main` with a read-only session tool (not part of the repository). Definitions: `words` outside code fences; `first_cmd` is the line of the first fenced block; `longest_sec` is the words in the longest H2 section; `long_lines` counts lines over 300 characters; `sent_len` and `fre` (Flesch reading ease) cover plain paragraphs only, not bullets or tables.

| Metric | Before | After | Target |
|---|---:|---:|---|
| `words` | 6,202 | 5,710 | at most 6,512 (aim 5,582) |
| `h2` | 5 | 19 | n/a |
| `toc` | 1 (false positive) | 1 (a real contents list) | 1 |
| `first_cmd` | 105 | 20 | 40 or less |
| `longest_sec` | 2,570 | 869 | 1,500 or less |
| `long_lines` | 44 | 1 | 22 or less |
| `max_line` | 1,380 | 364 | 700 or less |
| `sent_len` | 16.4 | 12.3 | 16.5 or less |
| `fre` | 42 | 52 | at least 42 (aim 47) |

Missed: the aim of minus 10 percent in `words`. The README is 7.9 percent shorter (492 words fewer), within the ceiling. Moving the source list saved 1,144 words. The front door, contents list, task table and How it works added 576, and the plain-English rewrite added 80 (mostly the "Problem", "Fix" and "Verified" labels).

## Select

| Item | Decision | Reason |
|---|---|---|
| R1 Front door | Applied | Opening, "At a glance" (six facts, counted again), "Start here" (three steps). First command at line 20. |
| R2 Contents | Applied | Grouped list of all 18 other H2 sections; every link resolves. |
| R3 Structure | Applied | 19 H2 sections, none over 869 words. The improvements list became three H2 sections plus a figures table. |
| R4 Find the right skill | Applied | Twelve tasks worded after `tests/fixtures/routing.json`. All 12 names exist (`find`), and the engine's own ranker puts each listed skill first. |
| R5 No walls of text | Applied | Longest paragraph 58 words; no table cell over 35 words; 1 line over 300 characters (the opening paragraph, 364). |
| R6 Plain English | Applied | Mean sentence 12.3 words; terms defined at first use; British English; no marketing wording. |
| R7 Say it once | Applied | Removed "documentation wave" process wording and the `Next:` line that repeated the contents. Kept "What the October 2026 kaizen improved" in the new style. |
| R8 Relocate bulk | Applied to References only | `docs/references.md` holds the full list. The 48-row skill catalogue stays: it is under the 50-row limit and is the README's core reference. The improvements section stays because Peter asked for it. |

## Experiment

| Commit | What changed |
|---|---|
| `c2a1293` | Moved the References section (books, repositories, tool projects, standards, product documentation) to `docs/references.md`, verbatim, headings one level up. The README keeps a summary and a link. `docs/README.md` indexes the page. |
| `c022d3e` | Front door, contents list, "When to use it", task table, "How it works", author footer. Reordered to use, check, then status. Promoted H3 sections to H2 with unchanged anchors. Renamed `Installation` to `Install` and `Capabilities` to `What is inside` (no inbound links). |
| `4029885` | Rewrote install, validation, quality, improvements, open findings and gates as short bullets. Date table sorted by date, with an "Enforced" column and the 2026-12-01 detail below it. |
| `408afe2` | Restored three notes (labs, ShellCheck, PowerShell) to say what was not run on 31 October 2026. |
| `7952094` | Dropped the `Next:` line. |

Metrics after each commit (same tool as above):

| Commit | `words` | `first_cmd` | `longest_sec` | `long_lines` | `sent_len` | `fre` |
|---|---:|---:|---:|---:|---:|---:|
| `main` (`cb2fbd2`) | 6,202 | 105 | 2,570 | 44 | 16.4 | 42 |
| `c2a1293` | 5,058 | 105 | 2,570 | 41 | 14.0 | 42 |
| `c022d3e` | 5,634 | 20 | 863 | 42 | 12.8 | 51 |
| `4029885` | 5,714 | 20 | 863 | 1 | 12.2 | 51 |
| `408afe2` | 5,721 | 20 | 869 | 1 | 12.2 | 51 |
| `7952094` | 5,710 | 20 | 869 | 1 | 12.3 | 52 |

Deliberate content changes, none to a figure:

- Added the author line, the MIT licence line, the `CONTRIBUTING.md` link and "For Windows hosts, use the paired engine `windows-admin-engine-skills`" (from `AGENTS.md`).
- The container-lab, PowerShell and ShellCheck notes no longer say "documentation wave"; they give the date and the reason.
- The `--as-of` commands for the 2026-12-01 gate moved from a table cell to a bullet. Their exit codes were run again (see Check).

## Check

Validators on `main` before and after, same commands as the README's [Validation](../../../README.md#validation) table, run from the repository root with `PYTHONDONTWRITEBYTECODE=1`. Python 3.14.8, Node.js 22.23.1, `pytest` 9.0.3 from an existing session virtual environment (no package was installed).

| Check | Before | After |
|---|---|---|
| `validate_skills.py --baseline quality-baseline.json` | exit 0 | exit 0 |
| `routing_smoke_test.py` | exit 0 (109/109, P@1 96/109, P@3 109/109) | exit 0 (same) |
| `check-distro-matrix.sh` | exit 0 | exit 0 |
| `python3 -m pytest -q` | exit 0, 119 passed, 9 skipped | exit 0, 119 passed, 9 skipped |
| `check_marketplace.py` | exit 0, 446 package files | exit 0, 448 |
| `generate-plugin-manifest.js ... --check` | exit 0, 45 skills | exit 0, 45 skills |
| `validate_safe_operation_fixture.py` | exit 0 | exit 0 |
| `source_ingestion_guardrail.py` | exit 0, 0 findings | exit 0, 0 findings |
| `common-sh.test.sh` | exit 0 | exit 0 |
| `kaizen_metrics.py` hygiene gate | exit 0; 0 dangling paths, 0 dangling anchors | exit 0; 0 and 0 |
| `test-destructive-bash-gate.js`, `test-plugin-hook-config.js` | exit 0, 61/61 and 7/7 | exit 0, 61/61 and 7/7 |
| `quick_validate.py linux-sysadmin` | exit 0 | exit 0 |
| `engine_compliance.py` (engineering-catalogue scanner) | exit 0, 48 compliant | exit 0, 48 compliant |
| `git diff --check` | exit 0 | exit 0 |

Exit codes are identical. Package file counts rose by 2 (the references page and this record).

Other checks, all run after the last README edit:

- Preservation: `readme-preserve-check.py` against `main`: 0 lost links, 0 lost commands (35 of 35 kept), 0 broken anchors (6 distinct `README.md#anchor` links in tracked files: the 4 listed under Observe, plus 2 that the new docs index lines add), 0 broken in-page links (19). 73 link targets moved to `docs/references.md`.
- Independent preservation check, not using that tool: all 74 URLs and 24 relative link targets of the old README appear in the new README or `docs/references.md`; all 249 of its inline code spans appear verbatim in one of the two; all 40 commit hashes appear in the new README, except 5 that now sit in `docs/references.md`.
- Counts, checked against `find` and the installer rather than the README: 48 `SKILL.md` files, 44 specialists in 16 category folders, 3 meta skills, 1 hub, 26 `sk-*` files, 13 tier 1 (`scripts/install-skills-bin --list`), 45 skills in the Codex manifest.
- Task table: the 12 task wordings were ranked with `scripts/routing_smoke_test.py`; the listed skill is first for all 12.
- Start here: `bash install.sh --scope project --dry-run` and `node scripts/install-engine.js doctor --scope project` were run from an empty scratch directory. The dry run listed files and wrote nothing; `doctor` printed `(nothing installed)`.
- Date gate: `kaizen_metrics.py --baseline docs/kaizen/2026-10-engine-kaizen-pass-2/metrics-final.json --as-of 2026-11-30` exited 0; with `--as-of 2026-12-01` it exited 1, and the report reads `expired_source_records: 10`.

`NOT_ASSESSED`: rendering on GitHub (anchors were computed with the same slug rules as the check tool and `kaizen_metrics.py`, which agree); `install.ps1` (no PowerShell); the container labs and ShellCheck (no containers used); `install-skills-bin.test.sh` (needs root); hosted CI on these commits (nothing was pushed).

## Standardise

Conventions for the next README editor. Limits are the ones this edit met.

1. **Skeleton.** Title and purpose; At a glance and Start here; Contents; When to use it; Find the right skill; How it works; What is inside; Install; Validation; Quality and improvement; References; Contributing, author and licence.
2. **Limits.** First fenced command within 40 lines. A contents list of every H2. No H2 over 1,200 words. No paragraph over 90 words and no table cell over 35. Lines over 300 characters only where a link or a command forces it. Mean sentence length 16 words or fewer.
3. **Interface headings.** Do not rename or move these without updating the linking files in the same commit: `Validation`, `Updating installed scripts`, `Quality and improvement`, `What the October 2026 kaizen improved`, `Open findings that matter to a user` and `Date-triggered gates` (linked from `AGENTS.md`, `CONTRIBUTING.md`, `docs/README.md` and two `docs/engine-design` pages).
4. **Say each figure where it is measured.** The skill, script, routing and test counts appear in At a glance, the Validation table and the figures table. Change all three together and re-run the commands in Validation.
5. **Move bulk, keep a link.** Source lists and long catalogues go to `docs/`. Keep a summary and a link in the README, and run the preservation check.

## Teach

- Run the Validation commands first, then edit the README, then run them again. Exit codes must match.
- Keep the four interface anchors, and keep the author line in the footer.
- A new fact goes in once, in the section that owns it. Link to it from elsewhere.

## Re-measure and next cycle

- **Metric defect.** `toc` reads 1 on the old README because it counts any four in-page links before the third H2. It should look for a heading named Contents, or for a run of consecutive link lines. Not fixed here: the tool is outside this repository.
- **Open.** The 10 percent word-count aim was missed (7.9 percent). A next pass could shorten the 19 improvement items further, or move them to `docs/` with a one-line summary each; that needs Peter's decision because he asked for the section.
- **Open.** `CHANGELOG.md` does not exist in this repository, so no changelog entry was made.
- **Idea, not built.** A test that compares the At a glance numbers with `find` and `install-skills-bin --list` would catch drift. Tests were out of scope.
- Re-run the metrics and the preservation check after the next README edit, and on 2026-12-01 when the date gate starts to fail.
