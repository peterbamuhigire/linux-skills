# Linux system administration activity records

The `linux_admin_activity.py` helper records one concise summary after an engine-mediated administration task and produces a date-ranged Markdown report. It does not monitor the operating system, run commands, or change host configuration.

## Record one completed task

Run from the Linux engine checkout after the specialist workflow has completed:

```bash
python3 scripts/linux_admin_activity.py record \
  --category update \
  --operation "security update review" \
  --status no_change \
  --target-scope local \
  --summary "Checked the configured security update source; no applicable updates were installed." \
  --evidence-ref "case-2026-09-27-update-review" \
  --limitation "Repository ownership was not independently checked."
```

Use `--changed` only when state actually changed. Record `blocked`, `failed`, `partial`, `pending_reboot`, and `not_assessed` distinctly. Do not include hostnames, account names, credentials, command arguments, raw output, certificate material, or absolute paths. Existing journal/audit output and operation evidence remain the detailed source; use `--evidence-ref` for a short relative ID.

The default state directory follows XDG Base Directory Specification: `$XDG_STATE_HOME/chwezi/linux-admin`, falling back to `$HOME/.local/state/chwezi/linux-admin`. Each UTC month uses one `activity-YYYY-MM.jsonl` file. Files are created user-private where the filesystem allows it; no history is deleted automatically. Set `CHWEZI_ACTIVITY_ROOT` to an absolute path to select a different store. A shared root requires deliberate ownership and permissions.

## Generate a report

```bash
python3 scripts/linux_admin_activity.py report \
  --from 2026-09-01 --to 2026-09-30 \
  --output reports/system-admin-2026-09.md
```

To combine Linux and Windows records, pass the Windows activity directory as an additional input:

```bash
python3 scripts/linux_admin_activity.py report \
  --from 2026-09-01 --to 2026-09-30 \
  --include-record-root "/mnt/c/Users/<user>/AppData/Local/Chwezi/WindowsAdmin/activity" \
  --output reports/system-admin-2026-09.md
```

The report deduplicates event IDs, keeps partial/failed/blocked outcomes visible, and reports malformed records. It summarizes only the supplied activity files; absence of a record does not prove an action did not occur. Run `linux_auditd`/journald investigations separately when a forensic or host-wide record is required.

## Background and patching boundary

The ledger has no daemon, startup task, timer, privileged updater, or security-fix loop. Linux package updates remain owned by the active package manager and configured update policy. See the research and options record in the coordination repository at `docs/operations/system-admin-activity-record-contract-2026-09.md`. The XDG state-path basis is the [Freedesktop XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/).
