# Claude Code and Codex plugin packaging

Review date: 2026-10-29. This checkout keeps its existing Claude Code package as the source of truth and adds a Codex compatibility manifest that points at the same skill folders. No skill directory is copied or moved.

## Layout decision

The Claude package remains `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. Its explicit skill path list is retained and must continue to pass `node scripts/generate-plugin-manifest.js --engine . --root . --exclude 'docs,scripts,templates,tests,commands,meta,notes,prompts' --check`. The list covers operational skills; the three `meta/` authoring skills remain intentionally unlisted.

The Codex adapter is `.codex-plugin/plugin.json`. Its `skills` array mirrors the Claude paths, and its hook path points to the existing `hooks/hooks.json`. OpenAI's plugin reference documents a Codex `skills` path as a relative directory or array of paths; the Claude manifest reference also supports explicit skill directory arrays. Both require package-relative paths and reject traversal/out-of-root targets. ([OpenAI plugin manifest fields](https://developers.openai.com/plugins/deploy/submission); [Claude Code manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference))

There is no root portable `plugin.json`: the current skills are spread across their canonical engine directories. OpenAI's portable format discovers skills from a root `skills/` directory, while the compatibility manifest supports the explicit path array used here. Adding a portable root manifest without changing package layout would therefore change component discovery and can supersede Codex compatibility settings. ([OpenAI package structure and manifest precedence](https://developers.openai.com/plugins/build/plugins))

Public-upload support is not claimed. OpenAI's manifest field table documents a Codex `skills` path array, but its submission-error reference also describes `plugin_skills_path_unsupported` as requiring the root `skills/` directory. This engine uses distributed explicit skill paths, so that public-upload condition is unresolved; do not treat the local/repo compatibility manifest as evidence of public listing acceptance. ([OpenAI manifest fields](https://developers.openai.com/plugins/deploy/submission); [OpenAI submission errors](https://developers.openai.com/plugins/deploy/submission-errors))

The Codex manifest deliberately has no MCP declaration because this engine package declares no MCP server. It does not copy Claude's `userConfig`; OpenAI's Claude-plugin import guide says Claude `userConfig` is not executed by OpenAI plugins. The Codex hook reference is for the local compatibility package. OpenAI's public plugin guidance says packages with lifecycle hooks are not eligible for the public plugin directory; this work does not claim or attempt public submission. ([OpenAI Claude-plugin import guide](https://developers.openai.com/plugins/guides/submit-claude-plugin); [OpenAI hook/package guidance](https://developers.openai.com/plugins/build/plugins))

The existing Claude marketplace entry remains the repo-root plugin source. Anthropic documents `.claude-plugin/marketplace.json` with a root-relative source and a plugin entry whose name matches its manifest. OpenAI documents that its desktop client also reads a legacy-compatible `.claude-plugin/marketplace.json` location; local CLI installation and discovery have now been tested as recorded below. ([Claude marketplace guide](https://code.claude.com/docs/en/plugin-marketplaces); [OpenAI local marketplace formats](https://developers.openai.com/plugins/build/plugins))

## Checks

Run the marketplace validator and its regression tests from the repository root:

```sh
python3 scripts/check_marketplace.py
python3 -m unittest discover -s tests -p 'test_marketplace.py'
node scripts/generate-plugin-manifest.js --engine . --root . --exclude 'docs,scripts,templates,tests,commands,meta,notes,prompts' --check
```

The validator checks JSON shape, Claude marketplace/manifest identity and version alignment, Claude/Codex skill-set parity, on-disk skill coverage, normalized relative paths, traversal and symlink rejection, Codex listing fields, declared hook-file integrity, and the file cap. It fails closed when inventory cannot complete. Both counts have the `5000` cap: package-source file entries exclude `.git` and common ephemeral cache directories, while checkout file-like entries include `.git` and caches. A file-like entry is a regular file or a symlinked directory entry; directories are not counted. Counts use the working tree, including newly added files not yet staged, and the checker prints both totals separately.

These validator checks are structural. Separate offline native CLI tests now
prove local installation and discovery: Codex 0.165.0 exposes all 45 declared
skill paths; Claude 2.1.312 reports those skills plus two legacy commands. See
[the portfolio refresh](kaizen/2026-10-engine-kaizen/portfolio-refresh.md) for
scope and evidence. Hook execution and public marketplace acceptance remain
NOT_ASSESSED; no API-backed model test or public submission was performed.

For an existing checkout, run these commands from its root in the runtime
whose user installation you intend to change:

```sh
codex plugin marketplace add . --json
codex plugin add linux@chwezi-linux --json
codex plugin list --json
```

The file ceiling is hard: callers may use a smaller limit for testing, but the
validator rejects a configured limit above 5,000.

## Current source notes

- OpenAI Developers, “Package your plugin,” “Upload and submit your plugin,” “Submit your Claude Code plugin to OpenAI,” and “Plugin submission errors”; accessed 2026-10-29: [package](https://developers.openai.com/plugins/build/plugins), [submission](https://developers.openai.com/plugins/deploy/submission), [Claude import](https://developers.openai.com/plugins/guides/submit-claude-plugin), [errors](https://developers.openai.com/plugins/deploy/submission-errors).
- Claude Code Docs, “Plugins,” “Create a marketplace,” “Create a Claude Code plugin,” and “Plugin manifest reference”; accessed 2026-10-29: [overview](https://code.claude.com/docs/en/plugins), [marketplace](https://code.claude.com/docs/en/plugin-marketplaces), [create](https://code.claude.com/docs/en/plugins/create), [manifest](https://code.claude.com/docs/en/plugins/manifest-reference).

Author: Peter Bamuhigire — [techguypeter.com](https://techguypeter.com) — +256 784 464178.

Native `claude plugin validate .` passed on 2026-10-29 with two warnings: root `CLAUDE.md` is not loaded as plugin project context, and the plugin has no icon. Skills remain self-contained; the warning does not establish that a live client loaded them. Full output is retained in the Kaizen samples.
