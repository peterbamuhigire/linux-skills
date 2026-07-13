---
name: linux-disaster-recovery
description: Use when recovering MySQL data, application files, configuration, boot state, or filesystems from a verified backup after loss or corruption; use linux-troubleshooting first when the fault may be recoverable without restore.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Disaster Recovery

## Distro support

Two-family skill. Backup/restore strategy and systemd rescue/emergency targets
are identical; recovery-time tooling differs at a few critical points — get
these wrong and a box won't boot. Body uses Debian/Ubuntu; substitute per this
matrix.

| Recovery concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Reinstall packages | `apt install --reinstall` | `dnf reinstall` |
| Regenerate GRUB | `update-grub` | `grub2-mkconfig -o /boot/grub2/grub.cfg` |
| GRUB config path | `/boot/grub/grub.cfg` | `/boot/grub2/grub.cfg` (UEFI: `/boot/efi/EFI/<distro>/`) |
| Rebuild initramfs | `update-initramfs -u` | `dracut -f` |
| Default root FS / repair | ext4 → `e2fsck` | xfs → `xfs_repair` (xfs can't shrink) |
| Restore networking | Netplan | NetworkManager/`nmcli` |
| Restore firewall | `ufw` | `firewalld` |
| Rescue target | `systemctl rescue` | identical |

**RHEL-family note:** the two recovery actions that most often differ are
**GRUB regeneration** (`grub2-mkconfig`, not `update-grub`) and **initramfs
rebuild** (`dracut -f`, not `update-initramfs`). Root is usually XFS — use
`xfs_repair`, and remember XFS cannot be shrunk. See
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md). In `sk-*` scripts
use the `common.sh` package primitives.

## Use when

- Data has been lost, corrupted, or overwritten and a restore may be required.
- You need to recover databases, application files, or config snapshots from backups.
- You need an emergency recovery checklist during a production incident.

## Do not use when

- The problem is only a service outage or bad config that can be fixed in place; use `linux-service-management` or `linux-troubleshooting`.
- The task is a routine backup review rather than an actual restore path.
- The task is **creating** backups — building rsync/tar archives, incremental
  snapshots, or filesystem (LVM/ZFS/Btrfs) snapshots. That now lives in the
  **`13-backup-and-archiving`** category: `linux-rsync-sync` (offsite/incremental
  rsync), `linux-archive-integrity` (tar create + verify), and
  `linux-filesystem-snapshots` (LVM/ZFS/Btrfs). This skill stays focused on
  *restore* and emergency recovery.

<!-- dual-compat-start -->

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Incident timeline, affected scope, and recovery objective | Incident commander/data owner | yes | Stop; do not choose a restore point |
| Backup catalogue, timestamp, checksum, and encryption access | Backup system/secret provider | yes | Do not restore or claim recoverability |
| Restore authority, target, and outage window | Change/data owner | yes for mutation | Produce a recovery plan only |
| Validation queries/files and rollback path | Application owner | yes | Stop before overwriting live state |

## Capability Contract

Read/search access may assess backups and recovery options. Decryption, filesystem repair, database replacement, bootloader/initramfs work, service stops, and destructive restores require explicit authority, protected credentials, and a recovery target. Never overwrite the sole surviving copy.

## Degraded Mode

Fallback when restore verification is unavailable: report the narrowest recoverable scope and blocking gap. Missing checksums, keys, isolated space, capacity, or application validation mean the recovery point has not passed.

## Decision Rules

| Condition | Action | Failure avoided |
|---|---|---|
| Fault may be configuration/service-only | Troubleshoot before restore | Unnecessary data rollback |
| Latest backup may contain corruption | Select last verified pre-incident point | Restoring bad state |
| Partial restore satisfies objective | Restore smallest isolated scope first | Excessive data loss/downtime |
| Source and target filesystem differ | Use family/filesystem-specific recovery path | Unbootable or damaged host |

## Workflow

1. Stabilise the incident, preserve current state, and confirm restore is necessary.
2. Define RPO/RTO, exact scope, target, authority, and rollback; stop if any required decision is absent.
3. Inventory candidate backups and verify timestamp, checksum, decryptability, and pre-incident status.
4. Test the smallest suitable restore in isolation and run application validation.
5. Confirm destructive impact, back up current target, execute the authorised restore, and record commands.
6. Validate data/service/access; on failure recover the pre-restore target and keep the incident open.

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Backup qualification | Shows source, timestamp, checksum, decrypt test, and incident relation |
| Restore execution record | Includes approval, target backup, commands, before-state backup, and timestamps |
| Recovery validation | Proves application queries/files, service health, access, and residual data gap |

## Quality standards

- Restore the smallest correct scope first when possible.
- Use timestamps and incident facts to choose the backup, not guesswork.
- Verification after restore is mandatory.

## Anti-patterns

- Restoring over live data without confirmation. Fix: record authority, target, impact, and before-state backup.
- Choosing the latest backup blindly. Fix: select a verified point before the incident/corruption.
- Ending after the restore command. Fix: run application, integrity, service, and access checks.
- Testing decryption for the first time during production restore. Fix: qualify the backup in isolation first.
- Repairing the wrong filesystem with family assumptions. Fix: detect filesystem and use its supported tooling.
- Overwriting the only surviving copy. Fix: restore into isolated space or clone current state first.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Recovery plan | Incident commander | Names RPO/RTO, restore point, scope, authority, validation, and rollback |
| Restored service/data | Application owner | Meets defined validation without destroying the source backup |
| Residual-loss statement | Data/risk owner | Quantifies time/data gap and unresolved controls |

## Worked Example

A table was corrupted at 10:20 EAT. Verify and decrypt the 10:00 database backup into an isolated database, validate row counts and application queries, then restore only the affected database after approval. Keep a dump of the damaged live database for rollback and investigation.

<!-- dual-compat-end -->

## References

- [`references/backup-strategy.md`](references/backup-strategy.md)
- [`references/restore-procedures.md`](references/restore-procedures.md)

**This skill is self-contained.** Every command below works on a stock
Debian/Ubuntu or RHEL-family server (substitute per the **Distro support**
matrix above). The `sk-*` scripts in the **Optional fast path**
section at the bottom are convenience wrappers — never required.

**Always confirm before restoring.** A restore overwrites existing data.
Never start a restore without typing the full word `yes` at the prompt,
even in non-interactive mode.

---

## Step 1: Assess First

```bash
# Is this a service crash (restart only) or actual data loss?
sudo systemctl status nginx mysql postgresql php8.3-fpm

# When did it happen?
sudo journalctl --since "2 hours ago" | grep -iE "error|fail|crash" | head -20
```

Service crash → restart it (`linux-service-management`), no restore needed.
Data loss/corruption → proceed below.

## Step 2: Find The Right Backup

```bash
# Local backups (7-day retention)
ls -lth ~/backups/mysql/*.gpg 2>/dev/null | head -10

# Google Drive (3-day retention for MySQL)
rclone ls gdrive:<backup-folder> 2>/dev/null | sort | tail -10

# If rclone token expired:
rclone config reconnect gdrive:
```

Choose the backup **closest to before the incident**.

## Step 3: Restore

Full restore procedure (decrypt → extract → import):
See `references/restore-procedures.md`.

The procedure, condensed:

```bash
# Decrypt (enter passphrase when prompted)
gpg --decrypt backup.sql.gz.gpg > backup.sql.gz

# Inspect size and sanity
gunzip -l backup.sql.gz
zcat backup.sql.gz | head -20

# Stop the service that writes to the DB
sudo systemctl stop nginx apache2 php8.3-fpm

# Restore (confirm first!)
zcat backup.sql.gz | mysql -u root -p <database>

# Restart
sudo systemctl start php8.3-fpm apache2 nginx
```

## Emergency Checklist

```bash
# 1. Stop affected service to prevent further damage
sudo systemctl stop <service>

# 2. Find best backup (Step 2 above)

# 3. Decrypt → restore → verify (references/restore-procedures.md)

# 4. Restart all services
sudo systemctl start nginx mysql php8.3-fpm apache2

# 5. Re-run security audit
sudo bash ~/.claude/skills/scripts/server-audit.sh

# 6. Clean up
rm -rf ~/restore/
```

## Demo/Dev Reset (Git-Tracked SQL Dump Pattern)

Some apps ship a git-tracked SQL dump as the demo DB source of truth.
A reset script drops and recreates from that dump:

```bash
ls /usr/local/bin/reset-*           # find available reset scripts
sudo reset-<app>-from-git           # requires typing YES
ls /var/backups/<app>/              # safety backup always created first
```

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-disaster-recovery` installs wrappers
for the above:

| Task | Fast-path script |
|---|---|
| Verify last backup is usable | `sudo sk-backup-verify` |
| Guided restore (pick backup, preview, confirm) | `sudo sk-restore-wizard` |
| MySQL restore from a specific file | `sudo sk-mysql-restore --file <path>` |
| PostgreSQL restore | `sudo sk-postgres-restore --file <path>` |
| Site file restore | `sudo sk-site-restore --backup <path> --target <dir>` |
| Maintenance mode on/off | `sudo sk-emergency-mode on\|off` |

These are optional wrappers around the commands above.

## Demo/Dev Reset (Git-Tracked SQL Dump Pattern)

Some apps ship a git-tracked SQL dump as the demo DB source of truth.
A reset script drops and recreates from that dump:

```bash
ls /usr/local/bin/reset-*           # find available reset scripts
sudo reset-<app>-from-git           # requires typing YES
ls /var/backups/<app>/              # safety backup always created first
```

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-disaster-recovery
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-backup-verify | scripts/sk-backup-verify.sh | yes | Verify last backup age, integrity (tar/gpg check), remote copy reachable via rclone. |
| sk-mysql-backup | scripts/sk-mysql-backup.sh | yes | Dump all databases with gzip + gpg + rclone upload; rotate local and remote. Refactored to source common.sh and honor standard flags. |
| sk-mysql-restore | scripts/sk-mysql-restore.sh | no | Guided restore: list backups, pick, download, decrypt, show sizes, confirm, restore. |
| sk-postgres-backup | scripts/sk-postgres-backup.sh | no | `pg_dump` + compression + gpg + rclone, per database or all, with rotation. |
| sk-postgres-restore | scripts/sk-postgres-restore.sh | no | Guided PostgreSQL restore from backup file or remote. |
| sk-site-backup | scripts/sk-site-backup.sh | no | Tar a full site directory, exclude cache/node_modules, gpg, upload via rclone. |
| sk-site-restore | scripts/sk-site-restore.sh | no | Restore a site backup to original path with permission repair. |
| sk-config-snapshot | scripts/sk-config-snapshot.sh | no | Snapshot `/etc/` (and other declared dirs) to a git-tracked archive; diff against previous. |
| sk-restore-wizard | scripts/sk-restore-wizard.sh | no | Interactive guided restore: pick backup set, pick target, preview, confirm, execute. |
| sk-emergency-mode | scripts/sk-emergency-mode.sh | no | Toggle maintenance mode: drop Nginx to 503 page, stop non-essential services, show live status. |
