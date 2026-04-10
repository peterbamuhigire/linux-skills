# APT Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

APT (Advanced Package Tool) is the package management frontend on
Debian and Ubuntu. It sits on `dpkg` and adds dependency resolution,
repository handling, authentication, and upgrade planning. This
reference covers the commands, files, and workflows that matter on a
production server: sources, pinning, holds, PPAs, modern GPG key
management, phasing, and recovery from broken dependency states. Use
`apt` interactively, `apt-get` in scripts, and read `dpkg` output
carefully.

## Table of contents

- [Architecture](#architecture)
- [apt vs apt-get vs aptitude](#the-apt-family-apt-vs-apt-get-vs-aptitude)
- [Sources and deb822](#sources-sourceslist-and-sourceslistd)
- [APT configuration](#apt-configuration-etcaptaptconfd)
- [Update, upgrade, install, purge, autoremove](#updating-and-upgrading)
- [Holds with apt-mark](#holds-apt-mark)
- [Pinning](#pinning-with-etcaptpreferencesd)
- [PPAs and GPG keys](#ppas-and-add-apt-repository)
- [Phasing and held-back packages](#phasing-ubuntus-gradual-rollout)
- [dpkg output and apt-cache](#reading-dpkg-output-during-install-and-upgrade)
- [Dependency failures and recovery](#dependency-failures-and-recovery)
- [Worked examples](#worked-examples)
- [Sources](#sources)

## Architecture

APT is layered:

- `dpkg` — lowest layer. Installs `.deb` archives, runs maintainer
  scripts (`preinst`, `postinst`, `prerm`, `postrm`), tracks installed
  files. No dependency resolution. Database in `/var/lib/dpkg/`.
- `libapt-pkg` — C++ library that reads sources, authenticates
  `Packages` indices, and computes dependency graphs.
- `apt-get`, `apt-cache`, `apt-mark` — stable, script-safe CLIs with
  machine-parseable output.
- `apt` — modern interactive CLI. Output format explicitly unstable,
  never parse it in scripts.
- `aptitude` — ncurses/CLI frontend with its own resolver. Useful for
  interactively untangling broken dependencies.

## The apt family: apt vs apt-get vs aptitude

The Ubuntu Server Guide is explicit:

> While apt is a command-line tool, it is intended to be used interactively,
> and not to be called from non-interactive scripts. The apt-get command
> should be used in scripts (perhaps with the --quiet flag).
> — Ubuntu Server Guide, *Package Management*

- **Interactive shell** — use `apt`.
- **Scripts, cron, Ansible, cloud-init** — use `apt-get` / `apt-cache`
  with `DEBIAN_FRONTEND=noninteractive` for anything that might prompt.
- **Broken dependencies** — use `aptitude`. Its resolver proposes
  downgrades and removals that `apt-get` refuses.

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends nginx
```

## Sources: sources.list and sources.list.d

APT reads package sources from:

- `/etc/apt/sources.list` — legacy single file, often minimal on modern
  Ubuntu (official repos live in `sources.list.d/ubuntu.sources`).
- `/etc/apt/sources.list.d/*.list` — third-party, traditional one-line.
- `/etc/apt/sources.list.d/*.sources` — modern deb822, preferred.

Traditional one-line format:

```text
# /etc/apt/sources.list.d/example.list
deb [signed-by=/etc/apt/keyrings/example.gpg] https://repo.example.com/apt stable main
```

Fields: `deb` or `deb-src`, optional `[options]`, URI, suite,
components. The `signed-by` option pins the repo to a specific
keyring so the key is never globally trusted.

## Deb822 sources format (.sources files)

deb822 is structured, multi-line, and preferred in modern Ubuntu. A
single `.sources` file can declare multiple URIs, suites, and components:

```text
# /etc/apt/sources.list.d/nodesource.sources
Types: deb
URIs: https://deb.nodesource.com/node_20.x
Suites: nodistro
Components: main
Signed-By: /etc/apt/keyrings/nodesource.gpg
Architectures: amd64 arm64
```

Advantages: keys referenced by absolute path, multiple suites per
entry, comments tolerated, easy to template from Ansible. Convert an
old one-liner by deleting the `.list` file and writing an equivalent
`.sources` file.

## APT configuration: /etc/apt/apt.conf.d/

Configuration is assembled from every file under `/etc/apt/apt.conf.d/`
in lexical order; later files override earlier ones. Never edit
`apt.conf` directly — drop a new file with a high number prefix.

Common files shipped by Ubuntu:

| File | Purpose |
|---|---|
| `01autoremove` | Which packages count as "automatically installed" |
| `20auto-upgrades` | Whether to run daily update and upgrade |
| `50unattended-upgrades` | Full unattended-upgrades policy |
| `70debconf` | Debconf frontend |

```bash
apt-config dump                          # effective config
apt-config dump | grep -i 'periodic'     # daily timer keys
```

Disable recommended packages globally:

```text
# /etc/apt/apt.conf.d/99no-recommends
APT::Install-Recommends "false";
APT::Install-Suggests "false";
```

## Updating and upgrading

`apt update` refreshes the local index and never modifies installed
packages. `apt upgrade` upgrades without removing anything.
`apt full-upgrade` (same as `apt-get dist-upgrade`) removes packages
when necessary to satisfy an upgrade.

```bash
sudo apt update                 # refresh indices
apt list --upgradable           # what would be upgraded
sudo apt upgrade                # conservative
sudo apt full-upgrade           # allow removals
```

Use `full-upgrade` for normal release updates. A stuck `upgrade` with
packages "kept back" is almost always solved by running `full-upgrade`.

## Installing, removing, purging

```bash
sudo apt install nginx                          # install with recommends
sudo apt install --no-install-recommends nginx  # core only
sudo apt install nginx=1.24.0-1ubuntu1          # specific version
sudo apt install ./local-package_1.0_amd64.deb  # local .deb
sudo apt reinstall nginx
sudo apt remove nginx        # remove binaries, keep config in /etc
sudo apt purge nginx         # remove binaries AND config
sudo apt purge --auto-remove nginx   # also drop orphan deps
```

Always `purge` when uninstalling something for good on a server —
leftover config files cause silent drift and confuse audits.

## autoremove and clean

- `apt autoremove` — remove orphan dependencies. Review before
  confirming; kernel packages often appear here.
- `apt clean` — empty `/var/cache/apt/archives/` completely.
- `apt autoclean` — remove only archives no longer downloadable.

```bash
sudo apt autoremove --purge
sudo apt clean
```

## Holds: apt-mark

Holding freezes a package at its current version; APT refuses to
upgrade, downgrade, or remove it until released.

```bash
sudo apt-mark hold linux-image-generic
apt-mark showhold
sudo apt-mark unhold linux-image-generic
sudo apt-mark auto nginx         # mark as auto-installed
sudo apt-mark manual nginx       # mark as manually installed
apt-mark showmanual | head
```

Always document *why* a package is held. Keep a flat file such as
`/etc/apt/linux-skills-holds.txt`:

```text
# package              reason                                set-by date
linux-image-generic    locked until driver XYZ tested        peter  2024-03-12
nodejs                 pinned to 20.x LTS for prod API       peter  2024-03-20
```

## Pinning with /etc/apt/preferences.d/

Pinning tells APT which version to prefer when multiple are available
(distribution vs PPA vs backport). Pins live in `/etc/apt/preferences.d/`,
one file per rule set.

Pin priorities:

| Priority | Meaning |
|---|---|
| `< 0` | Never install |
| `1-99` | Install only if no installed version exists |
| `500` | Default for an available package |
| `990` | Default for the target release |
| `1000+` | Always preferred, may downgrade |
| `1001+` | Force, even across release boundaries |

Pin by origin, release, or version:

```text
# /etc/apt/preferences.d/nodejs-nodesource
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 1001
```

```text
# /etc/apt/preferences.d/backports-certbot
Package: certbot python3-certbot*
Pin: release a=jammy-backports
Pin-Priority: 990
```

```text
# /etc/apt/preferences.d/postgresql-16
Package: postgresql postgresql-*
Pin: version 16.*
Pin-Priority: 1001
```

Verify the effective priority with `apt-cache policy nginx`.

## PPAs, third-party repos, and GPG keys

A PPA is a Launchpad-hosted repo; adding one is a trust decision —
you are authorising a new signing key.

```bash
sudo apt install software-properties-common
sudo add-apt-repository ppa:ondrej/php
sudo apt update
sudo add-apt-repository --remove ppa:ondrej/php
```

`add-apt-repository` drops a `.sources` file in
`/etc/apt/sources.list.d/` and fetches the signing key into
`/etc/apt/keyrings/` on modern releases. List everything:

```bash
grep -rh ^deb /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null
```

### Modern keyring layout vs legacy

Modern Ubuntu no longer trusts a single global keyring. Every
third-party repo carries its own key file referenced by `signed-by=`.

- **Modern (recommended)** — `/etc/apt/keyrings/`, directory mode
  `0755`, files `0644` owned `root:root`, referenced by `Signed-By:`
  (deb822) or `[signed-by=...]` (one-line).
- **Legacy (deprecated)** — `/etc/apt/trusted.gpg` (monolithic) and
  `/etc/apt/trusted.gpg.d/*.gpg` (per-file but globally trusted). Do
  not add keys here on new systems. `apt-key add` is removed in recent
  Ubuntu — never use it.

Cross-check fingerprints against the upstream project's security page
before trusting any new key. See *Worked examples* for the full flow.

## Phasing: Ubuntu's gradual rollout

Ubuntu uses *phased updates*: new versions roll out to a percentage of
systems over several days. Until your system is selected, `apt upgrade`
reports the package as "kept back":

```text
The following packages have been kept back:
  libc6 libc-bin
```

Check the phase status:

```bash
apt-cache policy libc6
# 500 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 Packages
# Pinned to phased update at 50%
```

Options: wait (the next apt-daily cycle may promote you), force the
upgrade with `apt install libc6 libc-bin` by name, or disable phasing
globally for a staging box:

```text
# /etc/apt/apt.conf.d/99-no-phased-updates
APT::Get::Always-Include-Phased-Updates "true";
Update-Manager::Always-Include-Phased-Updates "true";
```

## Held back: reading the output correctly

"Held back" from `apt upgrade` has five possible causes:

1. **Phased update** — staged rollout, your machine not yet selected.
2. **`apt-mark hold`** — explicit pin. Check `apt-mark showhold`.
3. **Dependency conflict** — new version needs something uninstallable.
   `apt full-upgrade` resolves by allowing removals.
4. **Kernel meta-package** — kernels install side by side, so `upgrade`
   holds them. `full-upgrade` promotes them.
5. **Pin priority** — `/etc/apt/preferences.d/` blocking the new version.

Triage:

```bash
apt-mark showhold
apt-cache policy <pkg>
sudo apt full-upgrade -s          # simulate
sudo apt install <pkg>            # force specific install
```

## Reading dpkg output during install and upgrade

Every `apt` operation calls `dpkg` to unpack and configure packages:

```text
Preparing to unpack .../nginx_1.24.0-1ubuntu1_amd64.deb ...
Unpacking nginx (1.24.0-1ubuntu1) over (1.22.1-9ubuntu0.1) ...
Setting up nginx (1.24.0-1ubuntu1) ...
Processing triggers for man-db (2.10.2-1) ...
```

- **Unpacking** — archive extracted; old binaries still on disk.
- **Setting up** — `postinst` runs, restarts services, migrates data.
  Failures here leave the package half-configured.
- **Processing triggers** — deferred work like `update-initramfs`,
  `update-grub`, `ldconfig`.

When something fails:

```text
Setting up postgresql-16 (16.2-1ubuntu1) ...
dpkg: error processing package postgresql-16 (--configure):
 installed postgresql-16 package post-installation script subprocess returned error exit status 1
E: Sub-process /usr/bin/dpkg returned an error code (1)
```

The first line after `Setting up <pkg>` is the real error. "post-installation
script subprocess returned error" always means `postinst` failed. List
every package not in the clean `ii` state:

```bash
dpkg -l | awk '$1 != "ii" && $1 != ""'
```

## apt-cache: querying the cache

```bash
apt-cache policy                    # every source, priority, arch
apt-cache policy nginx              # installed, candidate, sources, pins
apt-cache show nginx                # full package stanza
apt-cache depends nginx             # forward deps
apt-cache rdepends --installed nginx # reverse deps (installed only)
apt-cache madison nginx             # version table across all origins
apt-cache search '^postgresql-1[56]$'
```

`apt-cache policy` is the single most useful command when something
goes wrong.

## Dependency failures and recovery

**Interrupted dpkg run** (power loss, `kill -9`):

```bash
sudo dpkg --configure -a        # finish half-configured installs
sudo apt --fix-broken install   # finish half-unpacked installs
```

**`apt install` refuses because of conflicts**:

```bash
sudo apt install -s <package>   # dry run, read proposed removals
sudo aptitude install <package> # aptitude's resolver offers alternatives
```

**A held package is blocking upgrade**:

```bash
apt-mark showhold
sudo apt-mark unhold <package>
sudo apt full-upgrade
```

**Post-install script fails on every run**:

```bash
dpkg -l | grep -E '^iF|^iU|^rc'   # half-configured / config-only
sudo dpkg --configure <package>    # retry postinst
sudo apt install --reinstall <package>
# last resort:
sudo dpkg --purge --force-all <package>
sudo apt install <package>
```

**"Hash sum mismatch" on `apt update`** (mirror glitch):

```bash
sudo rm -rf /var/lib/apt/lists/*
sudo apt clean
sudo apt update
```

## Worked examples

### Add a third-party repo securely (deb822 + keyring)

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
gpg --show-keys /etc/apt/keyrings/hashicorp.gpg   # verify fingerprint

sudo tee /etc/apt/sources.list.d/hashicorp.sources > /dev/null <<'EOF'
Types: deb
URIs: https://apt.releases.hashicorp.com
Suites: jammy
Components: main
Signed-By: /etc/apt/keyrings/hashicorp.gpg
Architectures: amd64 arm64
EOF

sudo apt update && sudo apt install terraform
```

### Pin a package to a specific origin

```bash
sudo tee /etc/apt/preferences.d/nodejs > /dev/null <<'EOF'
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 1001
EOF
apt-cache policy nodejs
```

### List packages installed from a specific repo

```bash
aptitude search '?narrow(?installed, ?origin(deb.nodesource.com))'
```

### Find which package owns a file

```bash
dpkg -S /etc/nginx/nginx.conf      # nginx-common: /etc/nginx/nginx.conf
dpkg -L nginx-common | head        # reverse: files shipped by a package
```

Empty output from `dpkg -S` means the file was not installed by a
package — it was created by a postinst, by hand, or by a running
process. Common audit finding.

### Reinstall a package cleanly

```bash
sudo apt install --reinstall -o Dpkg::Options::="--force-confask,confnew" nginx
```

For a catastrophic state: `sudo apt purge nginx nginx-common nginx-core
&& sudo rm -rf /etc/nginx && sudo apt install nginx`.

### Snapshot the manually-installed list (for rebuilding)

```bash
apt-mark showmanual | sort -u > /root/package-list.txt
# on the new server: apt install $(cat package-list.txt)
```

## Sources

- Ghada Atef, *Mastering Ubuntu: A Comprehensive Guide to Linux's
  Favorite*, 2023 — Ch III.III *Installing and managing software
  packages*; Ch IV.III *Commands and utilities for system administration*.
- Canonical, *Ubuntu Server Guide Documentation (Focal 20.04 LTS)*,
  2020 — *Package Management* chapter (Apt, Aptitude, dpkg,
  APT Configuration, Extra Repositories, Automatic Updates).
- `apt(8)`, `apt-get(8)`, `apt-cache(8)`, `apt-mark(8)`, `apt.conf(5)`,
  `sources.list(5)`, `apt_preferences(5)`, `dpkg(1)` manual pages.
