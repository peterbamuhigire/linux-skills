# systemd Service Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This reference is the deep-dive companion to `SKILL.md`. It covers every
systemd concept that matters when you run production web servers on
Ubuntu/Debian — unit types, unit file sections, service types, dependencies,
sandboxing/hardening, resource limits, drop-in overrides, and per-service
operational notes for the stack this repo supports (nginx, apache2, mysql,
postgresql, php-fpm, redis, fail2ban). Every command is stock Ubuntu/Debian
— no helper scripts required.

## Table of contents

1. systemd unit types
2. The three unit-file sections: [Unit], [Service], [Install]
3. Service `Type=` values and when to use each
4. Restart policies
5. Dependencies and ordering
6. User, group, and privilege dropping
7. Filesystem sandboxing and hardening directives
8. Resource limits (cgroup controls)
9. Drop-in overrides with `systemctl edit`
10. When you must `daemon-reload`
11. Inspecting and debugging units
12. Per-service notes: nginx, apache2, mysql, postgresql, php-fpm, redis, fail2ban
13. Sources

---

## 1. systemd unit types

systemd manages more than just services. Every unit file has a suffix that
tells systemd what kind of unit it is. The ones you touch on a production
web server:

| Suffix      | Purpose                                                                 |
|-------------|-------------------------------------------------------------------------|
| `.service`  | A long-running process (nginx, mysql, php-fpm, a Node app).             |
| `.socket`   | A socket that, when connected to, starts an associated service.         |
| `.target`   | A named group of units — `multi-user.target` is the classic run level.  |
| `.timer`    | A scheduled trigger for a paired `.service` (cron replacement).         |
| `.mount`    | A filesystem mount point managed by systemd (parallel to `/etc/fstab`). |
| `.path`     | Watches a file or directory and activates a service on change.          |
| `.swap`     | A swap device or file.                                                  |
| `.device`   | A kernel device node exposed to systemd.                                |
| `.slice`    | A cgroup slice used for resource accounting (e.g. `user.slice`).        |
| `.scope`    | An externally-created process group managed by systemd.                 |

List every installed unit of a given type:

```bash
systemctl list-unit-files --type=service
systemctl list-unit-files --type=timer
systemctl list-unit-files --type=socket
systemctl list-units --type=mount --all
```

Unit files live in three directories, searched in precedence order:

1. `/etc/systemd/system/` — local admin (wins over everything).
2. `/run/systemd/system/` — runtime, volatile.
3. `/lib/systemd/system/` — packaged, provided by apt (never edit directly).

Never edit files under `/lib/systemd/system/`. Create a drop-in override
under `/etc/systemd/system/<unit>.d/` instead (see section 9).

---

## 2. The three unit-file sections

A typical service unit has three sections. Directives are case-sensitive.

```ini
[Unit]
Description=My Node.js API
Documentation=https://example.com/docs
After=network-online.target postgresql.service
Wants=network-online.target
Requires=postgresql.service

[Service]
Type=simple
User=nodeapp
Group=nodeapp
WorkingDirectory=/var/www/api
ExecStart=/usr/bin/node /var/www/api/server.js
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
StartLimitBurst=5
StartLimitIntervalSec=60

[Install]
WantedBy=multi-user.target
```

### [Unit] directives worth knowing

| Directive          | Meaning                                                          |
|--------------------|------------------------------------------------------------------|
| `Description=`     | Human-readable one-liner shown by `systemctl status`.            |
| `Documentation=`   | One or more URIs (`man:`, `https://`).                            |
| `After=`           | Ordering only. Start this unit **after** the listed units.       |
| `Before=`          | Ordering only. Start this unit **before** the listed units.      |
| `Requires=`        | Hard dependency. If the dependency fails, this unit fails too.   |
| `Wants=`           | Soft dependency. Dependency is nice to have; not fatal if absent.|
| `BindsTo=`         | Stronger than `Requires` — if dep stops, we stop.                |
| `Conflicts=`       | Starting this stops the other; starting the other stops this.    |
| `ConditionPathExists=` | Unit is skipped (not failed) if path does not exist.         |
| `ConditionFileNotEmpty=` | Same idea, for non-empty files.                            |
| `AssertPathExists=` | Fails the unit (not skipped) if path missing.                   |

Rule of thumb: use `Wants=` + `After=` for almost every normal dependency.
Reserve `Requires=` for hard, data-loss-grade coupling.

### [Service] core directives

| Directive       | Meaning                                                             |
|-----------------|---------------------------------------------------------------------|
| `Type=`         | Startup model — see section 3.                                      |
| `ExecStart=`    | The command to run. Absolute path required.                         |
| `ExecStartPre=` | Command run before `ExecStart`. Prefix `-` to ignore failures.      |
| `ExecStartPost=`| Command run after `ExecStart` signals ready.                        |
| `ExecStop=`     | Custom stop command. Default is `SIGTERM` to the main PID.          |
| `ExecReload=`   | How to reload config (e.g. `nginx -s reload`).                      |
| `PIDFile=`      | Required for `Type=forking` so systemd can find the daemon.         |
| `Environment=`  | `KEY=VALUE` pairs injected into the process environment.           |
| `EnvironmentFile=` | Load a `KEY=VALUE` file (e.g. `/etc/default/nginx`).             |
| `WorkingDirectory=` | Chdir before `ExecStart`.                                       |
| `StandardOutput=` | `journal` (default), `null`, `append:/path/file`.                 |
| `StandardError=` | Same as above.                                                     |
| `TimeoutStartSec=` | How long to wait for startup before marking failed.              |
| `TimeoutStopSec=`  | How long to wait for stop before `SIGKILL`.                      |

### [Install] directives

`[Install]` is used **only** by `systemctl enable` / `disable`. It has no
effect on an already-running system.

| Directive      | Meaning                                                              |
|----------------|----------------------------------------------------------------------|
| `WantedBy=`    | Usually `multi-user.target`. On enable, a symlink is added to the target's `.wants/` directory. |
| `RequiredBy=`  | Like `WantedBy=` but with hard-dependency semantics.                 |
| `Alias=`       | Alternate unit name.                                                 |
| `Also=`        | Enable these other units alongside this one.                         |

---

## 3. Service `Type=` values

The service type controls how systemd decides the service has finished
starting. Picking the wrong one leads to "service appears started but
nothing is listening yet" bugs.

| Type        | Behaviour                                                                                   | Use for                                       |
|-------------|---------------------------------------------------------------------------------------------|-----------------------------------------------|
| `simple`    | Start `ExecStart`; consider ready immediately. Default when unspecified.                    | Node.js, Python daemons, anything foreground. |
| `exec`      | Like `simple` but waits until the binary has actually been `exec()`ed.                      | Modern replacement for `simple`.              |
| `forking`   | Expects the process to fork and the parent to exit. Pair with `PIDFile=`.                   | Classic daemons (old Apache init scripts, bind9, some Debian packages). |
| `oneshot`   | Runs once and exits. Pair with `RemainAfterExit=yes` for state tracking.                    | Init/bootstrap tasks, firewall rules, scripts.|
| `notify`    | Service calls `sd_notify(READY=1)` when ready. Most reliable startup signal.                | Modern nginx, modern systemd-native services. |
| `notify-reload` | Like `notify` but also handles reload handshaking.                                      | Services that support `sd_notify_reload`.     |
| `dbus`      | Considered ready when it claims a D-Bus name.                                               | D-Bus daemons only.                           |
| `idle`      | Like `simple` but waits for other jobs to finish first. Cosmetic — cleans up boot messages. | Login managers.                               |

For any new Node.js, Python, or Go service you write, use `Type=simple`
unless you have a reason not to.

---

## 4. Restart policies

`Restart=` controls the crash-recovery behaviour. Pair it with the rate-limit
directives so a crash loop doesn't hammer your server.

| Value           | Restart on… (exit 0 / exit !=0 / signal / timeout / watchdog)               |
|-----------------|-----------------------------------------------------------------------------|
| `no` (default)  | Never.                                                                      |
| `on-success`    | Only clean exits. Almost never what you want for a daemon.                  |
| `on-failure`    | Non-zero exit, killed by uncaught signal, timeout, watchdog. Recommended.   |
| `on-abnormal`   | Signal, timeout, watchdog — but not on non-zero exit code.                  |
| `on-abort`      | Only if killed by uncaught signal.                                          |
| `on-watchdog`   | Only on watchdog timeout.                                                   |
| `always`        | Always restart, regardless of why it exited.                                |

### Rate limiting

```ini
[Service]
Restart=on-failure
RestartSec=5s
StartLimitBurst=5
StartLimitIntervalSec=60
```

Read as: restart up to 5 times within any 60-second window, waiting 5
seconds between attempts. On the 6th failure in that window, systemd gives
up and leaves the unit in `failed` state until someone clears it with
`systemctl reset-failed <unit>`.

Note: in modern systemd, `StartLimitBurst=` and `StartLimitIntervalSec=`
belong in `[Unit]`, not `[Service]`. `systemctl edit` will place them
correctly if you let it create a drop-in.

### Watchdog

```ini
[Service]
Type=notify
WatchdogSec=30s
```

The service must call `sd_notify(WATCHDOG=1)` at least every 30 seconds
or systemd kills it. Use for long-running health monitoring of native
services.

---

## 5. Dependencies and ordering

The dependency directives fall into two camps:

- **Ordering**: `Before=`, `After=` — control *sequence* only.
- **Requirement**: `Requires=`, `Wants=`, `BindsTo=`, `PartOf=`, `Conflicts=`
  — control *whether* the other unit is pulled in.

You almost always need **both**. `Requires=postgres.service` alone does
not guarantee Postgres is up **before** your service starts; you also
need `After=postgres.service`.

### The network-online.target trap

`network.target` is reached early in boot — it does **not** mean the
network has an address. `network-online.target` is the unit to wait on
when your service needs a working network:

```ini
[Unit]
After=network-online.target
Wants=network-online.target
```

### PartOf

`PartOf=` means "if the other unit restarts or stops, I also restart or
stop." Useful for putting a worker service under the control of a parent
app server.

### Conflicts

`Conflicts=shutdown.target` is the common pattern — it prevents the unit
from being pulled into a shutdown.

---

## 6. User, group, and privilege dropping

Never run a web app as root if you can avoid it.

```ini
[Service]
User=www-data
Group=www-data
```

If the user doesn't exist, the unit fails. Create the user beforehand
with `useradd --system --no-create-home --shell /usr/sbin/nologin <name>`.

### DynamicUser

```ini
[Service]
DynamicUser=yes
StateDirectory=myapp
CacheDirectory=myapp
LogsDirectory=myapp
```

systemd creates a transient, random UID/GID for the lifetime of the unit.
Combined with `StateDirectory=`, `CacheDirectory=`, and `LogsDirectory=`,
you get an ephemeral account with automatically-managed directories
under `/var/lib/myapp/`, `/var/cache/myapp/`, `/var/log/myapp/`. Clean
and secure for new services.

### SupplementaryGroups

```ini
[Service]
User=myapp
SupplementaryGroups=ssl-cert adm
```

Add the service user to extra groups at start — no passwd/group edits
persist.

---

## 7. Filesystem sandboxing and hardening directives

This is the modern replacement for AppArmor profiles and chroot for many
services. Add as many of these as the service tolerates.

| Directive                   | Effect                                                                 |
|-----------------------------|------------------------------------------------------------------------|
| `ProtectSystem=strict`      | `/usr`, `/boot`, `/etc` become read-only for this process.             |
| `ProtectSystem=full`        | Same but `/etc` remains writable.                                      |
| `ProtectHome=true`          | `/home`, `/root`, `/run/user` become empty/inaccessible.               |
| `ProtectHome=read-only`     | Still readable.                                                        |
| `PrivateTmp=yes`            | Private `/tmp` and `/var/tmp` (own mount namespace).                   |
| `PrivateDevices=yes`        | Only `/dev/null`, `/dev/zero`, `/dev/random`, `/dev/urandom`, `/dev/tty`. |
| `PrivateNetwork=yes`        | No network at all — the service runs in its own net namespace.         |
| `PrivateUsers=yes`          | Separate user namespace — UIDs outside the service look like `nobody`. |
| `NoNewPrivileges=yes`       | `setuid`, `setgid`, `capabilities` can no longer be gained.            |
| `ProtectKernelTunables=yes` | `/proc/sys`, `/sys`, `/proc/sysrq-trigger` become read-only.           |
| `ProtectKernelModules=yes`  | Cannot load/unload kernel modules.                                     |
| `ProtectKernelLogs=yes`     | `/proc/kmsg`, `/dev/kmsg` hidden.                                      |
| `ProtectControlGroups=yes`  | `/sys/fs/cgroup` becomes read-only.                                    |
| `ProtectClock=yes`          | `settimeofday`, `clock_settime` blocked.                               |
| `ProtectHostname=yes`       | `sethostname` blocked.                                                 |
| `LockPersonality=yes`       | `personality()` locked.                                                |
| `MemoryDenyWriteExecute=yes`| Blocks W^X violations (no JIT unless disabled).                        |
| `RestrictRealtime=yes`      | Blocks `SCHED_FIFO`, `SCHED_RR`.                                       |
| `RestrictNamespaces=yes`    | Blocks user/mount/net/pid namespace creation.                          |
| `RestrictSUIDSGID=yes`      | Blocks `setuid`/`setgid` on created files.                             |
| `RemoveIPC=yes`             | Remove SysV IPC when service stops.                                    |

### Capability bounding

```ini
[Service]
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
```

Drops every Linux capability except the ones listed. `CAP_NET_BIND_SERVICE`
is the one you need to bind to ports below 1024 as a non-root user — the
answer to "how does nginx listen on 80 without being root."

### Read-write paths under ProtectSystem=strict

Combine with explicit write paths:

```ini
[Service]
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/myapp /var/lib/myapp /var/cache/myapp
InaccessiblePaths=/home /root
```

`ReadWritePaths=` punches holes in the read-only overlay. `ReadOnlyPaths=`
does the opposite. `InaccessiblePaths=` hides a path entirely.

### Syscall filtering

```ini
[Service]
SystemCallFilter=@system-service
SystemCallFilter=~@mount @debug @module @raw-io @reboot @swap @privileged
SystemCallErrorNumber=EPERM
```

The first line allows a high-level "system service" syscall group. The
`~` line then subtracts dangerous groups. `systemctl analyze syscall-filter`
lists the groups.

### Audit a unit's exposure

```bash
sudo systemd-analyze security nginx.service
```

This gives a score 0.0 (hardened) to 10.0 (wide-open). Work it downward.

---

## 8. Resource limits (cgroup controls)

systemd runs every service inside a cgroup. These directives translate
to cgroup limits without touching `/sys/fs/cgroup` by hand.

| Directive              | Meaning                                                             |
|------------------------|---------------------------------------------------------------------|
| `MemoryMax=512M`       | Hard cap. OOM-kill if exceeded.                                     |
| `MemoryHigh=400M`      | Soft cap. Throttled above this.                                     |
| `MemorySwapMax=0`      | No swap allowed for this service.                                   |
| `CPUQuota=50%`         | Max 50% of one core (200% = 2 full cores).                          |
| `CPUWeight=100`        | Relative share. Default 100; higher wins contention.                |
| `IOWeight=100`         | Block-IO share.                                                     |
| `TasksMax=512`         | Max processes/threads in this unit.                                 |
| `LimitNOFILE=65535`    | `ulimit -n` equivalent.                                             |
| `LimitNPROC=4096`      | `ulimit -u` equivalent.                                             |
| `LimitCORE=0`          | Disable core dumps.                                                 |

Inspect live usage:

```bash
systemctl status nginx                 # shows CPU, memory, tasks
systemd-cgtop                          # top-style view of all cgroups
systemctl show nginx -p MemoryCurrent  # scripted probes
```

---

## 9. Drop-in overrides with `systemctl edit`

Never edit `/lib/systemd/system/*.service` directly. Use drop-ins.

```bash
sudo systemctl edit nginx.service
```

This opens `/etc/systemd/system/nginx.service.d/override.conf` in your
editor. You only write the sections and directives you want to override
or add. Example:

```ini
[Service]
MemoryMax=2G
LimitNOFILE=100000
```

Save, exit. systemd auto-runs `daemon-reload` for drop-ins made via
`systemctl edit`. Restart the service to apply runtime changes:

```bash
sudo systemctl restart nginx
```

### Inspecting the merged unit

```bash
systemctl cat nginx                    # original + every drop-in
systemctl show nginx                   # all resolved properties
systemctl show nginx -p MemoryMax      # one property
```

### Reset a drop-in

```bash
sudo systemctl revert nginx            # removes drop-ins + local unit
```

### Edit a unit completely (not recommended)

```bash
sudo systemctl edit --full nginx.service
```

Creates a full unit copy at `/etc/systemd/system/nginx.service` that
shadows the packaged one. Drift risk — drop-ins are almost always better.

---

## 10. When you must `daemon-reload`

systemd caches unit files on first load. Any time you change a unit file
or drop-in **outside** of `systemctl edit`, you must tell systemd:

```bash
sudo systemctl daemon-reload
```

You need to do this after:

- Creating a new unit file in `/etc/systemd/system/`.
- Editing a unit file with `nano`, `vim`, or any non-`systemctl edit` flow.
- Installing a package that drops in new unit files (apt does this for you).
- Changing a drop-in by hand.

You do **not** need `daemon-reload` after:

- `systemctl edit` (handled automatically).
- Changing the contents of a config file referenced by the unit (e.g.
  editing `/etc/nginx/nginx.conf` — you reload nginx, not systemd).

`daemon-reload` does not restart running services. It only re-parses
unit files. You still need `systemctl restart <unit>` to apply changes
to a running service.

---

## 11. Inspecting and debugging units

### Status and health

```bash
systemctl status nginx                      # short status + last 10 log lines
systemctl is-active nginx                   # active / inactive / failed
systemctl is-enabled nginx                  # enabled / disabled / masked
systemctl is-failed nginx                   # failed / active
```

### Failed units

```bash
systemctl --failed                          # everything currently failed
systemctl list-units --state=failed
systemctl reset-failed                      # clear failed state for all
systemctl reset-failed nginx                # clear one
```

### Dependencies

```bash
systemctl list-dependencies nginx           # tree of what nginx needs
systemctl list-dependencies nginx --reverse # tree of what needs nginx
systemctl list-dependencies nginx --all     # expand .target entries
```

### Logs for one unit

```bash
journalctl -u nginx                         # everything, paged
journalctl -u nginx -n 100 --no-pager       # last 100 lines, no pager
journalctl -u nginx -f                      # follow live
journalctl -u nginx --since "10 min ago"
journalctl -u nginx --since "2024-12-01" --until "2024-12-02 08:00"
journalctl -u nginx -p err                  # only err and worse (priority ≤ 3)
journalctl -u nginx -p warning              # warnings and worse
journalctl -u nginx -k                      # kernel messages for this unit
journalctl -u nginx -o json-pretty          # structured output
```

Priorities: `emerg` (0), `alert` (1), `crit` (2), `err` (3), `warning`
(4), `notice` (5), `info` (6), `debug` (7).

### Boot-time analysis

```bash
systemd-analyze                              # total startup time
systemd-analyze blame                        # slowest unit first
systemd-analyze critical-chain               # bottleneck path
systemd-analyze time                         # kernel vs userspace
systemd-analyze plot > boot.svg              # graphical timeline
systemd-analyze verify /etc/systemd/system/myapp.service  # lint
```

### Show every property

```bash
systemctl show nginx                         # key=value dump
systemctl show nginx | grep -i memory
systemctl show nginx -p ActiveState,SubState,MainPID,LoadState
```

### Masking

```bash
sudo systemctl mask <unit>                   # disable so hard it can't start
sudo systemctl unmask <unit>
```

Masking creates a symlink to `/dev/null`. The unit cannot be started by
anything — even as a dependency. Use for services you never want to run
(e.g. `sudo systemctl mask apache2` on an nginx-only box to prevent
accidental starts).

---

## 12. Per-service operational notes

### nginx

```bash
sudo nginx -t                                # test config (ALWAYS before reload)
sudo nginx -t && sudo systemctl reload nginx # zero-downtime reload
sudo systemctl restart nginx                 # full restart (brief downtime)
sudo systemctl -l status nginx               # long form status
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

- `reload` is safe (master re-execs workers, in-flight requests finish).
- Binds to port 80/443 via `CAP_NET_BIND_SERVICE` in the unit — does not
  run as root after startup.
- Drop-in override example:

  ```ini
  [Service]
  LimitNOFILE=100000
  MemoryMax=2G
  ```

### apache2

```bash
sudo apache2ctl configtest                   # test config (ALWAYS before reload)
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo tail -f /var/log/apache2/error.log
sudo tail -f /var/log/apache2/access.log
sudo systemctl status apache2
```

- Configtest equivalent of `nginx -t`.
- Drop-in for MaxRequestWorkers etc. is not helpful — edit `mpm_*.conf`
  under `/etc/apache2/mods-available/` instead.
- Conflict note: you cannot run both `nginx` and `apache2` listening on
  the same port. Either reverse-proxy nginx in front of apache on 8080,
  or mask the one you don't need.

### mysql

```bash
sudo systemctl restart mysql                 # brief downtime; no reload
sudo journalctl -u mysql --since "10 min ago" --no-pager
mysql -e "SHOW STATUS LIKE 'Threads_connected';"
mysql -e "SHOW PROCESSLIST;"
```

- No graceful `reload`. Restart is the only way to reread `my.cnf`.
- Startup can take 30+ seconds on busy servers — `TimeoutStartSec=` of
  300s or more is sane.
- Log location: `/var/log/mysql/error.log`. On Ubuntu the unit tees
  errors into the journal too.

### postgresql

```bash
sudo systemctl reload postgresql             # re-reads postgresql.conf
sudo systemctl restart postgresql            # required for some config changes
sudo -u postgres psql -c "SELECT version();"
sudo -u postgres psql -c "\l"
sudo tail -f /var/log/postgresql/postgresql-*-main.log
```

- `reload` is safe for most `postgresql.conf` changes (check `pg_settings`
  column `context` — values `sighup` reload; `postmaster` need restart).
- The Ubuntu package uses a per-cluster service: `postgresql@14-main.service`
  is the actual daemon, `postgresql.service` is a wrapper target.

### php-fpm (php8.3-fpm, php8.2-fpm, etc.)

```bash
sudo php-fpm8.3 -t                           # test pool configs
sudo systemctl reload php8.3-fpm             # graceful, finishes in-flight
sudo systemctl restart php8.3-fpm            # hard restart
sudo tail -f /var/log/php8.3-fpm.log
```

- `reload` is truly graceful. Use it.
- Pool configs in `/etc/php/8.3/fpm/pool.d/*.conf`. Key tuning directives:
  `pm.max_children`, `pm.start_servers`, `pm.min_spare_servers`,
  `pm.max_spare_servers`, `pm.max_requests`, `request_terminate_timeout`.
- Socket location (Ubuntu default): `/run/php/php8.3-fpm.sock`. Nginx
  upstreams must match.

### redis

```bash
sudo systemctl restart redis-server          # unit name on Ubuntu/Debian
redis-cli ping                               # expects PONG
redis-cli -a "$REDIS_PASSWORD" info server
redis-cli -a "$REDIS_PASSWORD" info memory
```

- No safe `reload`. Restart on config changes.
- Unit is `redis-server.service` on Ubuntu/Debian, not `redis.service`.
- Set `maxmemory` and `maxmemory-policy` in `/etc/redis/redis.conf`. Also
  consider `MemoryMax=` in a drop-in for defense in depth.

### fail2ban

```bash
sudo systemctl reload fail2ban               # re-reads jail configs
sudo systemctl restart fail2ban              # full restart
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo tail -f /var/log/fail2ban.log
```

- `reload` rereads `/etc/fail2ban/jail.d/*.conf`.
- Ban list is persisted; a restart does not forgive current offenders.

### certbot.timer

```bash
systemctl status certbot.timer               # next run / last run
sudo systemctl list-timers | grep certbot
sudo certbot renew --dry-run                 # test the renewal path
sudo certbot certificates                    # all managed certs + expiry
```

- `certbot.timer` runs twice a day by default on Ubuntu. Don't add a
  cron; it's redundant.

### cron

```bash
crontab -l                                   # current user
sudo crontab -l                              # root
sudo systemctl status cron                   # Ubuntu unit name
sudo journalctl -u cron --since "1 hour ago" --no-pager
```

- On Ubuntu the unit is `cron.service`; on RHEL-family it's `crond.service`.
- For cron details (syntax, environment, gotchas) and how to convert a
  cron job into a systemd timer, see `timers-and-cron.md`.

---

## Sources

- `systemd.unit(5)`, `systemd.service(5)`, `systemd.exec(5)`, `systemd.resource-control(5)` man pages — the canonical reference.
- **Ubuntu Server Guide (Focal 20.04)**, Canonical (2020) — systemd unit examples, `systemctl status` output conventions.
- **Mastering Ubuntu**, Ghada Atef (2023) — Chapter: Service management with systemctl; unit file directory layout.
- **Linux System Administration for the 2020s** — modern patterns for sandboxed services and drop-in overrides.
- `systemd-analyze security` output on a reference Ubuntu 22.04 server for the hardening directives.
- Real-world operational notes from running nginx + apache2 + mysql + php-fpm + redis + fail2ban on production Ubuntu servers.
