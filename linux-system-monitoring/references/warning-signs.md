# Warning Signs on a Production Ubuntu Server

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This reference lists the symptoms that a production Ubuntu/Debian server
is about to have (or is already having) a bad day — and the exact command
to confirm each symptom plus the first remediation step. Use it as a
checklist after a user report, a page, or during a regularly-scheduled
health sweep.

Every command is stock Ubuntu/Debian. The `sk-*` scripts from
`SKILL.md` are optional convenience wrappers — not required.

## Table of contents

1. Load average sustained > 2× cores
2. Load average high with low CPU% (I/O bottleneck)
3. `MemAvailable` < 10% of total
4. Swap use growing
5. `%iowait` sustained > 20%
6. Disk > 85% full
7. Disk > 95% full (emergency)
8. Inode use > 90%
9. fail2ban ban count spiking
10. Unexpected listening port
11. Zombie process count growing
12. systemd failed units
13. OOM-kill in journal
14. Filesystem remounted read-only
15. Time drift (ntp/chrony unhealthy)
16. Too many TCP TIME_WAIT / CLOSE_WAIT
17. Growing `fd` count per process
18. Stuck `D`-state processes
19. Certificate expiry approaching
20. Backup missing / stale
21. Sources

---

## 1. Load average sustained > 2× cores

**Symptom.** `uptime` shows a 5-minute load that is double the core
count, and the 1-minute value is not trending down.

```bash
uptime
nproc
```

**Interpretation.** Run queue is longer than CPUs can serve. Something
is either CPU-pegged or waiting on I/O.

**Confirm CPU vs I/O.**

```bash
vmstat 1 5
# If r > nproc but wa is low        → CPU bottleneck (jump to #1 fix)
# If r is low but wa > 20 sustained → I/O bottleneck (see #2)
```

**First remediation step.**

```bash
top -bn1 -o %CPU | head -20          # who is eating the CPU
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head
```

Kill, renice, or throttle the offending process. If it is a legitimate
service (php-fpm, node, postgres) under load, tune pool sizes or add
capacity. If it is a runaway cron, kill it and fix the job.

---

## 2. Load average high with low CPU% (I/O bottleneck)

**Symptom.** Load is high but `top` shows every core mostly idle. The
`wa` column in vmstat is double-digit sustained.

**Confirm.**

```bash
vmstat 1 5                           # wa (I/O wait) > 20 sustained
iostat -xz 1 5                       # %util > 80, await > 50ms
```

**Find the process.**

```bash
sudo apt install -y iotop >/dev/null 2>&1
sudo iotop -bod 5 -n 3               # batch, only active processes
pidstat -d 1 5                       # per-process I/O
```

**First remediation step.** Identify the culprit:

- A runaway `mysqldump` or backup job → reschedule or add `ionice -c 3`.
- `journald` flushing — check `/var/log/journal` size.
- `apt` or `unattended-upgrades` → wait, or schedule off-peak.
- A legitimate query → `SHOW PROCESSLIST` in MySQL, then kill the bad query.

---

## 3. `MemAvailable` < 10% of total

**Symptom.** `free -h` shows `available` under 10% of `total`, not just
"used" climbing.

**Confirm.**

```bash
free -h
awk '/MemTotal|MemAvailable/ {print $1, $2, $3}' /proc/meminfo
```

**Interpretation.** Low `free` is fine (kernel caches everything it can).
Low `available` is the real alarm — the kernel thinks it cannot
satisfy a new process without reclaiming or swapping.

**First remediation step.**

```bash
ps -eo pid,rss,comm --sort=-rss | head -10
# Or with smem for accurate shared accounting:
sudo apt install -y smem >/dev/null 2>&1
smem -rk -s pss | head
```

Restart or tune the biggest consumer (php-fpm pool, node worker count,
redis maxmemory, mysql innodb_buffer_pool_size). If there is no swap,
create a swapfile as a safety net — see `linux-disk-storage/SKILL.md`.

---

## 4. Swap use growing

**Symptom.** `free -h` shows swap in active use and the number is rising
over time.

**Confirm it is active, not just cold pages.**

```bash
vmstat 1 5
#  si / so > 0 sustained = real paging, real memory pressure
swapon --show
cat /proc/swaps
```

Inactive swap (`si` and `so` stay 0 while `Swap used` is non-zero) is
fine — those are idle pages the kernel evicted long ago.

**First remediation step.** Find who is using swap.

```bash
# Per-process swap use, sorted
for p in /proc/[0-9]*/status; do
    awk '/Name|VmSwap/ {printf "%s ", $2} END {print ""}' $p
done 2>/dev/null | sort -k2 -rn -t' ' | head -10
```

Or with smem:

```bash
smem -rk -s swap | head
```

Restart or resize the worst offender. Keep `vm.swappiness=10` on DB
hosts so the kernel prefers dropping cache before swapping.

---

## 5. `%iowait` sustained > 20%

**Symptom.** `top` header shows `wa` double-digits continuously.

**Confirm + identify device.**

```bash
vmstat 1 5
iostat -xz 1 5                       # look for %util > 80 on a device
```

**First remediation step.**

1. Identify the process with `iotop -bod 5` or `pidstat -d 1 5`.
2. If it's a cron/backup job, `ionice -c 3` (idle class) it.
3. If it's a real workload, the disk is undersized — add capacity or
   move the workload to faster storage.
4. Check SMART health of the underlying device (section 7 of
   `linux-disk-storage/references/storage-reference.md`). Failing disks
   produce high `await`.

---

## 6. Disk > 85% full

**Symptom.** `df -h` shows any mounted filesystem at 85% or higher.

**Confirm.**

```bash
df -h -x tmpfs -x devtmpfs
```

**First remediation step.**

```bash
sudo du -sh /var/log/* /var/www/* ~/backups/* 2>/dev/null | sort -rh | head
sudo apt clean
sudo journalctl --vacuum-time=14d
sudo journalctl --vacuum-size=500M
```

Full safe-cleanup procedure: `linux-disk-storage/references/cleanup-patterns.md`.
Do not delete anything you don't understand — truncate logs with
`sudo truncate -s 0 /path/to/log` instead of `rm`.

---

## 7. Disk > 95% full (emergency)

**Symptom.** `df -h` shows > 95%. Services may already be failing
because they can't write. SSH may still work but new sessions that try
to write to `/var/log/btmp` or `/var/log/wtmp` can hang.

**Confirm.**

```bash
df -h -x tmpfs -x devtmpfs
sudo systemctl --failed
```

**First remediation steps (in order, do not skip).**

```bash
# 1. Reclaim journal immediately
sudo journalctl --vacuum-size=100M

# 2. APT cache
sudo apt clean

# 3. Truncate the biggest log without breaking open FDs
sudo find /var/log -type f -size +500M -printf '%s %p\n' | sort -rn | head
sudo truncate -s 0 /var/log/<oversize-file>

# 4. Old temp files
sudo find /tmp /var/tmp -type f -mtime +3 -delete

# 5. Check for deleted-but-held files (disk won't free until process restarts)
sudo lsof +L1 2>/dev/null | head
```

If `lsof +L1` shows deleted files held open by a process, restart that
process or reboot. Those pages never come back otherwise.

---

## 8. Inode use > 90%

**Symptom.** `df -i` shows `IUse%` at 90%+ on a filesystem. Writes fail
with "No space left on device" even though `df -h` shows space free.

**Confirm + find the culprit directory.**

```bash
df -i
sudo find / -xdev -type f 2>/dev/null | cut -d/ -f2-3 | sort | uniq -c | sort -rn | head
```

**First remediation step.** Common culprits:

```bash
sudo find /var/lib/php/sessions -type f | wc -l
sudo find /var/spool/postfix -type f | wc -l
sudo find /var/spool/mail -type f | wc -l
sudo find /tmp -type f | wc -l
sudo find /var/cache -type f | wc -l
```

Clear the runaway directory. For PHP sessions, tune `session.gc_maxlifetime`
and force a cleanup:

```bash
sudo find /var/lib/php/sessions -type f -mmin +60 -delete
```

---

## 9. fail2ban ban count spiking

**Symptom.** `fail2ban-client status sshd` shows far more banned IPs
than usual, or the jail banlist is growing quickly.

**Confirm.**

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo tail -50 /var/log/fail2ban.log
```

**First remediation step.**

1. Look at the pattern of IPs. Many from one country or subnet →
   active scanner. Widely distributed → likely a real distributed
   attack.
2. Confirm the jail is still catching new attempts (log should show
   recent bans within minutes).
3. If the box is slow because of the volume, tighten `maxretry` and
   `bantime` in the sshd jail, or drop the offending subnet at the
   firewall with `ufw deny from <subnet>`.
4. Rotate SSH keys if you see a successful SSH login from an unexpected
   IP. See `linux-access-control`.

---

## 10. Unexpected listening port

**Symptom.** `ss -tulnp` shows a port listening that nobody enabled.
Could be a misconfigured service, a leftover dev build, or a
compromise.

**Confirm.**

```bash
sudo ss -tulnp
sudo ss -tulnp | grep -vE "nginx|apache2|mysqld|php-fpm|sshd|postgres|redis|systemd-resolved"
```

**First remediation step.**

1. Identify the process: `sudo lsof -i :<port>` or `sudo ss -tulnp | grep :<port>`.
2. If it is a service you recognise but misconfigured (e.g. MySQL
   bound to 0.0.0.0 instead of 127.0.0.1), fix `bind-address` and
   restart.
3. If you do not recognise the process, do **not** simply kill it —
   first preserve evidence:

   ```bash
   sudo ps -o pid,ppid,user,stat,cmd -p <pid>
   sudo lsof -p <pid>
   sudo ls -la /proc/<pid>/exe         # real binary path
   sudo cat /proc/<pid>/environ        # environment at launch
   ```

4. Then treat as a possible compromise — full audit (`linux-security-analysis`),
   key rotation, and restore from a known-good backup if in doubt.

---

## 11. Zombie process count growing

**Symptom.** `top` or `ps` shows many processes in state `Z`.

**Confirm.**

```bash
ps -eo pid,ppid,stat,comm | awk '$3 ~ /Z/ {print}'
ps -eo stat | grep -c '^Z'
```

**First remediation step.** A zombie is a child whose parent has not
called `wait()`. Kill the **parent** (you cannot kill a zombie):

```bash
ps -eo pid,ppid,stat,comm | awk '$3 ~ /Z/ {print $2}' | sort -u
# Then investigate each PPID
```

Restart the parent supervisor (often a buggy application server or
shell script). Growing zombies are a software bug; fix the parent.

---

## 12. systemd failed units

**Symptom.** A service silently dropped. `systemctl --failed` lists it.

**Confirm + inspect.**

```bash
systemctl --failed
systemctl status <unit> -l
journalctl -u <unit> -n 100 --no-pager
```

**First remediation step.**

```bash
# Try a manual restart
sudo systemctl restart <unit>

# Still failing? Test config (web servers):
sudo nginx -t
sudo apache2ctl configtest
sudo php-fpm8.3 -t

# Reset the failed state after the fix:
sudo systemctl reset-failed <unit>
```

If the unit is crash-looping, `systemctl status` shows
`StartLimit` hit — fix the root cause, then reset and restart.

---

## 13. OOM-kill in journal

**Symptom.** The kernel's out-of-memory killer terminated a process to
free RAM. Users may report connection refused; `systemctl status
<service>` may show failure immediately after.

**Confirm.**

```bash
sudo dmesg -T | grep -i "killed process"
sudo journalctl -k | grep -i "out of memory"
sudo journalctl --since "1 hour ago" | grep -iE "oom|killed process"
```

**First remediation step.**

1. Note which process was killed (`Killed process 1234 (mysqld)`).
2. Confirm memory pressure at the time with `sar -r` (section 12 of
   `monitoring-commands.md`).
3. Sizing is wrong — either:
   - Reduce the killed service's memory footprint (cap with
     `MemoryMax=` in a drop-in override, lower pool/worker counts,
     tighten DB buffer pool), or
   - Add RAM / move to a bigger instance, or
   - Add a swapfile as a safety net (`linux-disk-storage/SKILL.md`).
4. Restart the killed service (it usually is not auto-restarted
   unless `Restart=on-failure` is set).

---

## 14. Filesystem remounted read-only

**Symptom.** Any write fails with "Read-only file system." The kernel
has forcibly remounted a filesystem read-only because of I/O errors.

**Confirm.**

```bash
mount | grep -w ro                   # or look in /proc/mounts
dmesg -T | grep -iE "remounting|error|EXT4-fs|XFS"
sudo journalctl -k --since "1 hour ago" | grep -iE "ext4|xfs|i/o error"
```

**First remediation step.**

This is a disk-failure or corruption event. Do **not** try to force it
back to read-write on a live system — you will make it worse.

1. Check SMART health immediately: `sudo smartctl -a /dev/sdX`.
2. Verify backups are current (`ls -lth ~/backups/`).
3. Schedule downtime. Boot from rescue, run `fsck -y /dev/sdX<n>`.
4. Plan a disk replacement if SMART shows failing attributes.

For LVM, check that the physical volume is not marked `missing`:
`sudo pvs`.

---

## 15. Time drift (ntp/chrony unhealthy)

**Symptom.** Clock is skewed — TLS handshakes failing ("certificate not
yet valid"), cron jobs firing at wrong times, MySQL replication lag
reported as huge.

**Confirm.**

```bash
timedatectl status
# Look for: "System clock synchronized: yes" and "NTP service: active"
systemctl status systemd-timesyncd
# Or, if chrony is installed:
chronyc tracking
chronyc sources -v
```

**First remediation step.**

```bash
sudo systemctl restart systemd-timesyncd
# Or for chrony:
sudo systemctl restart chrony
sudo chronyc makestep              # force a one-shot correction
```

Confirm the box can actually reach its NTP servers (UDP 123). If not,
the firewall or upstream is blocking — check `ufw status` and `ss -u
-lnp`.

---

## 16. Too many TCP TIME_WAIT / CLOSE_WAIT

**TIME_WAIT** (normal).

```bash
ss -tan state time-wait | wc -l
```

On busy web servers, thousands of TIME_WAITs are expected. Only a
problem if you're running out of ephemeral ports — check
`cat /proc/sys/net/ipv4/ip_local_port_range`.

**CLOSE_WAIT** (the scary one).

```bash
ss -tan state close-wait
ss -tan state close-wait | wc -l
```

A growing CLOSE_WAIT count means the **local** application has not
called `close()` on its sockets. It is an application bug (forgotten
`close`, exception path not cleaning up). The sockets pile up, eventually
exhausting file descriptors.

**First remediation step.** Restart the offending service as a
band-aid, then file a bug for the dev team — CLOSE_WAIT does not
resolve itself.

---

## 17. Growing `fd` count per process

**Symptom.** A long-running process slowly consumes more and more file
descriptors until it hits its `LimitNOFILE=` ceiling and starts throwing
"Too many open files."

**Confirm.**

```bash
# Top FD users
for p in $(ps -eo pid= | head -200); do
    count=$(ls /proc/$p/fd 2>/dev/null | wc -l)
    [ "$count" -gt 100 ] && echo "$count $(cat /proc/$p/comm 2>/dev/null) $p"
done | sort -rn | head

# Effective limit for a specific process
cat /proc/<pid>/limits | grep "open files"
```

**First remediation step.**

1. If it's a legitimate high-FD workload (nginx front-ending a lot of
   upstreams), raise `LimitNOFILE=` in a systemd drop-in:

   ```ini
   [Service]
   LimitNOFILE=100000
   ```

2. If it's a leak, restart the process as a band-aid and file a bug.

---

## 18. Stuck `D`-state processes

**Symptom.** `ps` shows one or more processes stuck in state `D`
(uninterruptible sleep). You cannot kill them even with `SIGKILL`.

**Confirm.**

```bash
ps aux | awk '$8 ~ /D/ {print}'
```

**Interpretation.** `D` state means the process is in a kernel call
that cannot be interrupted — almost always waiting for I/O from a
block device or NFS mount that is not responding.

**First remediation step.**

1. `sudo dmesg -T | tail -50` — look for I/O errors, NFS timeouts,
   USB storage unplugged.
2. If an NFS mount is hung, fix the NFS server or `umount -f -l <mp>`.
3. If a local disk is failing, you will likely need to reboot. Plan
   a disk replacement.

---

## 19. Certificate expiry approaching

**Symptom.** A TLS cert is within 14 days of expiry and has not auto-renewed.

**Confirm.**

```bash
sudo certbot certificates             # shows each cert, expiry, renewal status
sudo systemctl status certbot.timer
sudo systemctl list-timers | grep certbot
```

**First remediation step.**

```bash
sudo certbot renew --dry-run           # validate renewal path
sudo certbot renew                     # actually renew
sudo systemctl reload nginx apache2    # pick up new cert
```

If renewal fails, check the ACME HTTP-01 challenge path — usually an
nginx rewrite rule is intercepting `.well-known/acme-challenge/`.

---

## 20. Backup missing / stale

**Symptom.** The most recent backup file is older than expected, or
absent entirely.

**Confirm.**

```bash
ls -lth ~/backups/mysql/*.gpg 2>/dev/null | head -5
find ~/backups -name "*.gpg" -mtime -1 | wc -l   # backups in last 24h
# If using rclone to gdrive:
rclone ls gdrive:<folder> 2>/dev/null | sort | tail -5
```

**First remediation step.**

1. Check the backup job ran:

   ```bash
   sudo journalctl -u <backup-unit> --since "2 days ago" --no-pager
   sudo grep -i backup /var/log/syslog | tail
   ```

2. Common failure modes:
   - Disk was full when the job ran → fix disk, re-run job manually.
   - GPG passphrase file was missing or corrupted.
   - rclone token expired → `rclone config reconnect gdrive:`.
   - The cron fired but the script exited early with no error because
     stderr was discarded — drop the `2>&1 > /dev/null` trick and log
     properly.
3. Run the backup manually once the root cause is fixed.
4. Verify the restore still works (see
   `linux-disaster-recovery/references/backup-strategy.md` on restore
   rehearsals).

---

## Sources

- **Ubuntu Server Guide (Focal 20.04)**, Canonical (2020) — default
  monitoring defaults, systemd-timesyncd, journalctl.
- **Mastering Ubuntu**, Ghada Atef (2023) — monitoring and
  troubleshooting chapters.
- **Linux System Administration for the 2020s** — production incident
  patterns; the "disk full cascade" and "OOM kill story" examples.
- **Wicked Cool Shell Scripts**, Dave Taylor & Brandon Perry — the
  "watch for warning signs" family of admin scripts.
- `proc(5)`, `systemd-journald(8)`, `fail2ban(1)`, `systemctl(1)` man
  pages.
- Real incident post-mortems on production Ubuntu 20.04 / 22.04 servers.
