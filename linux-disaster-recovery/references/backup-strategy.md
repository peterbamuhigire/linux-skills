# Backup strategy

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This file is the complete backup strategy reference for an Ubuntu/Debian
web server. It covers *what* to back up, *where* to keep it, *how often*,
*how encrypted*, and *how to know it's actually working*. All examples
use standard tools (`mysqldump`, `pg_dump`, `tar`, `gpg`, `rclone`, `cron`)
and require no `sk-*` scripts.

## Table of contents

- [The 3-2-1 rule](#the-3-2-1-rule)
- [What to back up](#what-to-back-up)
- [What NOT to back up](#what-not-to-back-up)
- [Compression trade-offs](#compression-trade-offs)
- [Encryption: GPG discipline](#encryption-gpg-discipline)
- [Off-site storage with rclone](#off-site-storage-with-rclone)
- [Retention policy](#retention-policy)
- [Scheduling with cron or systemd timers](#scheduling-with-cron-or-systemd-timers)
- [Monitoring backup success](#monitoring-backup-success)
- [Restore rehearsal](#restore-rehearsal)
- [Credential file hygiene](#credential-file-hygiene)
- [Complete example: mysql-backup.sh](#complete-example-mysql-backupsh)
- [Sources](#sources)

---

## The 3-2-1 rule

The gold standard for backups:

- **3 copies** of the data (the production copy + 2 backups).
- **2 different media** (local disk + remote cloud; or local disk + external
  drive; or local disk + NAS).
- **1 off-site** copy (different physical location, different failure domain).

Our default implementation:

1. **Production data** on the server's disk.
2. **Local backup copy** in `~/backups/<type>/` on the same server (fast
   restore for accidental `DROP`).
3. **Off-site encrypted copy** on Google Drive via rclone (survives fire,
   theft, ransomware on the server).

The local copy is not a "backup" in the 3-2-1 sense — it shares the failure
domain of production. It's a *fast restore cache*.

---

## What to back up

### Always

| Asset | Why | How |
|---|---|---|
| **All databases** (MySQL, PostgreSQL) | Everything revolves around this | `mysqldump --all-databases`, `pg_dump` |
| **`/var/www/`** | Site code + uploaded user content | `tar` excluding cache/node_modules |
| **User-uploaded content dirs** | Often under `/var/www/.../uploads/`, sometimes elsewhere | `tar` |
| **`.env` files + credential files** | Irreplaceable secrets | separate encrypted archive, rotate with `linux-secrets` |
| **`/etc/`** (config snapshots) | Reproducible rebuild | `tar czf`, ideally git-tracked via etckeeper |
| **GPG key and rclone config** | Without these you can't decrypt the backups themselves | store **off-server**, not in the backups they unlock |

### Often

| Asset | Why | How |
|---|---|---|
| **Let's Encrypt certs** (`/etc/letsencrypt/`) | Convenience — can be reissued | `tar czf` |
| **SSH host keys** (`/etc/ssh/ssh_host_*`) | Rebuilds keep the same host identity | `tar czf` (mode 600) |
| **MySQL binlogs** since last full | Point-in-time recovery | `cp` to backup dir, rotate |
| **Cron jobs and systemd timers** | Part of `/etc/` snapshot | included with /etc |

### Sometimes

| Asset | Why | How |
|---|---|---|
| **`/home/administrator/`** | Bash history, ssh keys, personal scripts | user decision |
| **Docker volumes** | App state in containers | `docker run --rm -v <vol>:/src -v /backup:/dst alpine tar czf /dst/vol.tar.gz -C /src .` |
| **LXD container exports** | Full container restore | `lxc export <name> <file>` |

### Never (but see note)

- **`/var/cache/`** — package cache, reproducible.
- **`/var/tmp/`** and **`/tmp/`** — temporary by definition.
- **`node_modules/`** — rebuildable from lockfile.
- **Composer `vendor/`** — rebuildable from `composer.lock`.
- **Build output dirs** like `dist/` — rebuildable from source.
- **Docker images** — rebuildable from Dockerfile + pinned base.

Note: if rebuild time matters more than disk space, include build output.
The rule is "back up what's irreplaceable", not "skip everything rebuildable".

---

## What NOT to back up

- **`/var/log/`** — logs must **ship off the host live** (see
  `linux-observability`), not be caught by a backup after the fact. If
  ransomware deletes your logs, the backup is too late.
- **`/proc/`, `/sys/`, `/dev/`** — virtual filesystems, meaningless to back up.
- **`/var/lib/mysql/`** *as a raw file copy* — you'll capture an inconsistent
  mid-transaction state. Use `mysqldump` or `mysqlbackup` instead.
- **Running Docker container rootfs** — use `docker commit` or back up
  *volumes*, not containers.
- **Swap file** — ephemeral.

---

## Compression trade-offs

| Tool | CPU | Ratio | When to use |
|---|---|---|---|
| `gzip` (`gz`) | fast | medium | Default. Good balance. Every Unix can read it. |
| `xz` | slow | best | Archive backups you'll rarely restore. Disk-bound servers. |
| `bzip2` | medium | medium-good | Legacy choice, rarely best at anything now. |
| `zstd` | fast | very good | Modern choice. Better than gzip at similar CPU. Requires `zstd` package. |

Recommended default for a live backup cron: **gzip**. Fast, universal, good
enough ratio. Switch to `zstd` if you're disk-bound.

```bash
tar czf backup.tar.gz <dir>          # gzip (default)
tar cJf backup.tar.xz <dir>          # xz
tar --use-compress-program=zstd -cf backup.tar.zst <dir>   # zstd
```

---

## Encryption: GPG discipline

Backups leave the server and land on third-party cloud storage. Encrypt
them. Period.

### Symmetric vs asymmetric

- **Symmetric** (one passphrase encrypts and decrypts) — simpler for
  unattended backup scripts. The passphrase file lives on the server in
  mode `0600`. This is the default for `linux-skills`.
- **Asymmetric** (public key encrypts, private key decrypts) — stronger:
  the server never holds the decryption key. More complex to operate.

### Symmetric GPG (the default pattern)

```bash
# Generate a strong passphrase once (64 bytes base64)
openssl rand -base64 64 > ~/.backup-encryption-key
chmod 600 ~/.backup-encryption-key

# Encrypt
gpg --batch --symmetric --cipher-algo AES256 \
    --passphrase-file ~/.backup-encryption-key \
    -o backup.tar.gz.gpg backup.tar.gz

# Decrypt
gpg --batch --passphrase-file ~/.backup-encryption-key \
    -d backup.tar.gz.gpg > backup.tar.gz
```

### Where the key file lives

- `~/.backup-encryption-key` on the server (mode 600).
- **A second copy off the server** — in a password manager, a hardware
  token, or printed on paper in a safe. Without this second copy, losing
  the server = losing every backup.
- **Not** in the same cloud account where the backups are stored.
- **Not** in git. Not in `/etc/linux-skills/`. Not in the backup itself.

### Rotation

See `linux-secrets` `rotation-playbook.md`. Summary: rotate annually, keep
the old key for at least one retention cycle so old backups can still be
decrypted.

---

## Off-site storage with rclone

### Install and configure

```bash
sudo apt install rclone
rclone config
# Follow the interactive prompts:
# - n (new remote)
# - name: gdrive
# - type: drive (Google Drive)
# - auth via web (run on a laptop; paste the auth token back)
```

Config lives at `~/.config/rclone/rclone.conf` — **mode 600**.

### Verify

```bash
rclone lsd gdrive:
rclone about gdrive:
rclone copy test.txt gdrive:test/
rclone ls gdrive:test/
rclone delete gdrive:test/test.txt
```

### Upload a backup

```bash
rclone copy ~/backups/mysql/mysql-backup_20260410-0200.tar.gz.gpg \
    gdrive:linux-skills-backups/<hostname>/mysql/
```

### Rotate the remote side (delete old files)

```bash
# Delete files older than 3 days on the remote
rclone delete gdrive:linux-skills-backups/<hostname>/mysql/ \
    --min-age 3d
```

### Token refresh

Google's OAuth tokens expire. When they do, the cron job starts failing
silently. Monitor (see below), and reconnect:

```bash
rclone config reconnect gdrive:
```

### Alternative backends

- **S3** (`rclone config` → type `s3`): most reliable, pay per GB.
- **Backblaze B2** (`type b2`): cheapest for pure backup.
- **SFTP** (`type sftp`): your own remote server.
- **Dropbox** (`type dropbox`): simple personal-scale.

For a production server, S3 with lifecycle rules (transition to Glacier
after 30 days) is the professional default. For a single-operator setup,
Google Drive is fine.

---

## Retention policy

### The default policy

- **Local**: 7 days of daily backups. Fast restore cache.
- **Remote**: 3 days of daily backups. Catches cases where the local disk
  is destroyed or filled.
- **Off-site archival**: monthly snapshot kept for 1 year (optional).

### Generational rotation (grandfather-father-son)

For higher assurance:

| Level | Keep | Where |
|---|---|---|
| Daily | 7 days | Local + remote |
| Weekly (Sunday) | 4 weeks | Remote only |
| Monthly (1st of month) | 12 months | Remote only |
| Yearly (Jan 1) | forever | Remote cold storage |

Implementation with `rclone` and date-based filenames:

```bash
# Naming convention:
#   daily:   mysql-backup_YYYYMMDD.tar.gz.gpg
#   weekly:  mysql-backup_YYYY-Www.tar.gz.gpg       (%G-W%V)
#   monthly: mysql-backup_YYYY-MM.tar.gz.gpg
#   yearly:  mysql-backup_YYYY.tar.gz.gpg

# Daily prune (older than 7 days, local)
find ~/backups/mysql -name 'mysql-backup_daily_*.gpg' -mtime +7 -delete

# Weekly prune (remote)
rclone delete gdrive:backups/weekly/ --min-age 35d

# Monthly prune (remote)
rclone delete gdrive:backups/monthly/ --min-age 400d
```

---

## Scheduling with cron or systemd timers

### cron example

```cron
# /etc/cron.d/linux-skills-backup
MAILTO=ops@example.com
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# MySQL backup at 02:00 daily
0 2 * * * root /usr/local/sbin/mysql-backup.sh >> /var/log/linux-skills/mysql-backup.log 2>&1

# Site files backup at 02:30 daily
30 2 * * * root /usr/local/sbin/site-backup.sh >> /var/log/linux-skills/site-backup.log 2>&1

# /etc snapshot at 02:45 daily
45 2 * * * root /usr/local/sbin/etc-snapshot.sh >> /var/log/linux-skills/etc-snapshot.log 2>&1

# Retention cleanup at 03:15 daily
15 3 * * * root /usr/local/sbin/backup-cleanup.sh >> /var/log/linux-skills/backup-cleanup.log 2>&1
```

### systemd timer alternative (more robust)

```ini
# /etc/systemd/system/mysql-backup.service
[Unit]
Description=Daily MySQL backup
After=mysql.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/sbin/mysql-backup.sh
StandardOutput=append:/var/log/linux-skills/mysql-backup.log
StandardError=append:/var/log/linux-skills/mysql-backup.log
```

```ini
# /etc/systemd/system/mysql-backup.timer
[Unit]
Description=Daily MySQL backup

[Timer]
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mysql-backup.timer
systemctl list-timers mysql-backup.timer
```

Systemd timers have three advantages over cron:
1. `Persistent=true` catches missed runs (e.g. server was off at 02:00).
2. `RandomizedDelaySec` spreads load across multiple servers.
3. Failures show up in `systemctl status`, not just email.

---

## Monitoring backup success

A backup you're not watching is not a backup. Three layers:

### Layer 1: the script writes a log

Every backup script writes stdout + stderr to
`/var/log/linux-skills/<type>-backup.log`. First line of every run includes
the timestamp. Last line includes `SUCCESS` or `FAILURE` plus bytes.

### Layer 2: the cron sends mail on failure

Configure `MAILTO` and an MTA (see `linux-mail-server`). The script uses
`set -e` so any failure produces cron output, which cron mails.

For a systemd timer, use `OnFailure=alert@.service` to trigger a separate
alert unit on failure.

### Layer 3: a watchdog checks the most recent backup age

The real danger is *silent* failure — the script runs but writes nothing,
or uploads nothing. A watchdog cron (or monitoring check) verifies the
most recent backup is younger than expected:

```bash
#!/bin/bash
# /usr/local/sbin/backup-watchdog.sh — alerts if last backup is too old
MAX_AGE_HOURS=30

for type in mysql site etc; do
    latest=$(find ~/backups/$type -name '*.gpg' -printf '%T@ %p\n' \
             2>/dev/null | sort -rn | head -1)
    if [[ -z "$latest" ]]; then
        echo "FAIL: no $type backup found"
        continue
    fi
    age_sec=$(echo "$latest" | awk -v now="$(date +%s)" '{print now - $1}')
    age_hours=$((age_sec / 3600))
    if [[ "$age_hours" -gt "$MAX_AGE_HOURS" ]]; then
        echo "FAIL: $type backup is $age_hours hours old (max $MAX_AGE_HOURS)"
    else
        echo "OK:   $type backup is $age_hours hours old"
    fi
done
```

Schedule it at 12:00 daily (after the 02:00 backup should have run,
before the business day gets busy). Route failures to ops alerting.

### Layer 4: remote-side monitoring

Confirm the remote copy arrived, too:

```bash
latest_remote=$(rclone ls gdrive:linux-skills-backups/mysql/ --max-age 30h | \
                wc -l)
if [[ "$latest_remote" -lt 1 ]]; then
    echo "FAIL: no remote mysql backup in the last 30h"
fi
```

This catches the case where the local backup runs but the rclone upload
silently fails (expired token, API rate limit, Google outage).

---

## Restore rehearsal

**You don't have a backup until you've restored from it.** Schedule
quarterly restore drills:

1. Launch a disposable LXD container:
   ```bash
   lxc launch ubuntu:24.04 restore-drill-$(date +%Y%m%d)
   ```
2. Install MySQL (or Postgres) inside.
3. Push the most recent backup and GPG key to the container.
4. Run the full restore procedure from
   [`restore-procedures.md`](restore-procedures.md).
5. Verify the restored database is queryable and has the expected record
   counts.
6. Document the drill result in `/var/log/linux-skills/restore-drills.log`.
7. Destroy the container.

A failed drill is a **backup bug**, not a drill bug. Stop and fix before
the next production incident finds it.

---

## Credential file hygiene

The files that backups depend on are also the first targets in a
compromise:

| File | Mode | Owner | Why |
|---|---|---|---|
| `~/.backup-encryption-key` | 600 | root or admin user | passphrase for GPG |
| `~/.mysql-backup.cnf` | 600 | root or admin user | mysql login credentials |
| `~/.config/rclone/rclone.conf` | 600 | admin user | cloud storage token |
| `/etc/letsencrypt/live/*/privkey.pem` | 640 | root | TLS private key (not technically a backup cred but same rules) |

Verify:

```bash
stat -c '%a %n' ~/.backup-encryption-key ~/.mysql-backup.cnf \
    ~/.config/rclone/rclone.conf
```

Anything other than `600` is a finding for `sk-audit`.

---

## Complete example: mysql-backup.sh

A production-ready backup script. Works today, and will be the basis for
the future `sk-mysql-backup` rewrite.

```bash
#!/usr/bin/env bash
# /usr/local/sbin/mysql-backup.sh — daily MySQL backup with GPG + rclone
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

set -euo pipefail

# --- Config -----------------------------------------------------------------
BACKUP_DIR="/root/backups/mysql"
KEY_FILE="/root/.backup-encryption-key"
CNF_FILE="/root/.mysql-backup.cnf"
REMOTE="gdrive:linux-skills-backups/$(hostname)/mysql"
LOCAL_RETENTION_DAYS=7
REMOTE_RETENTION_DAYS=3

TIMESTAMP=$(date +%Y%m%d-%H%M)
DUMP_DIR="$BACKUP_DIR/dump_$TIMESTAMP"
ARCHIVE="$BACKUP_DIR/mysql-backup_$TIMESTAMP.tar.gz"
ENCRYPTED="$ARCHIVE.gpg"
LOG_PREFIX="[mysql-backup $TIMESTAMP]"

# --- Preflight --------------------------------------------------------------
[[ $EUID -eq 0 ]] || { echo "$LOG_PREFIX must run as root" >&2; exit 1; }
[[ -f "$KEY_FILE" ]] || { echo "$LOG_PREFIX missing $KEY_FILE" >&2; exit 2; }
[[ -f "$CNF_FILE" ]] || { echo "$LOG_PREFIX missing $CNF_FILE" >&2; exit 2; }
[[ "$(stat -c '%a' "$KEY_FILE")" == "600" ]] \
    || { echo "$LOG_PREFIX $KEY_FILE not mode 600" >&2; exit 3; }
command -v gpg >/dev/null    || { echo "missing gpg"; exit 5; }
command -v rclone >/dev/null || { echo "missing rclone"; exit 5; }

mkdir -p "$BACKUP_DIR" "$DUMP_DIR"

# --- Cleanup on error -------------------------------------------------------
trap 'rm -rf "$DUMP_DIR" "$ARCHIVE"; echo "$LOG_PREFIX FAILURE at line $LINENO"' ERR

# --- Dump --------------------------------------------------------------------
echo "$LOG_PREFIX starting dump"
mysqldump --defaults-file="$CNF_FILE" \
    --all-databases --single-transaction --routines --triggers --events \
    > "$DUMP_DIR/all-databases.sql"

# --- Archive + compress -----------------------------------------------------
tar czf "$ARCHIVE" -C "$BACKUP_DIR" "dump_$TIMESTAMP"
rm -rf "$DUMP_DIR"

# --- Encrypt ----------------------------------------------------------------
gpg --batch --symmetric --cipher-algo AES256 \
    --passphrase-file "$KEY_FILE" \
    -o "$ENCRYPTED" "$ARCHIVE"
rm "$ARCHIVE"

SIZE=$(stat -c%s "$ENCRYPTED")
echo "$LOG_PREFIX encrypted $SIZE bytes"

# --- Upload -----------------------------------------------------------------
rclone copy "$ENCRYPTED" "$REMOTE/" --log-level=INFO

# --- Prune ------------------------------------------------------------------
find "$BACKUP_DIR" -name '*.gpg' -mtime +$LOCAL_RETENTION_DAYS -delete
rclone delete "$REMOTE/" --min-age ${REMOTE_RETENTION_DAYS}d \
    --include '*.gpg' --drive-use-trash=false

echo "$LOG_PREFIX SUCCESS $SIZE bytes uploaded to $REMOTE"
```

Install:

```bash
sudo install -m 0700 mysql-backup.sh /usr/local/sbin/mysql-backup.sh
sudo chmod 600 ~/.backup-encryption-key ~/.mysql-backup.cnf

# Test manually first
sudo /usr/local/sbin/mysql-backup.sh

# Then schedule
sudo tee /etc/cron.d/mysql-backup > /dev/null <<'EOF'
MAILTO=ops@example.com
0 2 * * * root /usr/local/sbin/mysql-backup.sh >> /var/log/linux-skills/mysql-backup.log 2>&1
EOF
```

---

## Sources

- Book: *Linux System Administration for the 2020s* — backup discipline and
  restore rehearsal as first-class operations.
- Book: *Mastering Ubuntu* (Atef, 2023) — `mysqldump`, `pg_dump`, `rsync`,
  `tar` backup recipes.
- Book: *Ubuntu Server Guide* (Canonical) — `duplicity` and `rsnapshot`
  chapters for alternative approaches.
- Book: *Wicked Cool Shell Scripts* — the script skeleton and retention
  patterns.
- rclone docs: https://rclone.org/docs/
- Man pages: `mysqldump(1)`, `pg_dump(1)`, `tar(1)`, `gpg(1)`, `cron(8)`,
  `systemd.timer(5)`.
