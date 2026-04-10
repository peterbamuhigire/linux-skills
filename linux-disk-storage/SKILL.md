---
name: linux-disk-storage
description: Manage disk space on Ubuntu/Debian servers. Check usage, find space hogs, safe cleanup (apt cache, journal, old logs, old backups, node_modules), inode exhaustion, and emergency disk-full recovery. Includes swapfile creation for servers running without swap.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Disk & Storage

**This skill is self-contained.** Every command below is a standard
Ubuntu/Debian tool. The `sk-*` scripts in the **Optional fast path** section
are convenience wrappers — never required.

## Check Usage

```bash
df -h                           # filesystem overview (concern: > 85% used)
df -i                           # inode usage (can be full independently)
du -sh /var/www/* | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10
du -sh ~/backups/* 2>/dev/null | sort -rh | head -5
sudo find / -type f -size +100M 2>/dev/null | head -10
```

---

## Safe Cleanup (In Order Of Safety)

```bash
# 1. APT cache (always safe)
sudo apt clean && sudo apt autoremove

# 2. Journal logs (safe, keeps recent 14 days)
sudo journalctl --vacuum-time=14d
sudo journalctl --vacuum-size=500M

# 3. Old backup files (verify retention script is running first)
find ~/backups/mysql/ -name "*.gpg" -mtime +7 -delete

# 4. Temp files
sudo find /tmp /var/tmp -type f -mtime +7 -delete

# 5. node_modules after successful Astro build
# cd /var/www[/html]/<site> && rm -rf node_modules
# (update-all-repos will reinstall on next pull)
```

---

## Emergency Disk Full

```bash
# Fast identification
df -h && du -sh /var/www/* /var/log/* ~/backups/* 2>/dev/null | sort -rh | head -10

# Immediate wins (safe):
sudo apt clean
sudo journalctl --vacuum-size=200M
sudo find /tmp /var/tmp -type f -mtime +7 -delete

# Truncate an oversize log (safer than deleting):
sudo truncate -s 0 /var/log/<oversize-log-file>
```

---

## Inode Exhaustion (df -i shows 100%)

```bash
# Find dir with most files:
sudo find / -xdev -type f 2>/dev/null | cut -d/ -f2 | sort | uniq -c | sort -rn | head

# Common causes: PHP sessions, mail spool, tiny cache files
sudo find /var/lib/php/sessions/ -type f | wc -l
sudo find /tmp -type f | wc -l
```

---

## Swapfile (Safety Net For No-Swap Servers)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-swappiness.conf
sudo sysctl vm.swappiness=10
free -h                   # verify Swap shows 2G
```

Full cleanup targets and LVM reference: `references/storage-reference.md`

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-disk-storage` installs:

| Task | Fast-path script |
|---|---|
| Top 20 consumers by dir/file | `sudo sk-disk-hogs [/path]` |
| Interactive cleanup with preview | `sudo sk-disk-cleanup` |
| Inode exhaustion detector | `sudo sk-inode-check` |

These are optional wrappers around the commands above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-disk-storage
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-disk-hogs | scripts/sk-disk-hogs.sh | yes | Top 20 directories/files by size under a path; warns on `/var/log` and `/tmp` bloat. |
| sk-disk-cleanup | scripts/sk-disk-cleanup.sh | no | Interactive cleanup: apt cache, journal, old logs, kernel images, tmp. Shows bytes reclaimed. |
| sk-inode-check | scripts/sk-inode-check.sh | no | Find filesystems nearing inode exhaustion; top directories by inode count. |
