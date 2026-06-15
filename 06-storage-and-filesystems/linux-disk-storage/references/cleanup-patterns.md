# Disk Cleanup Patterns

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

A menu of safe-to-risky cleanup patterns for a Ubuntu/Debian web
server whose disk is filling up. Each pattern is annotated with a
**risk level**, the bytes it can realistically reclaim, and the
command to run. Patterns are ordered safest first — start at the top
and work down until you have enough free space. The last section
covers emergency recovery when the disk is at 100% and you can barely
SSH in.

Risk levels used throughout:

- **SAFE** — no data loss, no service impact. Always fine.
- **LOW** — trivial side effects (e.g. older logs gone, user history
  truncated).
- **MEDIUM** — requires you know what you're doing; may affect running
  services.
- **HIGH** — destructive if misapplied; only under emergency, with a
  backup ready.

## Table of contents

1. APT package cache and autoremove — SAFE
2. Journald vacuum — SAFE
3. `/tmp` and `/var/tmp` age-based deletion — SAFE
4. Old kernel images — LOW
5. Docker image/volume pruning — LOW to MEDIUM
6. PHP session files — LOW
7. Mail spool buildup — LOW
8. Log files: truncate, don't `rm` — LOW
9. `node_modules` after a successful build — LOW
10. Astro / Vite / Next build caches — LOW
11. Old backup files (respect retention) — MEDIUM
12. Application upload temp directories — MEDIUM
13. Emergency recovery: disk at 100% — HIGH
14. Sources

---

## 1. APT package cache and autoremove — SAFE

**What it does.** Removes downloaded `.deb` files from
`/var/cache/apt/archives/` and uninstalls packages that were pulled in
as dependencies but are no longer needed.

**Risk.** SAFE. The cache is nothing but a local copy of upstream
packages that can be re-downloaded at any time.

**Typical reclaim.** 200 MB – 2 GB on a long-running server.

```bash
# Inspect first — how much is cached?
du -sh /var/cache/apt/

# The cleanup
sudo apt clean                  # empty /var/cache/apt/archives
sudo apt autoclean              # only removes obsolete versions
sudo apt autoremove              # uninstall orphaned dependencies
sudo apt autoremove --purge      # also drop their config files
```

`apt clean` and `apt autoremove` are the first things to run. Always.

---

## 2. Journald vacuum — SAFE (loses history)

**What it does.** Deletes old systemd-journald log data.

**Risk.** SAFE for the system. The only trade-off is that you lose
journal history older than the retention window — you cannot look at
`journalctl -u nginx --since "3 weeks ago"` any more if you vacuumed
to 14 days.

**Typical reclaim.** Often enormous. On a web server with default
settings, `/var/log/journal` regularly reaches 4 GB – 8 GB.

```bash
# Inspect first
sudo du -sh /var/log/journal/
sudo journalctl --disk-usage

# Reduce to a time window
sudo journalctl --vacuum-time=14d     # keep 14 days of logs
sudo journalctl --vacuum-time=7d
sudo journalctl --vacuum-time=2d      # aggressive

# Reduce to a total size
sudo journalctl --vacuum-size=500M
sudo journalctl --vacuum-size=200M    # aggressive
```

Make the limit permanent by editing `/etc/systemd/journald.conf`:

```
[Journal]
SystemMaxUse=500M
MaxFileSec=1week
```

Then `sudo systemctl restart systemd-journald`.

---

## 3. `/tmp` and `/var/tmp` age-based deletion — SAFE

**What it does.** Removes files that haven't been touched in N days
from the two standard temp locations.

**Risk.** SAFE when `-mtime` is generous (7 days or more). `MEDIUM`
if you drop to same-day deletion on a server that uses `/tmp` for
session data.

**Typical reclaim.** Varies wildly. Suspect a lot when PHP, media
conversion, or build tools have crashed mid-run.

```bash
# Inspect
sudo du -sh /tmp /var/tmp
sudo find /tmp /var/tmp -type f -printf '%s %p\n' | sort -rn | head -10

# Standard safe cleanup
sudo find /tmp /var/tmp -type f -mtime +7 -delete
sudo find /tmp /var/tmp -type d -empty -mtime +7 -delete

# More aggressive
sudo find /tmp -type f -mtime +2 -delete
```

Note: Ubuntu's `systemd-tmpfiles` already cleans `/tmp` on a schedule
(configurable in `/etc/tmpfiles.d/tmp.conf`). You are usually just
forcing what would happen anyway.

---

## 4. Old kernel images — LOW risk

**What it does.** Removes older kernel packages (`linux-image-*`,
`linux-headers-*`, `linux-modules-*`) that were superseded by apt
upgrades.

**Risk.** LOW. The danger is accidentally removing the **currently
running** kernel, which will prevent booting. `apt autoremove` will
not do that — but always check first.

**Typical reclaim.** 150 MB – 1 GB.

```bash
# Know your currently running kernel — never remove this one
uname -r

# What's installed
dpkg --list 'linux-image-*' 'linux-headers-*' | grep '^ii'

# What apt considers orphaned kernel packages
apt list --installed 2>/dev/null | grep -E "^linux-(image|headers|modules)" | head

# The safe cleanup
sudo apt autoremove --purge
```

`apt autoremove --purge` is always the right command. Do not manually
`dpkg -r linux-image-*` without matching the exact package to what
you saw in `dpkg --list`.

---

## 5. Docker image/volume pruning — LOW to MEDIUM risk

**What it does.** Removes unused Docker artifacts: stopped containers,
dangling images, unused networks, build cache, and optionally all
unused images and volumes.

**Risk.** LOW for dangling images. MEDIUM for `-a` (removes all images
without a running container). HIGH if you add `--volumes` without
understanding what data lives on them.

**Typical reclaim.** Routinely 2 GB – 20 GB on a dev box.

```bash
# Inspect first
docker system df
docker system df -v           # detailed

# Levels of aggression

# 1. Safest: dangling only
docker image prune

# 2. Stopped containers, dangling images, unused networks, build cache
docker system prune

# 3. Also remove all images not used by any container
docker system prune -a

# 4. DANGER: also remove all unused volumes — this deletes data
docker system prune -a --volumes
```

Before running with `--volumes`, list volumes and understand which
might hold application data (database dumps, config persistence):

```bash
docker volume ls
docker volume inspect <name>
```

---

## 6. PHP session files — LOW risk

**What it does.** Deletes old PHP session files from
`/var/lib/php/sessions/` (the default on Ubuntu).

**Risk.** LOW if you delete files older than `session.gc_maxlifetime`
(default 1440 seconds = 24 minutes). HIGHER if you delete sessions
younger than that — logged-in users may be thrown to the login page.

**Typical reclaim.** Usually small in bytes but can be **massive** in
inode count. The #1 cause of inode exhaustion on a PHP server.

```bash
# Inspect
sudo find /var/lib/php/sessions -type f | wc -l
sudo du -sh /var/lib/php/sessions

# Safe: delete sessions older than an hour
sudo find /var/lib/php/sessions -type f -mmin +60 -delete

# More aggressive on a stuffed box: older than 10 minutes
sudo find /var/lib/php/sessions -type f -mmin +10 -delete
```

Fix the root cause: configure PHP to garbage-collect sessions itself
by setting `session.gc_probability` high enough in `php.ini` (Debian
uses a cron at `/etc/cron.d/php` that handles this, but it can be
disabled).

---

## 7. Mail spool buildup — LOW risk

**What it does.** Clears a stuck Postfix deferred queue and old root
mail.

**Risk.** LOW. You lose deferred mail that was queued for delivery,
which is usually bounce notifications or monitoring alerts. If the
queue is full, mail is almost certainly failing anyway.

**Typical reclaim.** Varies. Can be severe when `MAILTO=root` is set
on a chatty cron and there is no MTA — root's mailbox balloons into
gigabytes.

```bash
# Inspect
sudo du -sh /var/spool/postfix /var/mail /var/spool/mail
sudo postqueue -p | tail          # view the queue (if postfix is installed)

# Clean root's mailbox (as root)
sudo sh -c '> /var/mail/root'     # or /var/spool/mail/root depending on distro
sudo truncate -s 0 /var/mail/root # equivalent

# Delete deferred postfix mail older than 1 day
sudo find /var/spool/postfix/deferred -type f -mtime +1 -delete

# Flush the queue (try delivery)
sudo postqueue -f
```

Fix the root cause: either install and configure a working MTA (msmtp
is enough on a non-mail server), or add `MAILTO=""` at the top of
crontabs where you don't care about output.

---

## 8. Log files: truncate, don't `rm` — LOW risk

**What it does.** Empties the contents of a log file while keeping
the file handle intact.

**Risk.** LOW if done correctly. HIGH if you use the wrong tool — see
below.

**Typical reclaim.** Whatever the log file grew to.

### Why `truncate` and not `rm`

On Linux, when a process has an open file descriptor to a log, and you
`rm` the log, the filename goes away immediately but the **disk space
is not freed** until the process closes the FD (i.e. restarts). You
"deleted" the file but the bytes are still held by the kernel. Running
`df -h` shows no change.

This is the #1 "I deleted the log but disk is still full" trap.

### The right ways

```bash
# CORRECT: keeps the FD intact, frees the space immediately
sudo truncate -s 0 /var/log/nginx/access.log

# ALSO CORRECT: same effect, different syntax
sudo sh -c '> /var/log/nginx/access.log'

# ALSO CORRECT but slightly different
sudo : > /var/log/nginx/access.log      # as root in current shell

# WRONG: frees nothing until nginx restarts
sudo rm /var/log/nginx/access.log
```

### Recovering after the fact

If you already ran `rm` on an open log:

```bash
# Find processes holding deleted files
sudo lsof +L1 2>/dev/null | head

# Restart the service that owns the deleted FD
sudo systemctl restart nginx
```

The space comes back the moment the FD closes.

### Batch operation

```bash
# Truncate every nginx log in one go
sudo find /var/log/nginx -type f -name "*.log" -exec truncate -s 0 {} \;
```

---

## 9. `node_modules` after a successful build — LOW risk

**What it does.** Deletes `node_modules/` from a project that has
already been built into a `dist/` or `build/` directory.

**Risk.** LOW if you are sure the build is done and production is
serving the build output, not the live source. If your `package.json`
is intact, `node_modules` can always be recreated with `npm ci`.

**Typical reclaim.** 200 MB – 1.5 GB per project. Adds up fast.

```bash
# Inspect
sudo du -sh /var/www/*/node_modules 2>/dev/null

# Delete — safe pattern when deploy is "build then serve dist/"
cd /var/www/<site>
npm run build                   # confirm build works
rm -rf node_modules

# Restore when you need it again
npm ci                          # faster than npm install, respects lockfile
```

**Don't** delete `node_modules` from an Astro/Next dev project that is
currently under active development — you'll just reinstall in 30
seconds. Only do this on built-and-deployed projects that are idle.

---

## 10. Astro / Vite / Next build caches — LOW risk

**What it does.** Removes framework build caches that exist to speed
up rebuilds.

**Risk.** LOW. Next rebuild takes longer; output is identical.

**Typical reclaim.** 50 MB – 500 MB per project.

```bash
# Astro
rm -rf /var/www/<site>/.astro
rm -rf /var/www/<site>/dist          # only if you will rebuild

# Vite
rm -rf /var/www/<site>/node_modules/.vite

# Next.js
rm -rf /var/www/<site>/.next/cache   # leave .next/ itself for runtime

# TypeScript incremental build
find /var/www -name "*.tsbuildinfo" -delete

# General "clean and rebuild"
cd /var/www/<site>
rm -rf node_modules .astro .next dist build
npm ci
npm run build
```

---

## 11. Old backup files (respect retention) — MEDIUM risk

**What it does.** Deletes backup archives older than your declared
retention window.

**Risk.** MEDIUM. You **must** know your retention policy. Deleting
backups without checking the remote copy is how you lose everything.

**Typical reclaim.** Whatever your backups weigh.

### The rules

1. **Never delete a local backup unless you have verified the remote
   copy exists.** Check rclone, S3, B2 — whatever the off-site target
   is.
2. **Never delete the most recent backup**, even if "old." It's the
   one you will reach for first in an incident.
3. **Respect 3-2-1**: 3 copies, 2 media, 1 off-site. See
   `linux-disaster-recovery/references/backup-strategy.md`.

### Patterns

```bash
# Inspect
ls -lth ~/backups/mysql/ | head
sudo du -sh ~/backups/*

# Confirm remote copies exist BEFORE deleting local
rclone ls gdrive:<backup-folder> | sort | tail

# MySQL: keep 7 days of local
find ~/backups/mysql -name "*.gpg" -mtime +7 -delete

# Site files: keep 14 days of local
find ~/backups/sites -name "*.tar.gz.gpg" -mtime +14 -delete

# Keep last N, delete the rest (count-based retention)
ls -1t ~/backups/mysql/*.gpg | tail -n +8 | xargs -r rm -v
```

Always test retention on a throwaway directory before trusting it
against your real backup vault.

---

## 12. Application upload temp directories — MEDIUM risk

**What it does.** Cleans up orphaned upload temp files left by a web
application that crashed mid-upload.

**Risk.** MEDIUM. You need to know which app owns which directory, and
that it does not need the file right now. An in-progress upload will
fail if you delete its temp file while the user is uploading.

**Typical reclaim.** Varies. On a media-heavy site, can be huge.

```bash
# Find candidates — look for named temp dirs under /var/www
sudo du -sh /var/www/*/tmp /var/www/*/storage/tmp \
           /var/www/*/uploads/tmp 2>/dev/null | sort -rh

# Common PHP upload temp (set by upload_tmp_dir in php.ini)
sudo find /var/lib/php/uploads -type f -mmin +60 -delete 2>/dev/null

# Laravel storage
sudo find /var/www/<site>/storage/framework/cache -type f -mtime +1 -delete
sudo find /var/www/<site>/storage/framework/sessions -type f -mmin +60 -delete
sudo find /var/www/<site>/storage/framework/views -type f -mtime +1 -delete
```

Always use `-mmin` / `-mtime` thresholds, never blanket `-delete`.

---

## 13. Emergency recovery: disk at 100%

**Scenario.** `df -h` shows 100%. Services are failing. You can SSH in
but new sessions may hang on `/var/log/wtmp`. Some systemd units have
already failed.

**Risk level.** HIGH. Move deliberately.

### Sequence

Run each step only if the previous didn't reclaim enough.

```bash
# Step 0 — confirm and measure
df -h -x tmpfs -x devtmpfs
```

```bash
# Step 1 — empty apt cache (SAFE, instant)
sudo apt clean
```

```bash
# Step 2 — vacuum journald aggressively
sudo journalctl --vacuum-size=100M
sudo du -sh /var/log/journal
```

```bash
# Step 3 — find the biggest files
sudo du -sh /var/log/* /var/lib/* /var/www/* 2>/dev/null | sort -rh | head -20
sudo find / -xdev -type f -size +500M -printf '%s %p\n' 2>/dev/null \
    | sort -rn | head -20
```

```bash
# Step 4 — truncate oversize logs without deleting them
sudo truncate -s 0 /var/log/nginx/access.log
sudo truncate -s 0 /var/log/nginx/error.log
sudo truncate -s 0 /var/log/apache2/*.log
sudo truncate -s 0 /var/log/mysql/error.log
sudo truncate -s 0 /var/log/syslog
# Find the biggest log
sudo find /var/log -type f -size +100M \
    -exec truncate -s 0 {} \; -print
```

```bash
# Step 5 — old tmp files
sudo find /tmp /var/tmp -type f -mtime +1 -delete
```

```bash
# Step 6 — deleted-but-held files (recover space from old rm)
sudo apt install -y lsof >/dev/null 2>&1
sudo lsof +L1 2>/dev/null | head
# If any show up, restart that service to release the space:
sudo systemctl restart <service>
```

```bash
# Step 7 — old kernels and orphaned packages
sudo apt autoremove --purge
```

```bash
# Step 8 — confirm
df -h
```

### The "cannot SSH in" scenario

If disk is so full that even SSH login fails:

1. Try the console (cloud provider web console, IPMI, or physical
   keyboard).
2. Once at a shell, run the same sequence above starting with
   `sudo journalctl --vacuum-size=50M` and `sudo apt clean`.
3. On some cloud providers, rebooting into rescue mode gives you a
   clean shell against the same disk.

### What NOT to do

- **Do not** `rm -rf /var/log/*`. You break services that are writing
  to live logs, and you often lose evidence of why the disk filled up.
- **Do not** delete files out of `/var/lib/mysql/`. You will corrupt
  the database.
- **Do not** delete files out of `/var/lib/dpkg/` or
  `/var/lib/apt/lists/`. You will break apt.
- **Do not** delete files out of `/boot/` without understanding exactly
  what each one is. The next reboot will fail.
- **Do not** trust `du` output that's cut off at 0 bytes on files you
  know are big — that's the "deleted-but-held" symptom. Use
  `lsof +L1`.
- **Do not** `rm` an active log and assume space comes back. Use
  `truncate -s 0` instead.

---

## Sources

- **Ubuntu Server Guide (Focal 20.04)**, Canonical (2020) — journald,
  apt cache, and default log rotation behaviour.
- **Mastering Ubuntu**, Ghada Atef (2023) — disk usage and cleanup
  chapter.
- **Linux System Administration for the 2020s** — production
  incident playbook for disk-full events.
- **Wicked Cool Shell Scripts**, Dave Taylor & Brandon Perry — shell
  scripts for inode and disk monitoring.
- `systemd-journald.conf(5)`, `logrotate(8)`, `apt(8)`, `find(1)`,
  `truncate(1)`, `lsof(8)`, `docker-system-prune(1)` man pages.
- Real-world disk-full incidents on production Ubuntu/Debian web
  servers.
