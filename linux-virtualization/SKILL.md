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

## Use when

- Managing LXD, Docker/Podman, or KVM/libvirt workloads on a host.
- Investigating container or VM lifecycle failures.
- Taking snapshots or backups before risky changes.

## Do not use when

- The task is configuration management for the host itself; use `linux-config-management`.
- The task is ordinary application service management outside the container or VM layer.

## Required inputs

- The virtualization layer involved: LXD, Docker/Podman, or KVM/libvirt.
- The guest, container, or image name.
- Whether the task is inspection, lifecycle management, snapshotting, or troubleshooting.

## Workflow

1. Identify the owning virtualization layer and target workload.
2. Inspect current state before changing it.
3. Apply the matching workflow below for lifecycle, snapshot, backup, or startup diagnosis.
4. Verify the guest or container state and host-level impact after the action.

## Quality standards

- Keep host and guest responsibilities distinct.
- Snapshot or back up before risky mutations when possible.
- Validate both orchestration state and actual workload health.

## Anti-patterns

- Treating all container technologies as interchangeable.
- Deleting or pruning workloads before identifying what they belong to.
- Debugging a guest failure without checking host-level status and logs.

## Outputs

- The container or VM diagnosis or action taken.
- The host- and guest-level checks used to validate it.
- Any backup, snapshot, or cleanup follow-up required.

## References

- [`references/lxd-reference.md`](references/lxd-reference.md)
- [`references/docker-reference.md`](references/docker-reference.md)

**This skill is self-contained.** Every command below uses standard
Ubuntu/Debian tools (`lxc`, `docker`, `virsh`). The `sk-*` scripts in the
**Optional fast path** section are convenience wrappers — never required.

This skill owns the container and VM layer on a host: **LXD** system
containers (Canonical's native), **Docker/Podman** for application
containers, and **KVM/libvirt** for full virtual machines.

It does **not** own:

- **Kubernetes** — out of scope for v1.
- **Cloud provider VMs** (EC2, DigitalOcean droplets) — managed at the
  provider side.
- **Applications inside containers** — managed by application-specific
  skills.

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
- Host firewall rules — use `linux-firewall-ssl`.
- Kubernetes/Nomad orchestration — out of scope.

---

## Standing rules

1. **LXD over legacy LXC.** `lxc` (the LXD CLI) is the modern, declarative
   wrapper. Direct `lxc-*` (legacy) commands are discouraged.
2. **Always snapshot before mutating.** Snapshot → mutate → verify. Roll
   back on failure.
3. **Snapshots are not backups.** They live on the same pool. Export
   containers/VMs to tar on separate storage for real backup.
4. **Resource limits are mandatory in production.** Unbounded containers
   eat the host. Set `limits.memory`, `limits.cpu`, and `limits.disk` in
   every profile.
5. **Privileged containers are banned unless justified in writing.**
   Unprivileged is the default.
6. **Docker images are pinned by digest, not tag** in production.
   `nginx:latest` is a moving target; `nginx@sha256:abc…` is reproducible.
7. **Validate docker-compose files before applying** with
   `docker compose config`.

---

## Quick reference — manual commands

### LXD

```bash
# List all containers
lxc list
lxc list -f compact                            # compact format
lxc info <name>                                # detailed state, IP, resource use

# Launch and basic lifecycle
lxc launch ubuntu:24.04 web01
lxc exec web01 -- bash
lxc stop web01
lxc start web01
lxc delete web01 --force

# Snapshots
lxc snapshot web01 before-upgrade-2026-04-10
lxc info web01 | grep -A10 Snapshots
lxc restore web01 before-upgrade-2026-04-10
lxc delete web01/before-upgrade-2026-04-10    # delete a snapshot

# Full export / backup
lxc export web01 /backups/lxd/web01-$(date +%Y%m%d).tar.gz
lxc import /backups/lxd/web01-20260410.tar.gz

# Resource limits (applied to running container)
lxc config set web01 limits.memory 1GB
lxc config set web01 limits.cpu 2
lxc config device override web01 root size=10GB

# Copy between hosts
lxc remote add remotehost <ip>
lxc copy web01 remotehost:web01-copy
```

Full LXD reference (`lxd init`, profiles, storage backends, networks,
cloud-init integration, 6 worked examples) — see
[`references/lxd-reference.md`](references/lxd-reference.md).

### Docker

```bash
# Inspect
docker ps -a                                   # all containers
docker images                                  # all images
docker volume ls                               # volumes
docker network ls                              # networks
docker system df                               # disk usage
docker stats --no-stream                       # live resource use

# Inspect one container
docker inspect web01 | less
docker logs --tail 50 web01
docker logs -f web01                           # follow
docker top web01                               # processes inside
docker exec -it web01 bash                     # shell in

# Lifecycle
docker run -d --name web01 --restart unless-stopped nginx@sha256:<digest>
docker stop web01
docker start web01
docker rm web01

# Images — pin by digest
docker pull nginx:1.27
docker inspect nginx:1.27 | grep RepoDigests   # get the digest
docker pull nginx@sha256:<digest>              # pin

# Prune
docker system prune                            # safe: stopped containers, dangling images
docker system prune -a --volumes               # aggressive: everything not running
```

Compose:

```bash
docker compose config                          # validate before applying
docker compose up -d
docker compose ps
docker compose logs -f web
docker compose down
docker compose pull                            # refresh images
```

Full Docker reference (daemon config, Dockerfile best practices, networks,
volumes, compose v2, security, systemd-managed containers) — see
[`references/docker-reference.md`](references/docker-reference.md).

### KVM / libvirt

```bash
sudo virsh list --all                          # all VMs
sudo virsh dominfo <vm>
sudo virsh start <vm>
sudo virsh shutdown <vm>                       # graceful (via ACPI)
sudo virsh destroy <vm>                        # hard power-off
sudo virsh snapshot-create-as <vm> snap-before-upgrade
sudo virsh snapshot-list <vm>
sudo virsh snapshot-revert <vm> snap-before-upgrade
```

---

## Typical workflows

### Workflow: "What's running on this host?"

```bash
echo "=== LXD ==="
lxc list 2>/dev/null || echo "(lxd not installed)"
echo
echo "=== Docker ==="
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "(docker not installed)"
echo
echo "=== KVM ==="
sudo virsh list --all 2>/dev/null || echo "(libvirt not installed)"
```

### Workflow: "Snapshot before I mess with it"

```bash
lxc snapshot web-prod before-upgrade-$(date +%Y%m%d-%H%M)
# ... do the risky thing ...
# If it breaks:
lxc restore web-prod before-upgrade-20260410-1530
# When confirmed stable, delete the snapshot:
lxc delete web-prod/before-upgrade-20260410-1530
```

### Workflow: "Back up a container to cold storage"

```bash
DEST=/backups/lxd
mkdir -p "$DEST"
lxc export web-prod "$DEST/web-prod-$(date +%Y%m%d).tar.gz"
# Then ship off-host:
rclone copy "$DEST/web-prod-$(date +%Y%m%d).tar.gz" gdrive:lxd-backups/
```

### Workflow: "Why won't this Docker container start?"

```bash
docker inspect web01 --format '{{.State.Status}}: {{.State.Error}}'
docker logs --tail 50 web01
docker inspect web01 --format '{{json .State.Health}}' | jq .
# Mount issues?
docker inspect web01 --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
# Port conflicts?
ss -tulnp | grep -E ':(80|443)'
# Restart loops? (check restart count)
docker inspect web01 --format '{{.RestartCount}}'
```

---

## Troubleshooting / gotchas

- **LXD containers "lose" their IP on boot.** They use DHCP from `lxdbr0`
  by default; if the bridge has no DHCP server, set a static IP in the
  profile or container config.
- **Docker DNS fails inside containers.** Usually `systemd-resolved` on
  the host is binding 53/udp. Fix: tell Docker to use a different
  nameserver (`/etc/docker/daemon.json` → `"dns": ["1.1.1.1"]`) or point
  containers at the host's resolver.
- **`docker system prune -a` is destructive.** It deletes images not used
  by a running container — including ones you paused to investigate.
  Always use `docker system prune` (without `-a`) first.
- **KVM VMs with bridged networking don't get IPs.** Check that the host
  bridge has a DHCP server on the VLAN, or configure the VM with cloud-init
  static networking.
- **LXD container file ownership looks weird from the host.** Unprivileged
  containers remap UIDs (`uid 1000` inside = `uid 1001000` outside). Use
  `lxc file push/pull` to move files without fighting ownership.

---

## References

- [`references/lxd-reference.md`](references/lxd-reference.md) — full LXD
  reference: init, profiles, storage, networks, 6 worked examples.
- [`references/docker-reference.md`](references/docker-reference.md) —
  Docker daemon config, Dockerfile best practices, compose, security.
- Book: *Ubuntu Server Guide* (Canonical, Focal) — LXD and KVM chapters.
- Book: *Mastering Ubuntu* (Atef, 2023) — Docker coverage.
- Man pages: `lxc(1)`, `docker(1)`, `virsh(1)`.

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-virtualization` installs:

| Task | Fast-path script |
|---|---|
| LXD containers with state, IP, memory, disk, uptime | `sudo sk-lxd-list` |
| Create / list / restore LXD snapshots | `sudo sk-lxd-snapshot` |
| Full LXD container export to tar | `sudo sk-lxd-backup --container <n>` |
| Docker containers + images + volumes summary | `sudo sk-docker-inspect` |

These are optional wrappers. The `lxc` and `docker` commands above are the
source of truth.

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
