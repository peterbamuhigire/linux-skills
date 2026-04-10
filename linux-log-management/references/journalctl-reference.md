# journalctl Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

`journalctl` is the query tool for systemd's binary journal. Every service
on a modern Ubuntu server emits structured records to journald, and
`journalctl` lets you slice those records by unit, priority, time, boot,
user, kernel facility, or any one of dozens of metadata fields. This
reference walks through the architecture, every filter flag worth
remembering, configuration of `journald.conf`, disk management, and
common production workflows.

## Table of contents

- [Architecture — journald, metadata, forwarding](#architecture--journald-metadata-forwarding)
- [Where the journal lives on disk](#where-the-journal-lives-on-disk)
- [journald.conf — the knobs that matter](#journaldconf--the-knobs-that-matter)
- [Basic reading: last N, follow, since/until](#basic-reading-last-n-follow-sinceuntil)
- [Filtering by unit](#filtering-by-unit)
- [Filtering by priority](#filtering-by-priority)
- [Filtering by time](#filtering-by-time)
- [Filtering by boot](#filtering-by-boot)
- [Filtering by user, UID, PID](#filtering-by-user-uid-pid)
- [Filtering by arbitrary metadata fields](#filtering-by-arbitrary-metadata-fields)
- [Kernel messages and dmesg replacement](#kernel-messages-and-dmesg-replacement)
- [Output formats](#output-formats)
- [Disk usage and vacuuming](#disk-usage-and-vacuuming)
- [Access control — who can read the journal](#access-control--who-can-read-the-journal)
- [Forwarding to rsyslog / a remote host](#forwarding-to-rsyslog--a-remote-host)
- [Audit the journal itself](#audit-the-journal-itself)
- [Recipes by task](#recipes-by-task)
- [Sources](#sources)

## Architecture — journald, metadata, forwarding

`systemd-journald.service` is a single long-running process owned by the
root system-session systemd. It has four input paths:

1. **Kernel ring buffer** (`/dev/kmsg`) — all `printk()` messages.
2. **Forwarded syslog** (`/run/systemd/journal/syslog`) — legacy syslog
   client sockets.
3. **Native protocol** (`/run/systemd/journal/socket`) — used by
   `sd_journal_send()`, the supported way for new programs to log with
   structured fields.
4. **Standard output/error** of every unit systemd starts. systemd
   captures unit stdout/stderr and pipes it to journald by default.

For each incoming message journald attaches a **dictionary of metadata
fields**:

```
PRIORITY=6
_UID=0
_GID=0
_COMM=nginx
_EXE=/usr/sbin/nginx
_CMDLINE=nginx: master process /usr/sbin/nginx
_SYSTEMD_UNIT=nginx.service
_PID=1234
_HOSTNAME=web01
_MACHINE_ID=f9b0...
_BOOT_ID=a21c...
MESSAGE=Starting A high performance web server and a reverse proxy server...
```

Fields prefixed with underscore (`_PID`, `_SYSTEMD_UNIT`, etc.) are
**trusted** — journald stamps them itself. User-supplied fields have no
underscore. When you filter with `journalctl _SYSTEMD_UNIT=nginx.service`
you are pattern-matching on those fields; the journal is indexed, so the
query is fast even against gigabytes.

The journal is a **binary append-only log with an index file**. The
on-disk format guarantees:

- Random access by cursor (`journalctl --cursor=...`).
- Fast filtering by field (indexed).
- Optional **forward secure sealing** (FSS) — a key-rotated HMAC so
  tampering is detectable (`journalctl --setup-keys`; rarely used).
- Automatic rotation when the file hits `SystemMaxFileSize`.

Journald also forwards everything to:

- `/dev/kmsg` (optional: `ForwardToKMsg=`)
- `/dev/tty` on console (`ForwardToConsole=`)
- wall (`ForwardToWall=`)
- the classic syslog socket (`ForwardToSyslog=`), which is how rsyslog
  fills `/var/log/syslog`, `/var/log/auth.log`, etc.

## Where the journal lives on disk

Two possible locations:

| Path | Mode | Used when |
|---|---|---|
| `/var/log/journal/<machine-id>/*.journal` | persistent | `Storage=persistent` or `auto` + the directory exists |
| `/run/log/journal/<machine-id>/*.journal` | volatile (tmpfs) | `Storage=volatile` or `auto` + `/var/log/journal` does not exist |

On a default Ubuntu 22.04/24.04 server, `Storage=auto` and
`/var/log/journal/` **exists**, so journal data is persisted across
reboots. Old-school minimal images may lack the directory — create it
and restart journald to turn on persistence:

```bash
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
```

Files under `/var/log/journal/<id>/`:

- `system.journal` — the currently-writing file.
- `system@*.journal` — older rotated journals.
- `user-1000.journal` — per-user logs (if enabled).

## journald.conf — the knobs that matter

Configuration lives in `/etc/systemd/journald.conf` with drop-ins under
`/etc/systemd/journald.conf.d/*.conf`. Apply with:

```bash
sudo systemctl restart systemd-journald
```

The fields you actually need:

```ini
[Journal]
Storage=persistent
Compress=yes
Seal=no

# Disk caps — once exceeded, oldest files are deleted:
SystemMaxUse=1G
SystemKeepFree=2G
SystemMaxFileSize=128M
SystemMaxFiles=100

# Time-based retention:
MaxRetentionSec=1month
MaxFileSec=1week

# Forwarding to classic syslog (leave on unless you've removed rsyslog):
ForwardToSyslog=yes
ForwardToKMsg=no
ForwardToConsole=no
ForwardToWall=yes

# Rate limiting — protect disk from log floods:
RateLimitIntervalSec=30s
RateLimitBurst=10000
```

Field meanings:

- **`Storage=`** — `persistent` always writes to `/var/log/journal`,
  `volatile` always uses `/run/log/journal`, `auto` picks based on the
  directory, `none` disables the on-disk store (forward-only).
- **`Compress=`** — compress records larger than 512 bytes with XZ. Usually
  `yes`.
- **`SystemMaxUse=`** — absolute cap on total journal bytes.
- **`SystemKeepFree=`** — minimum free disk to keep on the journal's
  filesystem. journald deletes old files if this would be violated.
- **`MaxRetentionSec=`** — delete files older than this.
- **`RateLimitIntervalSec=` / `RateLimitBurst=`** — if a single unit
  exceeds `burst` messages in `interval`, further messages are dropped
  with a `Suppressed N messages from ...` record. Raise the burst for
  noisy trusted units, lower the burst to harden against a log flood.

See current effective config:

```bash
sudo systemctl show systemd-journald | grep -E "^(Storage|Compress|MaxUse|KeepFree|MaxRetention|RateLimit)"
```

## Basic reading: last N, follow, since/until

```bash
journalctl                          # entire journal, paged (oldest first)
journalctl -r                       # reverse (newest first)
journalctl -n 50                    # last 50 records (newest at bottom)
journalctl -n 200 -r                # last 200 records, newest on top
journalctl -f                       # live follow (tail -f)
journalctl --no-pager               # no less(1) pager (scripts)
journalctl -x                       # explain error codes when available
journalctl -e                       # jump to the end (then scroll up)
journalctl -o cat                   # message only, no timestamp
```

`-n` accepts a number or `all`. `--no-pager` combined with `-n 200` is the
standard one-shot form you paste into incident tickets.

## Filtering by unit

The single most useful flag:

```bash
journalctl -u nginx.service
journalctl -u nginx -f                      # live tail one unit
journalctl -u nginx -u php8.3-fpm -f        # live tail multiple units
journalctl -u "php*-fpm.service"            # glob match
journalctl -u mysql.service -n 100 --no-pager
journalctl --user-unit myapp.service        # user systemd units
```

`-u` may be repeated to OR multiple units. Combine with `-p` and time
filters to drill into a specific incident:

```bash
journalctl -u nginx -p err --since "2025-03-22 08:00" --until "2025-03-22 09:00"
```

## Filtering by priority

syslog priority levels, lowest (most verbose) to highest:

| Level | Name | Typical source |
|---|---|---|
| 0 | `emerg` | system unusable |
| 1 | `alert` | action must be taken immediately |
| 2 | `crit` | critical conditions |
| 3 | `err` | error conditions |
| 4 | `warning` | warning conditions |
| 5 | `notice` | normal but significant |
| 6 | `info` | informational |
| 7 | `debug` | debug-level |

`-p LEVEL` matches the level **and everything more severe**:

```bash
journalctl -p err                            # err, crit, alert, emerg
journalctl -p warning                        # warning + above
journalctl -p 0..3                           # emerg..err, range form
journalctl -p err --since "1 hour ago" --no-pager
journalctl -p err -u nginx --since today
```

The range form `0..3` is an exact bracket, helpful for ignoring
`debug`/`info` noise from a unit you cannot otherwise silence.

## Filtering by time

All of these are accepted:

```bash
journalctl --since "2025-03-22 08:00:00"
journalctl --since "08:00"                   # today at 08:00
journalctl --since "1 hour ago"
journalctl --since yesterday
journalctl --since "2 days ago" --until "1 day ago"
journalctl --since "09:15" --until "09:20"
journalctl --since "@1710000000"             # Unix epoch seconds
journalctl --since "now - 15min"             # not supported; use "15 min ago"
```

The parser understands English phrases (`today`, `yesterday`, `now`), ISO
timestamps (`YYYY-MM-DD HH:MM:SS`), and `@<epoch>`. Quote arguments with
spaces.

Investigate a specific incident window:

```bash
journalctl --since "2025-03-22 14:32:00" --until "2025-03-22 14:35:00" \
  -u nginx -u php8.3-fpm -u mysql
```

## Filtering by boot

```bash
journalctl --list-boots                      # index of persisted boots
#    IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
#      0 a21c... 2025-03-22 02:00:14 UTC  2025-03-22 14:45:22 UTC
#     -1 93e2... 2025-03-18 09:12:44 UTC  2025-03-22 01:58:10 UTC

journalctl -b                                # current boot only
journalctl -b -1                             # previous boot
journalctl -b -2 -u nginx                    # two boots ago, one unit
journalctl -b a21c...                        # exact boot by ID
journalctl -k -b -1                          # kernel messages, previous boot
```

This is the first query after a reboot you did not expect. If the server
fell over at 03:00 and auto-rebooted at 03:02, `journalctl -b -1` gives
you the last few seconds of the old boot before the crash.

## Filtering by user, UID, PID

```bash
journalctl _UID=1000                         # everything from UID 1000
journalctl _UID=1000 _COMM=bash              # and only from bash
journalctl _PID=2345
journalctl _PID=2345 --since "10 min ago"
journalctl --user                            # current user's own journal
```

`_UID`, `_GID`, `_PID`, `_COMM`, `_EXE`, `_CMDLINE`, `_SYSTEMD_UNIT`,
`_HOSTNAME`, `_BOOT_ID` are all valid match keys. They are **anded**
together when supplied on the same command line. Use `+` to OR:

```bash
journalctl _SYSTEMD_UNIT=nginx.service + _SYSTEMD_UNIT=php8.3-fpm.service
```

## Filtering by arbitrary metadata fields

Every journal record is a dictionary; any key is queryable:

```bash
journalctl -F MESSAGE_ID                     # list all distinct MESSAGE_IDs
journalctl -F _SYSTEMD_UNIT                  # list all units that have logged
journalctl -F _COMM                          # list all binaries that have logged
journalctl MESSAGE_ID=dc833cc19f6d4e14a5e89b07a7c6d5a6
journalctl _KERNEL_SUBSYSTEM=pci
```

`-F FIELD` lists the **unique values** seen for that field. Handy for
"what units actually exist on this box?" without grepping systemctl.

Well-known MESSAGE_IDs that matter (defined by systemd):

| ID | Event |
|---|---|
| `fc2e22bc6ee647b6b90729ab34a250b1` | process crashed (systemd-coredump) |
| `b07a249cd024414a82dd00cd181378ff` | OOM kill |
| `6bbd95ee977941e497c48be27c254128` | user session opened |
| `4d4e5dbfe84c4f37b0b0a9d82f6e0e63` | user session closed |

```bash
journalctl MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1   # all crashes
journalctl MESSAGE_ID=b07a249cd024414a82dd00cd181378ff   # all OOM kills
```

## Kernel messages and dmesg replacement

```bash
journalctl -k                                # kernel ring buffer (= dmesg)
journalctl -k -b                             # current boot kernel msgs
journalctl -k --since "5 min ago"
journalctl -k | grep -i "oom\|killed process"
journalctl -k -p err                         # kernel errors
```

`journalctl -k` replaces `dmesg` and is preferred because:

- It has **human timestamps** without `dmesg -T` gymnastics.
- It survives reboots (`-k -b -1`).
- It accepts all journalctl filters.

## Output formats

```bash
journalctl -o short                          # default — syslog-ish
journalctl -o short-iso                      # ISO timestamps
journalctl -o short-precise                  # microsecond precision
journalctl -o short-monotonic                # seconds since boot
journalctl -o cat                            # message only
journalctl -o verbose                        # every field
journalctl -o json                           # one JSON object per line
journalctl -o json-pretty                    # indented JSON
journalctl -o export                         # binary export format
```

Useful combos:

```bash
# Grep for a specific error across services, with ISO timestamps:
journalctl -o short-iso -p err --since today | grep -i "connection refused"

# Dump a unit's log as JSON for processing in jq:
journalctl -u nginx -o json --since "1 hour ago" \
  | jq -r 'select(.PRIORITY<="3") | .MESSAGE'

# Just the messages, no timestamps — feeding to another tool:
journalctl -u nginx -o cat --since "10 min ago" | sort | uniq -c | sort -rn
```

JSON output preserves the full metadata dictionary; it is the format of
choice when piping to `jq`, Loki, or a custom parser.

## Disk usage and vacuuming

```bash
journalctl --disk-usage
# Archived and active journals take up 812.0M in the file system.

# Force rotate (current journal becomes archived, new one starts):
sudo journalctl --rotate

# Delete old files until total size ≤ 500 MB:
sudo journalctl --vacuum-size=500M

# Delete files older than 7 days:
sudo journalctl --vacuum-time=7d

# Keep at most 10 archived files (plus the active one):
sudo journalctl --vacuum-files=10
```

Vacuuming respects the configured retention and will not delete the
**currently-writing** journal file. For a guaranteed "start fresh" you
must rotate first:

```bash
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s
```

On a disk-full incident, clearing the journal is a common quick win:

```bash
sudo journalctl --disk-usage
sudo journalctl --vacuum-size=200M
sudo journalctl --disk-usage
```

Then permanently cap it in `journald.conf`:

```ini
[Journal]
SystemMaxUse=500M
MaxRetentionSec=2weeks
```

## Access control — who can read the journal

Out of the box the journal is readable by:

- `root`
- members of `systemd-journal` group
- members of `adm` and `wheel` (traditional log-reader groups, if
  journald was compiled with that default)

Check your user's access:

```bash
groups $USER | tr ' ' '\n' | grep -E "adm|systemd-journal"
journalctl -n 5        # should show output without sudo
```

Grant a user read access:

```bash
sudo usermod -aG systemd-journal peter
# User must log out / log in for group membership to apply.
```

A user can always read **their own** journal:

```bash
journalctl --user                # current user only
journalctl --user -u myapp.service
```

## Forwarding to rsyslog / a remote host

### To rsyslog (classic /var/log files)

Already on by default:

```ini
# /etc/systemd/journald.conf
ForwardToSyslog=yes
```

rsyslog listens on `/run/systemd/journal/syslog` and splits the stream
into `/var/log/syslog`, `/var/log/auth.log`, etc. The rsyslog modules are
configured in `/etc/rsyslog.conf` and `/etc/rsyslog.d/`.

If you remove rsyslog entirely (journal-only host) also set
`ForwardToSyslog=no` to stop journald pushing into a socket nothing
reads.

### To a remote collector

systemd ships two helpers: `systemd-journal-remote` (receiver) and
`systemd-journal-upload` (sender).

**Sender side:**

```bash
sudo apt install systemd-journal-remote

# /etc/systemd/journal-upload.conf
[Upload]
URL=https://logs.example.com:19532

sudo systemctl enable --now systemd-journal-upload.service
```

**Receiver side:**

```bash
sudo apt install systemd-journal-remote

sudo mkdir -p /var/log/journal/remote
sudo systemctl enable --now systemd-journal-remote.socket

# Query received logs:
journalctl --directory=/var/log/journal/remote
```

For production, most shops forward to a log platform (Loki, Elasticsearch,
CloudWatch) via a specialised agent (`promtail`, `filebeat`, `vector`,
`fluent-bit`) rather than the systemd pair — they are easier to secure
and more mature downstream.

## Audit the journal itself

```bash
journalctl --verify                          # integrity check (FSS)
journalctl --header                          # print journal file headers
ls -lh /var/log/journal/*/                   # physical files

# When did journald last rotate?
systemctl status systemd-journald
```

## Recipes by task

### First five minutes of an incident

```bash
journalctl -p err --since "1 hour ago" --no-pager | tail -30
journalctl -k --since "1 hour ago" | grep -iE "oom|error|panic|killed"
journalctl -u nginx -u php8.3-fpm -u mysql -p err --since "1 hour ago" --no-pager
```

### "What happened right before the crash?"

```bash
journalctl --list-boots | head
journalctl -b -1 --since "2025-03-22 02:55" --until "2025-03-22 03:01"
```

### Grep a service for a specific string

```bash
journalctl -u nginx | grep -i "upstream timed out"
# better — keep metadata:
journalctl -u nginx -g "upstream timed out" --no-pager
```

`-g PATTERN` is a Perl-compatible regex filter on the MESSAGE field,
honouring all other filters.

### Live tail a service with colour by level

```bash
journalctl -u nginx -f -o short-iso
```

### Count errors per service in the last hour

```bash
journalctl -p err --since "1 hour ago" --no-pager \
  | awk '{print $5}' | sed 's/\[.*//;s/:$//' \
  | sort | uniq -c | sort -rn
```

(The message prefix format varies slightly between releases; adapt the
`awk`/`sed` columns if needed — or do it robustly in JSON:)

```bash
journalctl -p err --since "1 hour ago" -o json \
  | jq -r '._SYSTEMD_UNIT // ._COMM' \
  | sort | uniq -c | sort -rn | head
```

### Show only coredumps in the last week

```bash
journalctl MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1 --since "1 week ago"
coredumpctl list --since "1 week ago"
coredumpctl info <PID>             # stack trace if debug symbols available
coredumpctl dump <PID> > /tmp/core # extract the core file
```

### Export journal from one host to another

```bash
# Source:
sudo journalctl -b -o export > /tmp/boot.journal

# Destination:
mkdir -p /tmp/boot-journal
systemd-journal-remote --output=/tmp/boot-journal/ /tmp/boot.journal
journalctl --directory=/tmp/boot-journal
```

### Cap journal size on a disk-constrained VM

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/99-size.conf >/dev/null <<'EOF'
[Journal]
SystemMaxUse=300M
MaxRetentionSec=2weeks
EOF
sudo systemctl restart systemd-journald
journalctl --disk-usage
```

### Silence a noisy unit without killing it

```bash
# Raise journald rate limit for everyone except a specific chatty unit:
sudo mkdir -p /etc/systemd/system/noisy.service.d
sudo tee /etc/systemd/system/noisy.service.d/log.conf >/dev/null <<'EOF'
[Service]
LogRateLimitIntervalSec=10s
LogRateLimitBurst=20
EOF
sudo systemctl daemon-reload
sudo systemctl restart noisy.service
```

## Sources

- Canonical, *Ubuntu Server Guide* (20.04 LTS), logging section.
- `man 1 journalctl`, `man 5 journald.conf`, `man 8 systemd-journald`.
- systemd documentation —
  <https://www.freedesktop.org/software/systemd/man/journalctl.html>.
- Lennart Poettering's systemd journal design notes —
  <https://0pointer.de/blog/projects/journalctl.html>.
- systemd-journal-remote manual —
  <https://www.freedesktop.org/software/systemd/man/systemd-journal-remote.service.html>.
