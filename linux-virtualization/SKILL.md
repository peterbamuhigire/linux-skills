---
name: linux-virtualization
description: Manage containers and VMs on Ubuntu/Debian — LXD system containers, Docker/Podman application containers, KVM virtual machines. Use for container lifecycle, snapshots, backups, and host-level inspection.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Virtualization

This skill owns the container and VM layer on a host: LXD system
containers (Canonical's native), Docker or Podman for application
containers, and KVM/libvirt for full virtual machines.

It does **not** own:

- **Kubernetes** — out of scope for v1.
- **Cloud provider VMs** (EC2, DigitalOcean droplets, etc.) — those are
  managed at the provider side.
- **The applications inside containers** — those are managed by
  application-specific skills.

Informed by the Canonical *Ubuntu Server Guide* (LXD, KVM chapters) and
*Mastering Ubuntu* (Docker, Podman coverage).

---

## When to use

- Listing containers and VMs on a host.
- Creating or restoring LXD container snapshots.
- Exporting/backing up a container or VM to a tar file.
- Inspecting Docker/Podman state: containers, images, volumes, networks,
  health.
- Debugging why a container won't start or is unhealthy.

## When NOT to use

- Deploying a web application *inside* a container — use
  `linux-site-deployment`.
- Hardening the host's firewall to protect the container — use
  `linux-firewall-ssl`.
- Orchestrating at the cluster level (Kubernetes, Nomad) — out of scope.

---

## Standing rules

1. **LXD over LXC.** LXD is the declarative, modern wrapper. Direct `lxc-*`
   commands are legacy.
2. **Always snapshot before mutating.** `sk-lxd-snapshot` creates a named
   snapshot before any reconfiguration; roll back on failure.
3. **Backups are full exports, not snapshots.** Snapshots live on the same
   ZFS pool — they don't protect against disk failure. Use `sk-lxd-backup`
   to export to a tar that can live off-host.
4. **Container resource limits are mandatory in production.** Unbounded
   containers eat the host. Set `limits.memory`, `limits.cpu`, and
   `limits.disk` in every profile.
5. **Privileged containers are banned unless justified in writing.**
   Unprivileged containers are the default and cover 95% of use cases.
6. **Docker images are pinned by digest, not tag.** `nginx:latest` is a
   moving target; `nginx@sha256:abc...` is reproducible.

---

## Typical workflows

### "What's running on this host?"

```bash
sk-lxd-list         # LXD containers
sk-docker-inspect   # Docker containers + images + volumes
```

### "Snapshot before I mess with it"

```bash
sk-lxd-snapshot --container web-prod --name before-upgrade-2026-04-10
# do the risky thing
# if it breaks:
sk-lxd-snapshot --container web-prod --restore before-upgrade-2026-04-10
```

### "Back up a container to cold storage"

```bash
sk-lxd-backup --container web-prod --destination /backups/lxd/
# optionally pipe to rclone for off-host
```

### "Why won't this Docker container start?"

```bash
sk-docker-inspect --container web-prod
```

Shows state, last 20 log lines, exit code, restart count, health checks,
mount points, and port bindings in one report.

---

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-virtualization
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-lxd-list | scripts/sk-lxd-list.sh | no | All LXD containers with state, IPv4/IPv6, memory and disk usage, uptime. |
| sk-lxd-snapshot | scripts/sk-lxd-snapshot.sh | no | Create, list, or restore LXD container snapshots with a naming convention. |
| sk-lxd-backup | scripts/sk-lxd-backup.sh | no | Full LXD container export to tar, with restore metadata, for off-host backup. |
| sk-docker-inspect | scripts/sk-docker-inspect.sh | no | Summary of Docker containers, images, volumes, networks, health status, disk usage. |

---

## See also

- `linux-site-deployment` — for deploying apps inside the containers.
- `linux-disaster-recovery` — for tying container backups into the
  repo-wide backup strategy.
- `linux-cloud-init` — for provisioning LXD containers from cloud-init
  user-data.
