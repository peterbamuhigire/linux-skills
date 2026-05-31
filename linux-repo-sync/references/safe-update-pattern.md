# Safe repo-update pattern — reference

**Author:** Peter Bamuhigire · techguypeter.com · +256 784 464 178

This reference expands the doctrine in `../SKILL.md` with the reasoning and
the failure modes behind each rule. The rule itself is binding; this file is
the "why".

## The incident this prevents

A repo-update menu script ran, for every repo, before pulling:

```bash
git reset --hard HEAD   # discard tracked-file edits
git clean -fd           # delete untracked files and dirs
git pull --rebase
```

A developer had uncommitted edits in a server-side checkout. Running the menu
silently destroyed them — no prompt, no backup, no recovery. `git reset
--hard` overwrites the working tree and index with no undo, and `git clean
-fd` deletes files git was never tracking. Together they guarantee data loss
whenever someone has local work, which on a shared/admin server is common.

## Why `--rebase --autostash` is the right default

`git pull --rebase --autostash` does, in order:

1. `git stash` any local changes (tracked-file edits and staged changes).
2. `git fetch` + `git rebase` your branch onto the updated upstream.
3. `git stash pop` to re-apply your local changes on top.

The result: the repo advances to the latest upstream commit AND the local
work survives. If the local work cleanly re-applies, the operator may not even
notice the stash happened. If it does not, git stops at a conflict (see
below) with everything still recoverable.

`--autostash` only touches tracked content. Untracked files are never
stashed and never removed — they simply stay on disk, which is exactly what
you want for uploads, `.env`, and generated artefacts.

## Dirty-tree detection

```bash
if [[ -n "$(git status --porcelain)" ]]; then
    # working tree is dirty
fi
```

`git status --porcelain` prints one line per changed/untracked path and
nothing at all on a clean tree, so a non-empty result is a reliable dirty
signal that is stable across git versions and locales. Use it to warn the
operator, never to trigger a wipe.

## Conflict recovery (what to tell the operator)

When the rebase or the autostash re-apply hits a conflict, the script must
stop and surface these options. It must NOT auto-resolve and must NOT
auto-abort.

| Situation | Recovery |
|---|---|
| Resolved the conflicting files | `git rebase --continue` |
| Want to undo the pull entirely | `git rebase --abort` (returns to pre-pull HEAD) |
| Need to find the stashed local work | `git stash list`, then `git stash pop` once the tree is clean |
| Want to inspect what conflicts | `git status` shows the unmerged paths |

The autostash entry is preserved in the stash list across a `--abort`, so the
operator's work is never lost even if they roll the pull back.

## Idempotency

A compliant update is safe to run repeatedly. On an already-up-to-date clean
repo it is a no-op fetch. On a repo with local work it stashes, rebases (or
fast-forwards), and re-applies — the same outcome every time. There is no
state that a second run corrupts.

## What a compliant script must never contain

- `git reset --hard` (any ref)
- `git clean -f`, `-fd`, `-fdx`
- `git checkout -- .` / `git restore .` used to bulk-discard working changes
- any branch in the code that removes untracked files "to avoid conflicts"
- any automatic `git rebase --abort` / `git stash drop` on conflict

## Grep check

```bash
# Must return nothing on a compliant script:
grep -nE 'reset[[:space:]]+--hard|clean[[:space:]]+-fd|checkout[[:space:]]+--[[:space:]]+\.|restore[[:space:]]+\.' <script>

# Must be present:
grep -n 'pull --rebase --autostash' <script>
grep -n 'status --porcelain' <script>
```
