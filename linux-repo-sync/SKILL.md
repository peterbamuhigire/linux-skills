---
name: linux-repo-sync
description: Safely update git repositories on a server without ever destroying uncommitted local work. Defines the binding doctrine for any automated or menu-driven repo-update script — pull --rebase --autostash, porcelain dirty-checks, conflict recovery, never git reset --hard or git clean -fd. Load before writing, reviewing, or running any script that pulls repos on a managed server.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Repo Sync — safe git updates on a server

## Use when

- Writing, reviewing, or running any script that pulls git repos on a server
  (a repo-update menu, a deploy hook, a cron sync).
- Updating one or many repos on a managed host as part of deployment or
  routine maintenance.
- Deciding how an automated update should treat local, uncommitted, or
  untracked changes in a server-side working tree.

## Do not use when

- The task is a one-off `git pull` a developer runs by hand in their own
  checkout and watches the output of.
- The task is authoring the generic script scaffold rather than the git
  behaviour; for the script contract load `linux-bash-scripting` first, then
  apply this doctrine to the git steps.

## Required inputs

- The repo path(s) to update.
- Whether the run is interactive (an operator is watching) or
  unattended (cron / agent).
- Any per-repo post-pull build command.

## Workflow

1. Confirm the path is a git working tree (`<path>/.git` exists).
2. Check the working tree state with `git status --porcelain` before touching it.
3. Pull with `git pull --rebase --autostash` so local work is stashed,
   the rebase runs, and the work is re-applied on top.
4. On conflict, stop and tell the operator how to recover — never discard.
5. Leave untracked files in place, always.
6. Run any post-pull build only after a clean, successful update.

## Quality standards

- An update must never destroy uncommitted or untracked work.
- A dirty working tree is reported to the operator, never silently wiped.
- A failed rebase or stash re-apply leaves the operator a clear recovery path.
- The same script is safe to run twice (idempotent) and safe to run on a
  repo someone edited five minutes ago.

## Anti-patterns

- `git reset --hard HEAD` in an automated or menu repo-update script.
- `git clean -fd` (or `-fdx`) in an automated or menu repo-update script.
- "Resetting local changes" as a routine pre-pull step.
- Auto-resolving or auto-aborting a rebase/stash conflict on the operator's
  behalf.
- Removing untracked files (uploads, `.env`, generated config) to "avoid
  conflicts".

## Outputs

- An updated repo with all local work preserved.
- A clear report of branch, new commit, and whether local changes were
  stashed/re-applied.
- On conflict: an explicit, copy-pasteable recovery path — never a wiped tree.

## References

- [`references/safe-update-pattern.md`](references/safe-update-pattern.md)

---

## The doctrine (binding on every repo-update script)

This is a STANDARD, not a suggestion. It exists because a repo-update menu
script once ran `git reset --hard HEAD` + `git clean -fd` before pulling and
silently wiped a developer's uncommitted edits. That must never be possible
again on any server we manage.

1. **NEVER use `git reset --hard` in an automated or menu repo-update
   script.** It destroys uncommitted changes to tracked files with no undo.
2. **NEVER use `git clean -fd` (or `-fdx`) in an automated or menu
   repo-update script.** It deletes untracked files — uploads, `.env`,
   generated config — that git is not tracking precisely because they must
   survive.
3. **Prefer `git pull --rebase --autostash`.** `--autostash` stashes any
   local changes before the rebase and re-applies them afterwards, so local
   work is preserved through the update. This is the default pull command for
   every server-side update.
4. **Detect a dirty working tree before pulling** with
   `git status --porcelain`. If it is non-empty, warn the operator that local
   changes exist (and will be stashed and re-applied, not discarded). Never
   discard them.
5. **On a rebase or stash-reapply conflict, STOP.** Do not auto-resolve, do
   not auto-abort. Report the conflict and the recovery options to the
   operator:
   - `git rebase --continue` after resolving the conflicting files, or
   - `git rebase --abort` to return to the pre-pull state, and
   - `git stash list` — the autostash is preserved here; recover it with
     `git stash pop` once the tree is clean.
6. **Untracked files are left in place, always.** An update never removes a
   file git is not tracking.

## The safe pattern (copy-paste)

```bash
update_repo_safely() {
    local path="$1"

    [[ -d "$path/.git" ]] || { echo "not a git repo: $path" >&2; return 1; }
    cd "$path" || return 1

    # 1. Detect a dirty working tree — warn, never wipe.
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "WARNING: $path has local changes."
        echo "         They will be stashed and re-applied, not discarded."
    fi

    # 2. Pull with rebase + autostash: local work is preserved.
    if git pull --rebase --autostash; then
        echo "updated: $(git rev-parse --abbrev-ref HEAD) -> $(git log -1 --oneline)"
    else
        # 3. Conflict — stop and hand the operator a recovery path.
        echo "ERROR: pull/rebase hit a conflict in $path." >&2
        echo "  Resolve the files, then:  git rebase --continue" >&2
        echo "  Or roll back the pull:     git rebase --abort"   >&2
        echo "  Your stashed local work:   git stash list  (recover with: git stash pop)" >&2
        return 1
    fi
}
```

What this never does: no `git reset --hard`, no `git clean`, no removal of
untracked files, no automatic conflict resolution.

## Canonical script on this server

`/usr/local/bin/update-all-repos` is the menu-driven repo-update tool that
must exist on every managed server (see
[`notes/update-all-repos-setup.md`](../notes/update-all-repos-setup.md)). It
must follow this doctrine: a porcelain dirty-check plus
`git pull --rebase --autostash`, never `git reset --hard` + `git clean -fd`.
The `sk-update-all-repos` script (`linux-site-deployment`) is the engine
version of the same tool and is held to the same standard.

If you find any repo-update script on a server still doing `git reset --hard`
or `git clean -fd`, that is a bug to fix, not a pattern to copy.

## Verify

```bash
# A repo-update script is safe iff this returns nothing:
grep -nE 'git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+clean[[:space:]]+-fd' /usr/local/bin/update-all-repos

# And iff it pulls with autostash:
grep -n 'pull --rebase --autostash' /usr/local/bin/update-all-repos
```
