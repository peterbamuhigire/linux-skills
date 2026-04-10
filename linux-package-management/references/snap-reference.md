# Snap Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Snap is Canonical's sandboxed packaging system. A snap ships its
runtime, libraries, and binaries as a squashfs image mounted read-only
under `/snap/<name>/<revision>/`. Unlike apt, snaps refresh themselves
in the background and keep every revision for rollback. On a server,
snap is a trade-off: automatic security updates and clean rollback, at
the cost of the fine-grained control you get with apt holds and
pinning. This reference covers architecture, daily commands, channels,
refresh scheduling, services, interfaces, and apt-vs-snap trade-offs.

## Table of contents

- [Architecture](#architecture)
- [Install, refresh, remove, revert](#install-refresh-remove-revert)
- [Listing installed snaps](#listing-installed-snaps)
- [Channels: track, risk, branch](#channels-track-risk-branch)
- [Revisions and rollback](#revisions-and-rollback)
- [Refresh scheduling, hold, and inhibition](#refresh-scheduling-and-hold)
- [Confinement and interfaces](#confinement-strict-classic-devmode)
- [Snap services and configuration](#snap-services)
- [Snapshots and restore](#snapshots-and-restore)
- [Snap vs apt and common server snaps](#snap-vs-apt-trade-offs)
- [Restricting auto-refresh on servers](#restricting-auto-refresh-on-servers)
- [Worked examples](#worked-examples)
- [Sources](#sources)

## Architecture

- **snapd** — the daemon under `snapd.service`. Manages install,
  refresh, revert, and interface connections. REST API at
  `/run/snapd.socket`.
- **squashfs images** — each snap is a compressed read-only filesystem
  mounted at `/snap/<name>/<revision>/`. Two or more revisions may be
  mounted simultaneously.
- **Current symlink** — `/snap/<name>/current` points at the active
  revision. Flipping this symlink is what refresh and revert actually
  do at the filesystem level.
- **Writable data** — `/var/snap/<name>/<revision>/` per revision,
  `/var/snap/<name>/common/` shared across revisions, and
  `~/snap/<name>/<revision>/` per-user.
- **Store** — `snap install` fetches from snapcraft.io. Enterprises
  can run a local Snap Store Proxy.
- **Assertions** — every snap ships signed assertions binding it to a
  publisher key. snapd refuses unsigned or mismatched content.

Check the daemon state:

```bash
sudo systemctl status snapd.service snapd.socket
snap version                    # client and server version
snap changes                    # recent snapd operations
```

## Install, refresh, remove, revert

```bash
sudo snap install certbot                    # latest stable
sudo snap install certbot --classic          # classic confinement
sudo snap install microk8s --channel=1.29/stable

sudo snap refresh                            # refresh all now
sudo snap refresh certbot                    # one snap
sudo snap refresh --list                     # what would refresh

sudo snap remove certbot                     # keep snapshot
sudo snap remove --purge certbot             # drop snapshot too

sudo snap revert certbot                     # roll back to previous
sudo snap revert certbot --revision=2140     # specific revision
```

Every operation is transactional; a failed refresh reverts
automatically. Inspect the log with `snap changes`, `snap change 42`,
and `snap tasks 42`.

## Listing installed snaps

```bash
snap list                       # active revisions only
snap list --all                 # include disabled old revisions
snap info certbot               # store metadata + channels
snap find certbot               # search the store
```

`snap list --all` shows rollback capacity. The `disabled` row is the
previous revision, kept on disk ready for `snap revert`. snapd keeps
up to `refresh.retain` revisions (default 2).

```text
Name     Version   Rev   Tracking       Publisher   Notes
certbot  2.7.4     3462  latest/stable  certbot*    classic
certbot  2.7.1     3024  latest/stable  certbot*    classic,disabled
core22   20240111  1122  latest/stable  canonical*  base
```

## Channels: track, risk, branch

A channel has three parts: `track/risk/branch`.

- **Track** — major version line (`latest`, `1.29`, `24`).
- **Risk** — `stable`, `candidate`, `beta`, `edge`, from most to least
  stable.
- **Branch** — optional short-lived fork for testing fixes.

Example channel strings: `latest/stable`, `1.29/stable`,
`24/candidate`, `latest/edge/fix-startup-crash`.

```bash
snap info microk8s                                 # all channels
sudo snap install microk8s --channel=1.29/stable
sudo snap refresh microk8s --channel=1.30/stable   # switch track
sudo snap switch --channel=1.29/stable microk8s    # without refresh
```

**Production rule:** pin the track. `latest/stable` rolls major
versions whenever upstream releases one, which is almost never what
you want on a server. Pin `1.29/stable` and promote deliberately.

## Revisions and rollback

Every refresh increments the revision. snapd keeps `refresh.retain`
previous revisions (default 2, max 20). Rollback is instant because
both revisions are already mounted.

```bash
snap list --all certbot
sudo snap revert certbot                       # -> previous revision
sudo snap revert certbot --revision=3024
sudo snap refresh certbot                      # forward to latest
sudo snap set system refresh.retain=5          # keep more history
```

Data under `/var/snap/<name>/<rev>/` is per-revision and is *not*
rolled back — each revision has its own directory. Data under
`/var/snap/<name>/common/` is shared and survives rollback.

## Refresh scheduling and hold

By default snapd checks for refreshes roughly four times a day.

```bash
sudo snap refresh --time                        # next and last refresh
sudo snap set system refresh.timer=sun,03:00-04:00  # Sun 03:00-04:00
sudo snap set system refresh.timer=02:00-04:00      # every day 02-04
sudo snap refresh --hold=24h                    # hold all 24 hours
sudo snap refresh --hold=24h certbot            # hold one snap
sudo snap refresh --hold                        # hold indefinitely
sudo snap refresh --unhold                      # release
```

`refresh.hold` is the sysadmin's seatbelt: set while debugging, clear
afterwards. Never leave it held indefinitely — snap refreshes are the
only way snaps receive security patches.

**Refresh inhibition during active use:** snapd will not refresh a
snap while it is running, postponing until the app closes. After 14
days of deferrals it force-refreshes anyway. Inspect with
`snap refresh --list` and `snap warnings`. For a server-side snap like
`certbot` invoked ad-hoc, inhibition rarely matters.

## Confinement: strict, classic, devmode

Three modes:

- **strict** (default) — AppArmor + seccomp + cgroup sandbox. The snap
  sees only its own directories plus connected interfaces.
- **classic** — full system access, like an apt package. Required for
  apps that need the whole filesystem (IDEs, `lxd`, `certbot`,
  `microk8s`). Must install with `--classic` and requires store
  review-team approval.
- **devmode** — strict with all denials demoted to warnings. Author-
  only.

```bash
snap info certbot | grep confinement   # confinement: classic
```

Classic snaps are outside the sandbox — treat them with the trust of
an apt package from a third-party repo.

## Interfaces and connections

An interface is a declared capability — "access home directory", "talk
to NetworkManager". A snap declares plugs (needs) and slots (provides).
snapd auto-connects safe ones at install; the rest are manual.

```bash
snap connections                        # all snaps
snap connections certbot                # one snap's plugs and slots
sudo snap connect certbot:home          # connect a plug
sudo snap disconnect certbot:home
```

A `-` in the Slot column of `snap connections` means the plug is
declared but unconnected. Some snaps refuse to run without certain
plugs — fix with `snap connect`.

## Snap services

Snaps ship daemons as `snap.<snap>.<service>.service` systemd units.

```bash
snap services                           # all snap services
snap services microk8s
sudo snap start  microk8s.daemon-kubelite
sudo snap stop   microk8s.daemon-kubelite
sudo snap restart microk8s
sudo snap logs   microk8s -n 200        # tail logs
# or via systemd directly:
systemctl status snap.microk8s.daemon-kubelite.service
journalctl -u snap.microk8s.daemon-kubelite.service --since '1 hour ago'
```

## Snap configuration: get and set

```bash
sudo snap get system                    # core snap config
sudo snap get system refresh            # just refresh.* keys
sudo snap set microk8s rbac=true
sudo snap unset microk8s rbac           # reset to default
```

System-wide keys worth knowing:

| Key | Purpose |
|---|---|
| `refresh.timer` | When automatic refreshes run |
| `refresh.hold` | Pause refreshes until a given time |
| `refresh.retain` | How many old revisions to keep (2-20) |
| `refresh.metered` | `hold` to skip refreshes on metered links |
| `proxy.http` / `proxy.https` | HTTP proxy for snapd |

## Snapshots and restore

snapd can snapshot the writable data of a snap before risky refreshes.

```bash
sudo snap save                          # snapshot every snap
sudo snap save certbot                  # one snap
snap saved                              # list snapshot sets
sudo snap restore 7                     # restore all in set 7
sudo snap restore 7 certbot             # restore just certbot
sudo snap forget 7                      # delete a set
```

Snapshots live under `/var/lib/snapd/snapshots/` and contain only
`/var/snap/<name>/`, not binaries — snapshots assume you can reinstall
the snap from the store.

## Snap vs apt trade-offs

Prefer **snap** when:

- The upstream ships a snap and not an apt package (`microk8s`,
  recent `lxd`, `snapcraft`).
- You want automatic minor updates without an unattended-upgrades
  exception.
- You want clean rollback of one component.
- You want sandbox isolation — e.g. `certbot` in strict confinement.

Prefer **apt** when:

- You need a specific version held indefinitely (snap's `refresh.hold`
  is time-bound).
- You are on a locked-down network with no Snap Store Proxy.
- You depend on hooks, config layouts, or log paths the snap version
  does not use (snaps put logs in `journalctl`, configs under
  `/var/snap/<name>/current/`, not `/etc/`).
- You are on a minimal base image (Ubuntu Server Minimal, Docker) with
  no snapd installed.

### Common server snaps

| Snap | Purpose | Confinement | Pin |
|---|---|---|---|
| `certbot` | Let's Encrypt ACME client | classic | `latest/stable` |
| `lxd` | System container manager | strict | `5.21/stable` |
| `microk8s` | Single-node Kubernetes | strict | `1.29/stable` |
| `core22` / `core24` | Base snap | strict | auto |

`certbot` is the canonical server snap: the apt version is often years
behind, while the snap tracks EFF's own releases.

## Restricting auto-refresh on servers

You cannot disable snap auto-refresh permanently and stay secure —
auto-refresh *is* snap's update mechanism. Constrain *when* it runs:

```bash
sudo snap set system refresh.timer=03:00-04:00   # only 03-04 daily
sudo snap set system refresh.retain=5            # keep 5 old revs
sudo snap set system refresh.metered=hold        # skip on metered
sudo snap refresh --hold=24h                     # pause while debugging
```

For enterprise staged rollouts, run a local Snap Store Proxy and gate
approved revisions through its UI.

## Worked examples

### Install certbot and issue a cert

```bash
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/bin/certbot
sudo snap set certbot trust-plugin-with-root=ok
sudo certbot --nginx -d example.com
```

### Pin microk8s and set a refresh window

```bash
sudo snap install microk8s --channel=1.29/stable
sudo snap set system refresh.timer=sun,03:00-04:00
sudo snap set system refresh.retain=4
snap refresh --time
```

### Roll back a bad refresh

```bash
snap list --all certbot
sudo snap revert certbot              # -> previous revision
snap changes | tail
```

### Snapshot before a risky refresh

```bash
sudo snap save microk8s
snap saved
sudo snap refresh microk8s --channel=1.30/stable
# if bad:
sudo snap restore 12
sudo snap revert microk8s
```

### Weekly audit

```bash
snap list --all
snap services
snap connections | grep -E 'classic|system-files|docker-support'
sudo snap warnings
snap changes | tail -20
```

## Sources

- Canonical, *Ubuntu Server Guide Documentation (Focal 20.04 LTS)*,
  2020 — scattered references to `snapd`, snap confinement under
  AppArmor, and the Snap Store.
- Ghada Atef, *Mastering Ubuntu: A Comprehensive Guide to Linux's
  Favorite*, 2023 — Chapter III.III *Installing and managing software
  packages*.
- `snap(8)` manual page; `snapd(8)`; `snap-confine(5)`.
- Snapcraft documentation referenced from the Ubuntu Server Guide
  (snapcraft.io).
