# Container Prune & Scheduling — Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

> `[GROUNDING-GAP: image/volume/network/cache prune semantics, filters, and scheduled cleanup — grounded on Podman/Docker upstream docs and systemd.timer(5); the RHCSA/RHEL corpus covers container basics but not disk-hygiene at depth; deepen with Container Security (Liz Rice)]`

This reference details how container disk usage accumulates, every prune scope
and its filters, where storage actually lives on each family/mode, and how to
schedule a safe automatic prune.

## Table of contents

- [Where the disk goes](#where-the-disk-goes)
- [Measuring usage](#measuring-usage)
- [Prune scopes and filters](#prune-scopes-and-filters)
- [Volumes are special](#volumes-are-special)
- [Rootless Podman storage](#rootless-podman-storage)
- [Scheduled prune — systemd timer](#scheduled-prune--systemd-timer)
- [Sources](#sources)

## Where the disk goes

A busy container host accumulates, in rough order of size:

1. **Images** — every `pull`/`build` adds layers. Old tags and intermediate
   build layers (`<none>` "dangling" images) pile up fast.
2. **Build cache** — BuildKit caches every layer of every build.
3. **Stopped containers** — each keeps a writable layer until removed.
4. **Volumes** — named volumes survive `docker rm`; orphaned ones linger.
5. **Logs** — capped if you set `log-opts` in `daemon.json` (see
   `linux-container-engine`); uncapped JSON logs are a classic "disk full" page.

Docker keeps all of it under `/var/lib/docker`; root Podman under
`/var/lib/containers`; rootless Podman under `~/.local/share/containers`.

## Measuring usage

```bash
docker system df            # summary: images / containers / volumes / cache
docker system df -v         # per-object breakdown
podman system df
podman system df -v
du -sh /var/lib/docker      # raw on-disk size (root Docker)
```

The `RECLAIMABLE` column is the amount a prune would free without touching
anything in active use.

## Prune scopes and filters

| Command | Removes |
|---|---|
| `docker image prune` | dangling (untagged `<none>`) images only |
| `docker image prune -a` | all images not used by a container |
| `docker container prune` | all stopped containers |
| `docker volume prune` | volumes not referenced by any container |
| `docker network prune` | user-defined networks with no containers |
| `docker builder prune` | BuildKit build cache |
| `docker system prune` | stopped containers + dangling images + unused networks + cache |
| `docker system prune -a` | + all unused images |
| `docker system prune -a --volumes` | + unused volumes (destructive) |

Useful filters (Docker and Podman both accept `--filter`):

```bash
docker image prune -a --filter 'until=720h'          # older than 30 days
docker image prune -a --filter 'label!=keep'          # keep labelled images
docker container prune --filter 'until=24h'
```

Podman mirrors all of the above with `podman` in place of `docker`. Add `-f` to
skip the interactive confirm (the `sk-container-prune` script gates this behind
its own confirm).

## Volumes are special

Volumes hold *data*. `docker volume prune` removes any volume not currently
attached to a container — which includes a database volume whose container you
stopped for maintenance. **Never** schedule `--volumes` unattended on a stateful
host. Audit first:

```bash
docker volume ls --filter dangling=true       # candidates for removal
docker volume inspect <vol>                    # confirm it is truly orphaned
```

## Rootless Podman storage

Rootless Podman storage is per-user. Running `docker system prune` (or `sudo
podman ...`) does **not** clean a normal user's rootless storage:

```bash
# As the owning user, not root:
podman system df
podman system prune -a
du -sh ~/.local/share/containers/storage
```

A scheduled prune for a rootless user must be a `--user` systemd unit, and the
user must have linger enabled so the timer fires without an active login:

```bash
loginctl enable-linger alice
sudo -u alice XDG_RUNTIME_DIR=/run/user/$(id -u alice) \
    systemctl --user enable --now container-prune.timer
```

## Scheduled prune — systemd timer

A oneshot service plus a timer keeps the host tidy. System scope:

```ini
# /etc/systemd/system/container-prune.service
[Unit]
Description=Scheduled container image/cache prune
Documentation=man:docker-system-prune(1)

[Service]
Type=oneshot
# Conservative: dangling images, stopped containers, cache — NOT volumes.
ExecStart=/usr/bin/docker system prune -f --filter 'until=168h'
# Podman host instead:
# ExecStart=/usr/bin/podman system prune -f --filter 'until=168h'
```

```ini
# /etc/systemd/system/container-prune.timer
[Unit]
Description=Run container prune daily

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true            # catch up if the host was off at 03:30

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now container-prune.timer
systemctl list-timers container-prune.timer    # confirm next run
journalctl -u container-prune.service          # confirm it ran cleanly
```

The `sk-container-prune` script generates and installs this exact pair (using
itself as the `ExecStart`) when run with the timer option.

A cron equivalent (`/etc/cron.daily/container-prune`) works too, but the systemd
timer gives you `Persistent=true` catch-up and `journalctl` history for free.

## Sources

- Docker Inc. *Prune unused objects*. <https://docs.docker.com/config/pruning/>
- Red Hat. *Podman documentation* — `podman system prune`, `podman image prune`. <https://docs.podman.io/>
- `docker-system-prune(1)`, `docker-image-prune(1)`, `podman-system-prune(1)`, `podman-image-prune(1)`, `systemd.timer(5)` manual pages.
- *Container Security* — Liz Rice (image/layer lifecycle; deepen daemon-hardening and hygiene here).
