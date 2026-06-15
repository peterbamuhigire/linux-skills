# Container Engine — Docker & Podman Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This reference covers the **engine layer**: installing Docker Engine CE and
Podman on both families, daemon configuration (`/etc/docker/daemon.json`),
registries (`/etc/containers/registries.conf`), the day-to-day inspection
workflow, Dockerfile best practice, networks and volumes, image-digest pinning,
container/daemon security hardening, and rootless Podman. **Running** containers
(compose, Quadlet, `podman generate systemd`, restart policies, lifecycle) is
covered by `linux-container-deployment`; disk reclamation (`prune`) by
`linux-image-hygiene`.

Docker packages one process at a time: a Docker/Podman container is a single
application plus its libraries, started by `run` and killed when the process
exits — unlike an LXD/KVM whole-userland guest.

## Table of contents

- [Install Docker Engine](#install-docker-engine)
- [Daemon configuration](#daemon-configuration)
- [Registries (Podman registries.conf)](#registries-podman-registriesconf)
- [Core workflow](#core-workflow)
- [Dockerfile best practice](#dockerfile-best-practice)
- [Networks](#networks)
- [Volumes](#volumes)
- [Pin images by digest](#pin-images-by-digest)
- [Security hardening](#security-hardening)
- [Podman as a rootless alternative](#podman-as-a-rootless-alternative)
- [Sources](#sources)

## Install Docker Engine

**Do not** install `docker.io` from the Ubuntu archive on a production host — it lags upstream by months. Install Docker CE from Docker Inc.'s own apt repository (a `dnf`-repo equivalent exists for the RHEL family; see the skill's matrix):

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
docker version
```

Add your admin user to the `docker` group so you do not need `sudo` for every command. **Note:** membership of `docker` is equivalent to root on the host — only add trusted admins:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
docker run --rm hello-world
```

## Daemon configuration

The Docker daemon reads `/etc/docker/daemon.json` on startup. Use it to pin the storage driver, log driver, default runtime, registry mirrors, default resource limits, and live restore. A production-grade baseline:

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "storage-driver": "overlay2",
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 65536, "Soft": 65536 }
  },
  "registry-mirrors": ["https://mirror.gcr.io"],
  "default-address-pools": [
    { "base": "172.30.0.0/16", "size": 24 }
  ]
}
```

Why each key matters: **`log-driver` + `log-opts`** caps JSON logs — unbounded logs are the most common cause of "disk full" pages on Docker hosts. **`storage-driver: overlay2`** is the correct default on modern Ubuntu. **`live-restore: true`** keeps containers running across daemon restarts; without it, every Docker upgrade is a downtime. **`userland-proxy: false`** pushes port forwarding into iptables, which is faster and integrates better with host firewalls. **`no-new-privileges: true`** default-denies `setuid` elevation inside containers. **`default-ulimits`** raises `nofile` so services inside containers do not die with "too many open files" under load. **`default-address-pools`** avoids Docker auto-picking subnets that clash with your corporate LAN (the classic 172.17/16 collision).

Apply changes:

```bash
sudo systemctl restart docker
docker info | grep -E 'Storage Driver|Logging Driver|Live Restore'
```

Podman has **no daemon** — there is nothing equivalent to `daemon.json`.
Engine-wide defaults for Podman live in `/etc/containers/containers.conf`
(and `~/.config/containers/containers.conf` per user), and storage in
`/etc/containers/storage.conf`. Hardening like `no-new-privileges` is applied
per-`run` (or in a Quadlet unit) rather than daemon-wide.

## Registries (Podman registries.conf)

Podman, Buildah, and skopeo resolve images through
`/etc/containers/registries.conf` (system) — overridable per user at
`~/.config/containers/registries.conf` (the user file wins on conflict). On
RHEL the file ships with three registries by default: two Red Hat registries
(licensed content, require Red Hat credentials) and Docker Hub as the last
fallback. Always set `unqualified-search-registries` so a bare `podman pull
nginx` is unambiguous, and use `[[registry]]` blocks to add, pin, or block
registries:

```toml
# /etc/containers/registries.conf
unqualified-search-registries = ["registry.access.redhat.com", "registry.redhat.io", "docker.io"]

[[registry]]
location = "docker.io"

[[registry]]
location = "registry.example.com"
insecure = false        # true only for an internal registry without TLS

[[registry]]
location = "quay.io/oldnamespace"
blocked  = true         # refuse pulls from this registry entirely
```

Docker's equivalent is `registry-mirrors` (and `insecure-registries`) in
`/etc/docker/daemon.json`. Verify resolution with `podman info` /
`docker info`:

```bash
podman info --format '{{.Registries}}'
podman pull --log-level=debug alpine 2>&1 | grep -i 'trying'   # see search order
```

## Core workflow

Pull, run, list, inspect, log, exec, stop, remove:

```bash
docker pull nginx:1.27-alpine
docker run -d --name web -p 8080:80 nginx:1.27-alpine
docker ps
docker ps -a                                  # include stopped
docker logs -f --tail 100 web
docker exec -it web sh
docker inspect web
docker stats --no-stream web
docker stop web
docker start web
docker restart web
docker rm -f web
```

List, prune, remove images and check disk use:

```bash
docker images
docker image ls --digests
docker rmi nginx:1.27-alpine
docker image prune -a --filter 'until=720h'   # anything unused > 30 days
docker system df                               # disk use by type
docker system prune -af --volumes              # aggressive cleanup
```

Run a throwaway command in a fresh container, and copy files in and out:

```bash
docker run --rm -it ubuntu:22.04 bash
docker run --rm alpine:3.20 sh -c 'apk add curl && curl -I https://example.com'
docker cp ./nginx.conf web:/etc/nginx/nginx.conf
docker cp web:/var/log/nginx/access.log ./access.log
```

## Dockerfile best practice

A good Dockerfile is small, cache-friendly, reproducible, and runs as a non-root user. Multi-stage builds keep build-time tooling out of the final image.

```dockerfile
# syntax=docker/dockerfile:1.7

# -------- build stage --------
FROM node:20.11-bookworm-slim AS build
WORKDIR /app
# Copy manifests first so `npm ci` is cached when only src changes.
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# -------- runtime stage --------
FROM node:20.11-bookworm-slim AS runtime
# Non-root user with a fixed UID so bind-mounts behave.
RUN groupadd --system --gid 10001 app \
 && useradd  --system --uid 10001 --gid app --home /app --shell /sbin/nologin app
WORKDIR /app
ENV NODE_ENV=production PORT=3000
COPY --from=build --chown=app:app /app/node_modules ./node_modules
COPY --from=build --chown=app:app /app/dist         ./dist
COPY --from=build --chown=app:app /app/package.json ./
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=20s \
    CMD wget -qO- http://127.0.0.1:3000/healthz || exit 1
CMD ["node", "dist/server.js"]
```

Rules this file enforces: **Layer order for cache** — `package.json` copied and installed before `COPY . .`, so a source-only change does not bust the `npm ci` layer. **`COPY` over `ADD`** — `ADD` silently unpacks tars and fetches URLs; `COPY` is boring and predictable, use it unless you genuinely need `ADD`'s magic. **`WORKDIR` over `cd`** — every `WORKDIR` creates a known directory and survives layer caching. **Non-root `USER`** — container processes should never run as UID 0 unless they absolutely must bind a privileged port (and even then, use `CAP_NET_BIND_SERVICE` instead). **`HEALTHCHECK`** — exposes liveness to `docker ps`, Compose, Swarm, and anything else that reads container state. **Multi-stage** — build tools (devDependencies, compilers, headers) stay in the `build` stage and never ship. **Pinned base image tag** (`node:20.11-bookworm-slim`, not `node:latest`) — reproducible today, pinnable by digest tomorrow.

Build and tag:

```bash
docker build -t registry.example.com/myapp:2026.04.10 .
docker image ls registry.example.com/myapp
```

## Networks

Docker ships four built-in drivers:

| Driver | Use when |
|---|---|
| `bridge` | default; container-to-container on one host with NAT out to the internet |
| `host` | container shares the host's network namespace; no isolation, full speed, clash-prone ports |
| `none` | container has no network at all; for sandboxing batch jobs |
| `overlay` | multi-host networking for Swarm clusters |

Create a user-defined bridge (better than the default `bridge` because it gives you DNS between containers by name), then inspect and prune:

```bash
docker network create --driver bridge app-net
docker run -d --name db  --network app-net postgres:16
docker run -d --name web --network app-net -p 80:80 nginx:1.27-alpine
docker exec web ping -c1 db        # resolves by container name

docker network ls
docker network inspect app-net
docker network prune
```

## Volumes

Three flavours: **Named volume** — Docker-managed, lives under `/var/lib/docker/volumes/`, best for stateful data, portable across containers. **Bind mount** — a host path appears inside the container, best for config files and source during development. **tmpfs mount** — memory-only, good for secrets you do not want written to disk.

```bash
# named volume
docker volume create pgdata
docker run -d --name db -v pgdata:/var/lib/postgresql/data postgres:16

# bind mount
docker run -d --name web \
    -v /srv/www/html:/usr/share/nginx/html:ro \
    -p 80:80 nginx:1.27-alpine

# tmpfs
docker run -d --name batch --tmpfs /tmp:rw,size=64m,mode=1777 alpine:3.20 sleep 3600
```

Inspect, prune, and back up a named volume to a tar:

```bash
docker volume ls
docker volume inspect pgdata
docker volume rm pgdata
docker volume prune

docker run --rm \
    -v pgdata:/data:ro \
    -v "$PWD:/backup" \
    alpine:3.20 \
    tar -czf /backup/pgdata-$(date +%F).tar.gz -C /data .
```

## Pin images by digest

Tags are mutable. `nginx:1.27` today may be a different image next week. For any production workload, pin the **digest** and record it in Git:

```bash
docker pull nginx:1.27-alpine
docker image inspect nginx:1.27-alpine \
    --format '{{index .RepoDigests 0}}'
# → nginx@sha256:a2ba...longhash...

docker run -d nginx@sha256:a2ba...longhash...
```

Digests guarantee reproducibility. When you intentionally upgrade, you change the digest in a commit, and the diff shows exactly what moved.

## Security hardening

**Run as non-root.** Every production image should ship a `USER` instruction. If the image you are running does not, override on the command line. **Read-only root filesystem** forces the app to put mutable data on an explicit volume or tmpfs, which both documents state and defeats in-place tampering. **Drop all capabilities, add back only what you need** — the default container has a dozen Linux capabilities you almost certainly do not need. **`--security-opt no-new-privileges`** forbids `setuid` binaries inside the container from elevating; it should be on for everything.

```bash
docker run -d --user 10001:10001 myapp:2026.04.10

docker run -d --read-only \
    --tmpfs /tmp:rw,size=64m \
    --tmpfs /var/run:rw,size=16m \
    myapp:2026.04.10

docker run -d \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    -p 80:80 \
    nginx:1.27-alpine

docker run -d --security-opt no-new-privileges myapp:2026.04.10
```

**Seccomp.** Docker ships a default seccomp profile that blocks ~44 dangerous syscalls. Leave it on (it is on by default). Custom profiles are sometimes needed for unusual workloads: `docker run -d --security-opt seccomp=/etc/docker/seccomp-myapp.json myapp:2026.04.10`.

**Never bind-mount `/var/run/docker.sock`** into a container unless you are writing a CI agent and have thought carefully — that socket is root-equivalent on the host.

Scan images before deploy:

```bash
docker scout cves myapp:2026.04.10
# or
trivy image myapp:2026.04.10
```

## Podman as a rootless alternative

Podman is a drop-in, daemonless, rootless alternative to Docker. The CLI is intentionally Docker-compatible — most `docker` commands work unchanged with `podman`. Key differences: **no daemon** (each `podman` invocation is a short-lived process; nothing equivalent to `dockerd` runs in the background); **rootless by default** (containers run in your user namespace, so a compromise cannot gain host root even on namespace break-out); **systemd-native** (`podman generate systemd` emits unit files that run in the user slice); **pods** (group related containers into a shared network namespace, similar to a Kubernetes pod).

Install and smoke-test, then use it day-to-day exactly like Docker:

```bash
sudo apt install -y podman
podman run --rm hello-world
podman info
podman pull nginx:1.27-alpine
podman run -d --name web -p 8080:80 nginx:1.27-alpine
podman ps && podman logs -f web
podman exec -it web sh
podman stop web && podman rm web
```

For rootless operation, packages and subuid/subgid ranges must be in place:

```bash
podman unshare cat /proc/self/uid_map     # confirm the user namespace mapping
grep "$USER" /etc/subuid /etc/subgid       # rootless needs a sub-uid/gid range
loginctl enable-linger "$USER"             # let user services start at boot
```

Use Podman when you want rootless containers on a multi-tenant host, when you
cannot justify running a root-level daemon, or when you want systemd-native
integration without hand-writing unit files.

Running containers as systemd services (`podman generate systemd`, Quadlet
`.container` units, pods, restart policies) and compose stacks are covered in
**`linux-container-deployment`**; disk reclamation in **`linux-image-hygiene`**.

## Sources

- *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite* — Ghada Atef, 2023 (Docker, Podman, and container workflow chapters).
- Canonical. *Ubuntu Server Guide — Virtualization and Containers*. Canonical Ltd, 2020 (Focal 20.04 LTS edition). <https://ubuntu.com/server/docs>
- Docker Inc. *Docker Engine documentation*. <https://docs.docker.com/engine/>
- Docker Inc. *Compose specification*. <https://docs.docker.com/compose/compose-file/>
- Red Hat. *Podman documentation*. <https://docs.podman.io/>
- `dockerd(8)`, `docker(1)`, `docker-compose(1)`, `podman(1)` manual pages.
