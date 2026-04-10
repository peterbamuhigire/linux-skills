# systemd Timers and cron

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

A production Ubuntu/Debian server has two ways to run scheduled jobs:
the classic `cron` daemon and systemd timers. Both work. This reference
explains both, shows when to pick which, gives copy-pasteable templates,
and walks through converting a cron entry to a systemd timer.

## Table of contents

1. Choosing between cron and systemd timers
2. systemd timers: the minimum you need to know
3. Writing a timer unit + paired service unit
4. Timer calendar syntax (`OnCalendar=`)
5. Inspecting timers
6. cron fundamentals
7. Cron table syntax
8. Cron environment gotchas (PATH, locale, MAILTO)
9. Cron logging and debugging
10. anacron — cron for machines that sleep
11. `run-parts` and the `/etc/cron.*` directories
12. Worked example: converting a cron job to a systemd timer
13. Sources

---

## 1. Choosing between cron and systemd timers

Both are fine. Pick based on these criteria:

| Criterion                                       | cron      | systemd timer |
|--------------------------------------------------|-----------|---------------|
| Simple "every hour, run a script"                | Best      | Overkill      |
| Already have a systemd service for the job      | Fine      | Best          |
| Need to see logs via `journalctl -u <unit>`    | No        | Yes           |
| Need resource limits (CPU, mem cgroup)          | No        | Yes           |
| Need sandboxing (ProtectSystem, PrivateTmp)     | No        | Yes           |
| Need to run "5 minutes after boot"              | `@reboot` | `OnBootSec=`  |
| Need to run "10 minutes after the last run"     | No        | `OnUnitActiveSec=` |
| Need to catch missed runs after downtime        | anacron   | `Persistent=true` |
| Need randomised jitter to avoid thundering herds| No        | `RandomizedDelaySec=` |
| Widest toolchain familiarity                     | Yes       | Less so       |

Rule of thumb on the servers this repo manages: use **cron** for short
shell scripts the operator writes (backups, `update-all-repos`, SSL renew
checks). Use **systemd timers** when you already have a service unit
and want to run it on a schedule (e.g. `certbot.timer`, `apt-daily.timer`).

---

## 2. systemd timers: the minimum you need to know

A systemd timer is **two** units:

1. A `.timer` unit that defines *when* it fires.
2. A matching `.service` unit that defines *what* runs. By convention
   the service has the **same basename** as the timer.

Example: `backup-mysql.timer` triggers `backup-mysql.service`.

Enable + start a timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now backup-mysql.timer
```

You do **not** `start` the `.service` — the timer does that. You enable
and start the `.timer`.

---

## 3. Writing a timer unit + paired service unit

Save the service at `/etc/systemd/system/backup-mysql.service`:

```ini
[Unit]
Description=MySQL backup job
After=network-online.target mysql.service
Wants=network-online.target

[Service]
Type=oneshot
User=root
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
ExecStart=/usr/local/bin/backup-mysql.sh
StandardOutput=journal
StandardError=journal

# Sandboxing — still useful for scheduled jobs
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
ReadWritePaths=/root/backups /var/log/backup-mysql
NoNewPrivileges=yes
```

Save the timer at `/etc/systemd/system/backup-mysql.timer`:

```ini
[Unit]
Description=Run MySQL backup job daily at 02:30
Documentation=man:systemd.timer(5)

[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=10min
Persistent=true
Unit=backup-mysql.service

[Install]
WantedBy=timers.target
```

Key points:

- `Type=oneshot` in the service — it runs once and exits, no PID to track.
- `Persistent=true` — if the machine was off at 02:30, the job runs at
  next boot instead of being missed (anacron behaviour).
- `RandomizedDelaySec=` — spread out load across a fleet.
- The timer is `WantedBy=timers.target`, not `multi-user.target`.

Activate:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now backup-mysql.timer
systemctl list-timers --all | grep backup-mysql
```

Run the service once, by hand, without waiting:

```bash
sudo systemctl start backup-mysql.service
sudo journalctl -u backup-mysql.service -n 50 --no-pager
```

---

## 4. Timer calendar syntax (`OnCalendar=`)

`OnCalendar=` uses a shorthand `systemd.time(7)` calendar spec:

```
DayOfWeek Year-Month-Day Hour:Minute:Second
```

| Spec                             | Meaning                                      |
|----------------------------------|----------------------------------------------|
| `minutely`                       | Every minute.                                |
| `hourly`                         | Every hour at minute 0.                      |
| `daily`                          | Every day at 00:00.                          |
| `weekly`                         | Every Monday at 00:00.                       |
| `monthly`                        | First of every month at 00:00.               |
| `yearly`                         | 1 Jan at 00:00.                              |
| `*-*-* 02:30:00`                 | Every day at 02:30.                          |
| `Mon *-*-* 03:00:00`             | Mondays at 03:00.                            |
| `Mon..Fri 09:00`                 | Weekdays at 09:00.                           |
| `*-*-01 04:00:00`                | First of every month at 04:00.               |
| `*-*-* 00/4:00:00`               | Every 4 hours starting at 00:00.             |
| `*-*-* *:0/15:00`                | Every 15 minutes.                            |
| `2025-01-01 00:00:00`            | Exactly once.                                |

Validate a spec before committing:

```bash
systemd-analyze calendar "Mon..Fri 09:00"
# Output shows: Next elapse: the actual next time it will fire.
systemd-analyze calendar "*-*-* 00/4:00:00" --iterations=5
```

### Monotonic triggers (not calendar-based)

| Directive            | Meaning                                                  |
|----------------------|----------------------------------------------------------|
| `OnBootSec=5min`     | Fire 5 minutes after boot.                               |
| `OnStartupSec=2min`  | Fire 2 minutes after systemd itself started.             |
| `OnActiveSec=30s`    | Fire 30 seconds after the timer was activated.           |
| `OnUnitActiveSec=1h` | Fire 1 hour after the paired service last went active.  |
| `OnUnitInactiveSec=10min` | Fire 10 minutes after the service last went inactive.|

You can combine `OnBootSec=` and `OnUnitActiveSec=` to get "first run 5
minutes after boot, then every 10 minutes."

### Other useful `[Timer]` directives

| Directive              | Meaning                                                   |
|------------------------|-----------------------------------------------------------|
| `Persistent=true`      | Catch-up on missed calendar runs after downtime.          |
| `RandomizedDelaySec=`  | Add random jitter up to the given duration.               |
| `FixedRandomDelay=true`| Jitter value is stable per-unit (predictable across reboots). |
| `AccuracySec=1min`     | How precisely systemd tries to fire. Default 1min saves power.|
| `WakeSystem=true`      | Wake the system from suspend to fire. Laptops.            |
| `Unit=other.service`   | Trigger a service whose name doesn't match the timer.     |

---

## 5. Inspecting timers

```bash
systemctl list-timers                        # active timers, sorted by next run
systemctl list-timers --all                  # include inactive
systemctl list-timers --all --no-pager
systemctl status backup-mysql.timer          # state + next/last run
systemctl cat backup-mysql.timer             # unit + drop-ins
journalctl -u backup-mysql.service --since today
```

The `list-timers` output columns are: `NEXT`, `LEFT`, `LAST`, `PASSED`,
`UNIT`, `ACTIVATES`. Any timer showing `n/a` under `LAST` has never fired
— that usually means it just got enabled, or something is wrong with the
calendar spec.

Trigger the paired service manually, without waiting for the schedule:

```bash
sudo systemctl start backup-mysql.service
```

---

## 6. cron fundamentals

The classic cron daemon on Ubuntu/Debian is `vixie-cron` (package `cron`,
unit `cron.service`). It reads several tables:

| Location                         | Purpose                                                 |
|----------------------------------|---------------------------------------------------------|
| `/etc/crontab`                   | System-wide crontab. Includes a `user` field.           |
| `/etc/cron.d/*`                  | Drop-in system crontabs. One file per package/admin job. |
| `/etc/cron.hourly/*`             | Scripts run hourly, executed via `run-parts`.           |
| `/etc/cron.daily/*`              | Scripts run daily.                                      |
| `/etc/cron.weekly/*`             | Scripts run weekly.                                     |
| `/etc/cron.monthly/*`            | Scripts run monthly.                                    |
| `/var/spool/cron/crontabs/<user>`| Per-user crontabs (managed via `crontab -e`).           |

Commands:

```bash
crontab -l                                   # list current user's crontab
crontab -e                                   # edit (opens $EDITOR)
crontab -r                                   # remove current user's crontab
sudo crontab -l -u www-data                  # list another user's crontab
sudo crontab -e -u www-data                  # edit another user's crontab
```

Control the daemon:

```bash
sudo systemctl status cron
sudo systemctl restart cron
sudo systemctl enable cron                   # should already be enabled
```

---

## 7. Cron table syntax

User crontabs (`crontab -e`) have **5 time fields + command**:

```
# m  h  dom mon dow   command
  */5 *  *   *   *   /usr/local/bin/my-script.sh
```

| Field | Values                    | Notes                                |
|-------|---------------------------|--------------------------------------|
| `m`   | 0-59                      | Minute.                              |
| `h`   | 0-23                      | Hour.                                |
| `dom` | 1-31                      | Day of month.                        |
| `mon` | 1-12 or `jan`..`dec`      | Month.                               |
| `dow` | 0-7 or `sun`..`sat`       | Day of week (0 and 7 are Sunday).    |

System crontabs (`/etc/crontab`, `/etc/cron.d/*`) have **6 fields +
command** — the extra field is the **user**:

```
# m  h  dom mon dow user command
  30 2  *   *   *   root /usr/local/bin/backup-mysql.sh
```

Range, list, step shorthand:

| Spec      | Meaning                                |
|-----------|----------------------------------------|
| `*`       | Every value.                           |
| `1-5`     | Values 1 through 5 inclusive.          |
| `1,3,5`   | Explicit list.                         |
| `*/15`    | Every 15 (e.g. 0, 15, 30, 45).         |
| `0-30/5`  | 0, 5, 10, 15, 20, 25, 30.              |
| `@reboot` | Once, at daemon startup.               |
| `@hourly` | `0 * * * *`                            |
| `@daily`  | `0 0 * * *` (also `@midnight`)         |
| `@weekly` | `0 0 * * 0`                            |
| `@monthly`| `0 0 1 * *`                            |
| `@yearly` | `0 0 1 1 *` (also `@annually`)         |

---

## 8. Cron environment gotchas

This is the single most common source of "cron didn't run my script":
cron runs with an almost-empty environment.

- `PATH` in cron is roughly `/usr/bin:/bin` — **not** your login `PATH`.
- `HOME` is set to the user's home.
- `SHELL` is `/bin/sh`, not bash, unless you override it.
- `LANG`, locale variables: unset.
- `USER`, `LOGNAME`: set.
- No `$DISPLAY`, no `$DBUS_SESSION_BUS_ADDRESS`.

Defensive patterns:

```crontab
# Set shell and PATH at the top of the crontab
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=ops@example.com
LANG=en_US.UTF-8

# Use ABSOLUTE paths in commands
30 2 * * * /usr/local/bin/backup-mysql.sh
*/15 * * * * /usr/bin/php /var/www/html/cron/run.php
```

Always use absolute paths. Always. A script that works fine when you run
it by hand will silently fail under cron because `mysqldump`, `rclone`,
or `gpg` wasn't in `$PATH`.

### MAILTO and output redirection

By default, anything a cron job prints on stdout or stderr is mailed to
the user (or to `MAILTO=`). If you have no MTA configured this produces
`/var/mail/root` full of errors.

Redirect options:

```crontab
# Discard all output (never do this while debugging)
30 2 * * * /usr/local/bin/backup-mysql.sh > /dev/null 2>&1

# Append to a log file (recommended for debugging)
30 2 * * * /usr/local/bin/backup-mysql.sh >> /var/log/backup-mysql.log 2>&1

# Send only errors, discard stdout
30 2 * * * /usr/local/bin/backup-mysql.sh > /dev/null
```

Tip: while debugging, use the `>> logfile 2>&1` form so you capture
*everything*. Switch to silent mode only after confirming it works.

---

## 9. Cron logging and debugging

Cron writes execution records to syslog (and so to the journal):

```bash
sudo journalctl -u cron --since "1 hour ago" --no-pager
sudo journalctl -u cron -f                   # follow live
sudo grep CRON /var/log/syslog | tail -50    # on systems with rsyslog
```

A log line looks like:

```
Feb 10 02:30:01 web01 CRON[4567]: (root) CMD (/usr/local/bin/backup-mysql.sh)
```

Seeing the `CMD` line means cron **fired** the command. It does **not**
say the command succeeded — for that, check the command's own log or
the mail spool.

### The "my cron didn't run" checklist

1. Is `cron.service` running? `systemctl status cron`
2. Is the user crontab owned by the right user? `ls -l /var/spool/cron/crontabs/`
3. Does the crontab parse? `crontab -l -u <user>` returns without errors.
4. Is the time-zone what you think it is? `timedatectl` — remember cron
   uses local time by default. Compare `date` with the spec.
5. Did cron log a `CMD` line at the expected time? If yes, the job ran
   — look at the script's own logs. If no, the spec is wrong.
6. Is `$PATH` set in the crontab or the script? See section 8.
7. Is the script executable? `ls -l /path/to/script.sh` — needs `x`.
8. Does the script have a shebang? `head -1 script.sh` — `#!/bin/bash`
   is mandatory.
9. Does `MAILTO=` point somewhere real, and does the box have an MTA?
10. For jobs in `/etc/cron.d/*.conf`: is the filename `^[A-Za-z0-9_-]+$`?
    cron **ignores** files with a `.` in the name (so `backup.conf`
    never runs — name it `backup` instead).

---

## 10. anacron — cron for machines that sleep

Plain cron has a flaw: if the machine was off or asleep when the job
was scheduled, the job is simply missed. `anacron` fixes this for daily,
weekly, and monthly jobs by using timestamp files in
`/var/spool/anacron/`.

On Ubuntu/Debian, anacron is typically installed alongside cron. Its
table is `/etc/anacrontab`:

```
# /etc/anacrontab
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
RANDOM_DELAY=45
START_HOURS_RANGE=3-22

# period delay  job-identifier  command
1       5       cron.daily      run-parts /etc/cron.daily
7       25      cron.weekly     run-parts /etc/cron.weekly
@monthly 45     cron.monthly    run-parts /etc/cron.monthly
```

The four columns:

| Column         | Meaning                                                             |
|----------------|---------------------------------------------------------------------|
| period         | Days between runs (`1`, `7`, `@monthly`).                           |
| delay          | Minutes to wait after machine is eligible, before running.          |
| job-identifier | Label — must match a file in `/var/spool/anacron/`.                 |
| command        | What to run.                                                        |

For a server that is on 24/7, anacron is usually redundant — plain cron
works. On laptops and intermittently-on servers, anacron is essential
so `cron.daily` jobs actually catch up. If you are using systemd timers
instead, `Persistent=true` gives you the same catch-up behaviour.

Note: anacron only handles daily and longer periods. It does **not**
run `/etc/cron.hourly/` — that stays on plain cron.

---

## 11. `run-parts` and the `/etc/cron.*` directories

`run-parts` is the helper that runs every executable file in a directory,
in alphanumeric order. It is how `/etc/cron.hourly`, `/etc/cron.daily`,
`/etc/cron.weekly`, and `/etc/cron.monthly` are executed.

```bash
run-parts --test /etc/cron.daily              # list what would run, in order
run-parts --report /etc/cron.daily            # run, prefix output with script name
```

Rules for scripts dropped into these directories:

- Must be executable (`chmod +x`).
- **Filename must not contain a dot** — `backup.sh` is ignored. Use
  `backup` or `50-backup`.
- Filename must match `^[A-Za-z0-9_-]+$`.
- Scripts run as root.
- Order is alphabetical — prefix with `10-`, `20-`, etc. if order matters.

This is why `apt` dumps files like `apt-compat`, `dpkg`, `logrotate` (no
dot) into `/etc/cron.daily/`.

---

## 12. Worked example: converting a cron job to a systemd timer

Start with this cron entry in root's crontab:

```crontab
MAILTO=ops@example.com
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

30 2 * * * /usr/local/bin/backup-mysql.sh >> /var/log/backup-mysql.log 2>&1
```

### Step 1 — Write the service unit

Save at `/etc/systemd/system/backup-mysql.service`:

```ini
[Unit]
Description=MySQL backup job
After=network-online.target mysql.service
Wants=network-online.target

[Service]
Type=oneshot
User=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/local/bin/backup-mysql.sh
StandardOutput=journal
StandardError=journal
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7

# Hardening
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
NoNewPrivileges=yes
ReadWritePaths=/root/backups /var/log
```

### Step 2 — Write the timer unit

Save at `/etc/systemd/system/backup-mysql.timer`:

```ini
[Unit]
Description=Run MySQL backup daily at 02:30

[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=10min
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
```

### Step 3 — Enable

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now backup-mysql.timer
systemctl list-timers | grep backup-mysql
```

### Step 4 — Test it

```bash
# Fire immediately
sudo systemctl start backup-mysql.service

# Read the output (the script's stdout/stderr goes to the journal)
sudo journalctl -u backup-mysql.service -n 100 --no-pager
```

### Step 5 — Remove the old cron entry

```bash
sudo crontab -e -u root
# Delete the 30 2 * * * ... backup-mysql.sh line, save, exit
```

### What you gain

- **Unified log**: `journalctl -u backup-mysql -f` shows everything,
  with timestamps, priorities, and metadata. No separate
  `/var/log/backup-mysql.log`.
- **Status at a glance**: `systemctl status backup-mysql.timer` shows
  when it last fired and when it fires next.
- **Missed-run handling**: `Persistent=true` catches up if the server
  was off.
- **Jitter**: `RandomizedDelaySec=` spreads out load across a fleet of
  servers that would otherwise all fire at exactly 02:30.
- **Sandboxing**: the `Protect*` directives limit blast radius if the
  script misbehaves.
- **Resource limits**: add `MemoryMax=`, `CPUQuota=` when you need them.

### When to keep using cron instead

- It's a one-line script and you don't want to maintain two files.
- You're editing a user crontab on a shared box where you don't have
  root.
- You're matching an existing shop convention of "everything is in
  `/etc/cron.d/`".

Both tools are fine. Pick the one that gives the clearest operational
story for the job in front of you.

---

## Sources

- `systemd.timer(5)`, `systemd.time(7)`, `systemd.service(5)` man pages.
- `crontab(5)`, `crontab(1)`, `cron(8)`, `anacron(8)`, `run-parts(8)` man pages.
- **Linux Command Line and Shell Scripting Bible** — cron chapter: cron directories, anacron, `run-parts`, `/etc/anacrontab` walkthrough.
- **Ubuntu Server Guide (Focal 20.04)**, Canonical (2020) — `systemctl` and timer examples for Ubuntu.
- **Mastering Ubuntu**, Ghada Atef (2023) — scheduled tasks chapter.
- **Linux System Administration for the 2020s** — why timers are the modern choice for service-style jobs.
- Real-world operational notes from production Ubuntu servers running cron, anacron, and systemd timers side by side.
