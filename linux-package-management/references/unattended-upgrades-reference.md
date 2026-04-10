# Unattended-Upgrades Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

`unattended-upgrades` is the background security-patch service on
Debian and Ubuntu. It reads the same apt sources as a human operator,
filters through an allow list, and installs approved updates without
prompting. On a production server this is the difference between
"patched within 24 hours of CVE disclosure" and "rooted next Tuesday".

This reference covers the package layout, the two config files
(`50unattended-upgrades`, `20auto-upgrades`), allowed-origins syntax,
the blacklist, mail notifications, automatic reboot on kernel updates,
systemd timers, and a complete production web-server configuration.

## Table of contents

- [Package layout](#package-layout)
- [The two config files](#the-two-config-files-50unattended-upgrades-and-20auto-upgrades)
- [Allowed-Origins](#allowed-origins-which-suites-get-patched)
- [Package-Blacklist](#package-blacklist-what-never-gets-touched)
- [Mail, reboot, and DevRelease](#mail-notifications)
- [Dry run, forced run, logs](#dry-run-and-forced-run)
- [Systemd timers and reboot-required](#systemd-timers-apt-daily-and-apt-daily-upgrade)
- [Complete production web server config](#complete-production-web-server-config)
- [Sources](#sources)

## Package layout

Two packages do the work:

- **`unattended-upgrades`** — the Python program that runs upgrades,
  reads the allow list, honours the blacklist, sends mail, and
  triggers automatic reboots. Ships `/usr/bin/unattended-upgrade`,
  `/etc/apt/apt.conf.d/50unattended-upgrades`, and a systemd service.
- **`update-notifier-common`** — installs the hooks that create
  `/var/run/reboot-required` and `/var/run/reboot-required.pkgs` after
  a kernel or glibc upgrade. Required on every server for reboot
  detection to work.

```bash
sudo apt install unattended-upgrades update-notifier-common
dpkg -l unattended-upgrades update-notifier-common
systemctl list-timers apt-daily.timer apt-daily-upgrade.timer
```

The Ubuntu Server Guide sums it up:

> The unattended-upgrades package can be used to automatically install
> updated packages and can be configured to update all packages or just
> install security updates.
> — Ubuntu Server Guide, *Automatic Updates*

## The two config files: 50unattended-upgrades and 20auto-upgrades

Configuration is split across two files in `/etc/apt/apt.conf.d/`, and
the split matters.

### `/etc/apt/apt.conf.d/20auto-upgrades`

The on/off switch. Four `"0"`/`"1"` flags:

```text
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
```

- `Update-Package-Lists` — run `apt update` from the timer. Must be
  `1` for anything else to work.
- `Download-Upgradeable-Packages` — pre-download so the upgrade window
  is short.
- `AutocleanInterval` — days between `apt-get autoclean` runs.
- `Unattended-Upgrade` — run `unattended-upgrade` from the second
  timer. Set to `0` to stage: download but never install.

### `/etc/apt/apt.conf.d/50unattended-upgrades`

The policy file: which origins to patch, what to skip, reboot,
notifications. Key stanzas are detailed below.

Separation is deliberate. Flip `20auto-upgrades` to disable automatic
updates on a staging box while leaving policy intact.

## Allowed-Origins: which suites get patched

The most important setting in `50unattended-upgrades`. Only packages
whose `origin:archive` matches one of these patterns are eligible for
upgrade. `${distro_id}` expands to `Ubuntu`/`UbuntuESM`;
`${distro_codename}` to `jammy`/`noble`/`focal`; `//` is the comment.

**Security-only (production, recommended):**

```text
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
```

Normal updates still require a human running `apt full-upgrade` —
exactly what you want on a server where unplanned feature upgrades
cause outages.

**Allow-listing a third-party origin** (e.g. Ondrej Nginx PPA):

```text
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "LP-PPA-ondrej-nginx-mainline:${distro_codename}";
};
```

Find the origin string via `apt-cache policy <pkg>`; look for `o=`
(origin) and `a=` (archive). Unattended-upgrades matches
`origin:archive`.

## Package-Blacklist: what never gets touched

Some packages are too risky to upgrade unattended: databases with
manual migrations, hand-tuned kernels, custom libraries.

```text
Unattended-Upgrade::Package-Blacklist {
    "linux-image-.*";
    "linux-headers-.*";
    "postgresql-16";
    "mysql-server";
    "docker-ce";
    "docker-ce-cli";
};
```

Entries are regular expressions. A blacklisted package is skipped
silently, but if a matching package has an outstanding security
advisory the skip is logged and, with mail configured, reported.

## Mail, reboot, and DevRelease

```text
Unattended-Upgrade::Mail "ops@example.com";
Unattended-Upgrade::MailReport "on-change";
```

`MailReport` values: `always` (every run, noisy), `only-on-error`
(minimum for production), `on-change` (recommended — mail whenever
packages were installed).

Mail needs an outbound MTA: `postfix` in satellite-smarthost mode, or
`msmtp-mta`. Without an MTA mail is silently dropped.

```bash
sudo apt install postfix mailutils
# select "Satellite system", then edit /etc/postfix/main.cf:
# relayhost = [smtp.example.com]:587
echo "test" | mail -s "uu test $(hostname)" ops@example.com
```

Reboot control (after kernel or glibc updates the running process
tree is on the old version):

```text
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
```

- `Automatic-Reboot` — master switch; reboot when
  `/var/run/reboot-required` exists after a successful upgrade.
- `Automatic-Reboot-WithUsers "false"` — do not reboot while any
  interactive user is logged in. Safe default for SSH-managed boxes.
- `Automatic-Reboot-Time "HH:MM"` — wall-clock time. `"now"` reboots
  immediately.

`DevRelease` (`auto`/`true`/`false`) controls running on Ubuntu
development releases; leave at `auto` or `false` on production.

## Dry run, forced run, logs

```bash
sudo unattended-upgrade --dry-run -v    # smoke test after config edits
sudo unattended-upgrade -v              # run now, honour config
sudo unattended-upgrade -d              # debug logging
```

`--dry-run -v` parses every `apt.conf.d/` file, enumerates
Allowed-Origins, lists every upgradable package, and marks each as
"to install", "skipped (blacklisted)", or "skipped (not in
allowed-origins)". If a package you expected to be patched shows up
under "skipped", your origin string is wrong.

Logs live in:

- `/var/log/unattended-upgrades/unattended-upgrades.log` — one entry
  per run with packages installed and errors.
- `/var/log/unattended-upgrades/unattended-upgrades-dpkg.log` — raw
  dpkg output. Read this when something failed.
- `/var/log/dpkg.log` — normal dpkg log.
- `journalctl -u unattended-upgrades.service` — systemd summary.

Rotation is handled by `/etc/logrotate.d/unattended-upgrades`
(weekly, several rotations kept).

## Systemd timers: apt-daily and apt-daily-upgrade

Two timers drive everything. They are shipped by `apt` itself, not
`unattended-upgrades`.

- **`apt-daily.timer`** — runs `/usr/lib/apt/apt.systemd.daily update`,
  refreshing sources and pre-downloading. Controlled by
  `Update-Package-Lists` and `Download-Upgradeable-Packages` in
  `20auto-upgrades`.
- **`apt-daily-upgrade.timer`** — runs
  `/usr/lib/apt/apt.systemd.daily install`, invoking
  `unattended-upgrade`. Controlled by `Unattended-Upgrade` in
  `20auto-upgrades`.

```bash
systemctl list-timers apt-daily.timer apt-daily-upgrade.timer
systemctl cat apt-daily-upgrade.timer
```

Both timers use `RandomizedDelaySec` to stagger runs — you cannot
predict fire time to the second. Force a run manually:

```bash
sudo systemctl start apt-daily.service
sudo systemctl start apt-daily-upgrade.service
# or directly:
sudo /usr/lib/apt/apt.systemd.daily install
```

Disable on a staging box by masking the timer or flipping the switch:

```bash
sudo systemctl disable --now apt-daily-upgrade.timer
```

### /var/run/reboot-required

After installing a reboot-triggering package (`linux-image-*`,
`libc6`, `dbus`), the postinst calls
`/usr/share/update-notifier/notify-reboot-required` which creates:

- `/var/run/reboot-required` — flag file, presence means "reboot needed".
- `/var/run/reboot-required.pkgs` — one triggering package per line.

```bash
test -f /var/run/reboot-required && cat /var/run/reboot-required.pkgs
```

`unattended-upgrades` checks this file after every run and, if
`Automatic-Reboot "true"`, schedules the reboot. With
`Automatic-Reboot "false"` the flag sits until a human acts —
nightly monitoring must catch it.

## Complete production web server config

Production configuration for a public-facing Nginx + PHP-FPM + MariaDB
server implementing: (a) security-only updates, (b) mail on any
action, (c) reboot 03:00-04:00 if kernel updated, (d) blacklist of
high-risk packages.

### `/etc/apt/apt.conf.d/20auto-upgrades`

```text
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
```

### `/etc/apt/apt.conf.d/50unattended-upgrades`

```text
// Managed by linux-package-management skill. Do not edit by hand.

// (a) Security-only. Feature upgrades go through sk-apt-upgrade-safe.
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// (d) High-risk packages requiring human coordination.
Unattended-Upgrade::Package-Blacklist {
    "linux-image-.*";
    "linux-headers-.*";
    "linux-generic";
    "linux-virtual";
    "mariadb-server";
    "mariadb-server-core-.*";
    "mysql-server";
    "postgresql";
    "postgresql-1[0-9]";
    "docker-ce";
    "docker-ce-cli";
    "containerd.io";
};

Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";

// (b) Mail on any action for audit trail.
Unattended-Upgrade::Mail "ops@example.com";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::MailOnlyOnError "false";

// (c) Reboot between 03:00 and 04:00 if a kernel update landed.
//     Refuse to reboot while an SSH user is logged in.
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Verbose "true";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
```

### Monthly verification checklist

```bash
sudo unattended-upgrade --dry-run -v           # config parses, actions sane
systemctl list-timers apt-daily.timer apt-daily-upgrade.timer
echo "smoke" | mail -s "uu test $(hostname)" ops@example.com
ls -la /var/log/unattended-upgrades/
test -f /var/run/reboot-required && cat /var/run/reboot-required.pkgs
```

Rerun once a month. Unattended-upgrades is the service that silently
stops working (broken MTA, wrong origin, full disk) while nobody
notices until a public CVE is weeks old on the box.

## Sources

- Canonical, *Ubuntu Server Guide Documentation (Focal 20.04 LTS)*,
  2020 — *Automatic Updates* and *Notifications* sections of the
  Package Management chapter; *apt.conf(5)* reference.
- Ghada Atef, *Mastering Ubuntu: A Comprehensive Guide to Linux's
  Favorite*, 2023 — Chapter III.III and Chapter VI on Ubuntu servers.
- `unattended-upgrade(8)`, `apt.conf(5)`, `apt_preferences(5)`,
  `/usr/share/doc/unattended-upgrades/README.md`, and
  `/etc/apt/apt.conf.d/50unattended-upgrades` default comments.
- `systemd.timer(5)`, `apt-daily.timer(8)`,
  `apt-daily-upgrade.timer(8)`.
