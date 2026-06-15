---
name: linux-container-engine
description: Install and manage the container engine — Docker (daemon, dockerd) AND Podman (daemonless, rootless) across Debian/Ubuntu and the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Engine install from upstream repos on both families, rootless Podman vs the Docker daemon, storage drivers (overlay2), default network bridges, /etc/docker/daemon.json and /etc/containers/registries.conf, and daemon hardening (userns-remap, no-new-privileges, docker.sock permissions). Use this skill to stand up, configure, or harden the engine itself — not to run individual containers.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Container Engine — Docker & Podman

## Distro support

Two-family skill. The two engines are **Docker** (a root daemon, `dockerd`,
managed by `docker.service`) and **Podman** (daemonless, rootless by default,
shipped and preferred by the RHEL family). Both speak the OCI image format and
share most CLI verbs, but they configure differently: Docker reads
`/etc/docker/daemon.json`; Podman reads `/etc/containers/*.conf`
(`registries.conf`, `storage.conf`, `containers.conf`). The body below uses
Docker on Debian/Ubuntu; substitute per this matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Default / preferred engine | Docker CE (daemon) | **Podman** (daemonless, rootless) |
| Docker install | Docker CE apt repo (`docker-ce`) | Docker CE dnf repo (`docker-ce`) |
| Podman install | `apt install podman` | `dnf install podman` (in base/AppStream) |
| Daemon config | `/etc/docker/daemon.json` | `/etc/docker/daemon.json` (Docker); Podman has no daemon |
| Registries config | `/etc/docker/daemon.json` mirrors + Podman `/etc/containers/registries.conf` | `/etc/containers/registries.conf` (Podman default) |
| Storage driver | `overlay2` (Docker) | `overlay` via `fuse-overlayfs` (rootless Podman) / `overlay2` (Docker) |
| Default bridge | `docker0` (Docker) / `cni-podman0` or netavark | `cni-podman0` / **netavark** (RHEL 9+) |
| Rootless support | Podman rootless; Docker rootless is opt-in | Podman rootless is the default model |
| Volume SELinux labels | n/a | **SELinux**: bind-mount with `:z`/`:Z` or the container is denied |
| Socket | `/var/run/docker.sock` (root-equivalent) | none for rootless Podman; user socket via `podman.socket` |

**RHEL-family notes:** prefer **Podman** — rootless, no root daemon, and a
Docker-compatible CLI (`alias docker=podman` covers most flows). Registries
live in `/etc/containers/registries.conf` (system) and
`~/.config/containers/registries.conf` (per-user, overrides system). SELinux
relabels bind-mounted volumes: append `:z` (shared) or `:Z` (private) to
`-v host:container` or the container gets permission denied. See
[`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md)
and [`../../docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Installing Docker or Podman on a fresh host (either family).
- Choosing between the Docker daemon and rootless Podman for a workload.
- Writing or auditing `/etc/docker/daemon.json` or `/etc/containers/registries.conf`.
- Hardening the engine: userns-remap, `no-new-privileges`, socket permissions.

## Do not use when

- Running, stopping, or scheduling individual containers / compose stacks; use `linux-container-deployment`.
- Reclaiming disk from images, volumes, and networks; use `linux-image-hygiene`.
- Managing KVM/libvirt virtual machines; use `linux-virtualization`.
- Host firewall rules for published ports; use `linux-firewall-ssl`.

## Required inputs

- Which engine the host should run (Docker daemon, rootless Podman, or both).
- The family (Debian/Ubuntu vs RHEL) so install and config paths are correct.
- Whether containers must run rootless and any registry / mirror requirements.

## Workflow

1. Detect the family and any already-installed engine before installing.
2. Install the chosen engine from the upstream repo; enable it.
3. Write `daemon.json` / `registries.conf` for storage, logging, registries, hardening.
4. Verify the engine reports the expected storage driver, registries, and security flags.

## Quality standards

- Pin the storage driver (`overlay2`) and cap logs in `daemon.json` from day one.
- Treat `docker` group membership and `docker.sock` as root-equivalent; restrict both.
- Prefer rootless Podman on multi-tenant hosts; justify any root daemon in writing.

## Anti-patterns

- Installing `docker.io` from the distro archive on production (lags upstream).
- Bind-mounting `/var/run/docker.sock` into a container without a hard reason.
- Running every container as root because `:Z` SELinux labelling "was easier" to skip.

## Outputs

- The engine installed and its verified version / storage driver.
- The `daemon.json` / `registries.conf` applied and why each key is set.
- Any hardening (userns-remap, `no-new-privileges`, socket perms) and residual risk.

## References

- [`references/container-engine-reference.md`](references/container-engine-reference.md) — full Docker + Podman install, daemon config, networks, volumes, security, rootless.

**This skill is self-contained.** Every command below is a standard engine tool
— `docker` / `dockerd` on Debian/Ubuntu, `podman` on the RHEL family (see the
**Distro support** matrix). The `sk-*` script is an optional convenience wrapper
— never required.

This skill owns the **engine layer**: installing it, configuring the daemon /
Podman config, the storage driver, the default bridge, registries, and engine
hardening. It does **not** own running containers (`linux-container-deployment`),
disk cleanup (`linux-image-hygiene`), or KVM/libvirt VMs (`linux-virtualization`).

---

## Install the engine

### Docker CE (both families, upstream repo)

```bash
# Debian/Ubuntu
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

# RHEL family
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker

docker version
```

`docker` group membership is **root-equivalent** on the host — only add trusted admins.

### Podman (preferred on RHEL; available on Debian/Ubuntu)

```bash
# Debian/Ubuntu
sudo apt install -y podman
# RHEL family (base / AppStream — no extra repo)
sudo dnf install -y podman

podman info
podman run --rm hello-world          # rootless, no daemon
```

Rootless Podman runs each container in **your** user namespace; a breakout
cannot reach host root. Rootless containers cannot bind privileged ports (<1024)
or get a routable IP without extra setup — those need root or `slirp4netns`/`pasta`.

---

## Daemon configuration (`/etc/docker/daemon.json`)

A production baseline pins storage, caps logs, and turns on hardening:

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "userns-remap": "default",
  "default-address-pools": [ { "base": "172.30.0.0/16", "size": 24 } ],
  "registry-mirrors": ["https://mirror.gcr.io"]
}
```

Apply and verify:

```bash
sudo systemctl restart docker
docker info | grep -E 'Storage Driver|Logging Driver|Live Restore|userns'
```

Full rationale for each key — and the Podman equivalents — is in
[`references/container-engine-reference.md`](references/container-engine-reference.md).

---

## Registries (`/etc/containers/registries.conf`)

Podman (and Buildah/skopeo) read registries from
`/etc/containers/registries.conf` system-wide, overridable per-user at
`~/.config/containers/registries.conf`. Always set `unqualified-search-registries`
so a bare `podman pull nginx` is unambiguous:

```toml
unqualified-search-registries = ["registry.access.redhat.com", "docker.io"]

[[registry]]
location = "docker.io"

[[registry]]
location = "registry.example.com"
insecure = false
# blocked = true            # disable a registry entirely
```

Docker's registry mirrors live in `daemon.json` (`registry-mirrors`) instead.

---

## Storage driver & network bridge

```bash
docker info --format '{{.Driver}}'        # expect: overlay2
podman info --format '{{.Store.GraphDriverName}}'

docker network ls                          # default: bridge (docker0)
docker network inspect bridge | grep Subnet
podman network ls                          # default: podman (netavark on RHEL 9+)
```

`overlay2` is the correct default on modern kernels; rootless Podman uses
`overlay` via `fuse-overlayfs`. Avoid `devicemapper` (deprecated) and `vfs`
(no copy-on-write, huge disk use).

---

## Daemon hardening

- **`userns-remap`** maps container UID 0 to an unprivileged host UID, so a
  container root is not host root.
- **`no-new-privileges`** blocks `setuid` escalation inside containers.
- **`docker.sock` is root-equivalent.** It is owned `root:docker`, mode `0660`;
  do not loosen it and do not bind-mount it into containers.
- **Rootless Podman** sidesteps most of this — no root daemon, no root socket.

```bash
ls -l /var/run/docker.sock                 # expect srw-rw---- root docker
getent group docker                        # audit who has daemon access
docker info --format '{{.SecurityOptions}}'
```

> `[GROUNDING-GAP: daemon hardening (userns-remap, no-new-privileges, seccomp/AppArmor profiles, rootless socket perms) — grounded on Podman/Docker upstream docs; deepen with Container Security (Liz Rice)]`

Full detail (Dockerfile hardening, seccomp, capabilities, image scanning) is in
[`references/container-engine-reference.md`](references/container-engine-reference.md).

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-container-engine` installs:

| Task | Fast-path script |
|---|---|
| Report engine type, version, storage driver, registries, hardening flags | `sudo sk-engine-status` |

This is an optional wrapper. The `docker info` / `podman info` commands above are
the source of truth.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-container-engine
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-engine-status | scripts/sk-engine-status.sh | yes | Read-only: detect Docker daemon and/or Podman, print version, storage driver, default bridge, configured registries, and hardening flags (userns, no-new-privileges, socket perms). Both families. |
