---
name: linux-image-hygiene
description: Reclaim disk from the container engine across Debian/Ubuntu and the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Prune dangling and unused images, stopped containers, unused volumes and networks, and build cache to stop /var/lib/docker and Podman storage from filling the disk. Covers docker system prune, docker image prune, podman image prune -a, podman system prune, and a scheduled prune via a systemd timer. Use this skill when a container host is running out of disk or to set up automatic cleanup.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Container Image & Volume Hygiene

## Distro support

Two-family skill. The prune commands are nearly identical between Docker and
Podman; the differences are storage location (Docker keeps everything under
`/var/lib/docker`; rootless Podman under `~/.local/share/containers`) and that
on RHEL you usually drive Podman. The body below shows Docker on Debian/Ubuntu;
substitute per this matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Disk usage report | `docker system df` | `podman system df` |
| Prune (safe: dangling + stopped) | `docker system prune` | `podman system prune` |
| Prune everything unused | `docker system prune -a --volumes` | `podman system prune -a --volumes` |
| Unused images only | `docker image prune -a` | `podman image prune -a` |
| Dangling images only | `docker image prune` | `podman image prune` |
| Unused volumes | `docker volume prune` | `podman volume prune` |
| Unused networks | `docker network prune` | `podman network prune` |
| Storage root | `/var/lib/docker` | `/var/lib/containers` (root) / `~/.local/share/containers` (rootless) |
| Schedule | `systemd` timer (system) | `systemd` timer; rootless uses `--user` + linger |

**RHEL-family notes:** rootless Podman storage is per-user under
`~/.local/share/containers/storage` — a `docker system prune` as root will not
touch it; run `podman system prune` as the owning user. A scheduled prune for a
rootless user needs a `--user` timer plus `loginctl enable-linger`. See
[`../../docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- A container host is filling its disk (`/var/lib/docker`, container storage).
- Removing dangling images, stopped containers, unused volumes/networks, build cache.
- Setting up automatic, scheduled cleanup with a systemd timer.

## Do not use when

- Installing or configuring the engine; use `linux-container-engine`.
- Running or supervising containers; use `linux-container-deployment`.
- General host disk triage outside containers; use `linux-disk-storage`.

## Required inputs

- The engine in use (Docker daemon vs rootless Podman) and whose storage to clean.
- How aggressive the prune may be (dangling-only vs `-a --volumes`).
- For scheduling: the cadence and whether it is a system or rootless-user timer.

## Workflow

1. Measure first with `docker system df` / `podman system df`.
2. Identify what is genuinely unused (dangling images, stopped containers, orphan volumes).
3. Prune from least to most aggressive; confirm before `-a --volumes`.
4. Optionally install a scheduled prune (systemd timer) and verify it ran.

## Quality standards

- Always run `system df` before pruning so the reclaim is measured, not guessed.
- Start with safe prunes; reserve `-a --volumes` for hosts you fully understand.
- Volumes hold data — never auto-prune volumes on a stateful host without review.

## Anti-patterns

- Running `docker system prune -a --volumes` on a host with paused-to-investigate images, or with data-bearing volumes.
- Scheduling an aggressive `-a --volumes` prune unattended on a DB/stateful host.
- Cleaning root Docker storage and assuming rootless Podman storage was also freed.

## Outputs

- The disk reclaimed (before/after `system df`).
- Exactly which objects were pruned (images/containers/volumes/networks/cache).
- Any scheduled timer installed and its next-run time.

## References

- [`references/prune-and-scheduling.md`](references/prune-and-scheduling.md) — prune scopes, filters, storage layout, and the systemd prune timer.

**This skill is self-contained.** Every command below is a standard engine tool
— `docker` on Debian/Ubuntu, `podman` on the RHEL family (see the **Distro
support** matrix). The `sk-*` script is an optional convenience wrapper — never
required.

This skill owns **disk reclamation**. It does not own installing the engine
(`linux-container-engine`) or running containers (`linux-container-deployment`).

---

## Measure before you prune

```bash
docker system df                # TYPE / TOTAL / ACTIVE / RECLAIMABLE
docker system df -v             # per-image, per-volume detail
# Podman:
podman system df
```

`RECLAIMABLE` is the headline number — what a prune would free.

---

## Prune scopes (least to most aggressive)

```bash
# 1. Dangling images only (untagged <none> layers) — always safe
docker image prune

# 2. Stopped containers + dangling images + unused networks + build cache
docker system prune

# 3. All images not used by a running container (not just dangling)
docker image prune -a
docker image prune -a --filter 'until=720h'    # only images older than 30 days

# 4. Everything unused, INCLUDING named volumes — destructive
docker system prune -a --volumes

# Targeted:
docker container prune          # stopped containers
docker volume prune             # unused volumes (data loss risk!)
docker network prune            # unused user-defined networks
docker builder prune            # build cache
```

> **`docker system prune -a` deletes images not used by a *running* container —
> including ones you stopped to investigate. Always run `docker system prune`
> (no `-a`) first, and never auto-prune `--volumes` on a stateful host.**

Podman is the same surface:

```bash
podman image prune -a           # all unused images
podman system prune             # stopped containers + dangling + cache
podman system prune -a --volumes
podman volume prune
```

> `[GROUNDING-GAP: image/volume/cache prune semantics and filters (until=, label=, dangling=) — grounded on Podman/Docker upstream docs; deepen with Container Security (Liz Rice)]`

---

## Scheduled prune (systemd timer)

The cleanest way to keep a host tidy is a `*.timer` + `*.service` pair that runs
a safe prune nightly. System scope (Docker / root Podman):

```ini
# /etc/systemd/system/container-prune.service
[Unit]
Description=Scheduled container image/cache prune

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sk-container-prune --yes --schedule-safe
```

```ini
# /etc/systemd/system/container-prune.timer
[Unit]
Description=Run container prune daily

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now container-prune.timer
systemctl list-timers container-prune.timer
```

The `sk-container-prune` script below installs exactly this timer for you.
For rootless Podman use `systemctl --user` units plus
`loginctl enable-linger <user>`. Full detail (filters, storage layout, cron
alternative) is in
[`references/prune-and-scheduling.md`](references/prune-and-scheduling.md).

> `[GROUNDING-GAP: systemd prune timer scheduling — grounded on Podman/Docker + systemd.timer upstream docs; deepen with Container Security (Liz Rice)]`

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-image-hygiene` installs:

| Task | Fast-path script |
|---|---|
| Report reclaimable space, prune at chosen scope, optionally install the daily timer | `sudo sk-container-prune` |

This is an optional wrapper. The `docker`/`podman` prune commands above are the
source of truth.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-image-hygiene
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-container-prune | scripts/sk-container-prune.sh | yes | Report reclaimable space (`system df`), then prune Docker and/or Podman at a chosen scope (safe / images / aggressive); asks before each destructive step; can install a daily systemd prune timer. Both families. |
