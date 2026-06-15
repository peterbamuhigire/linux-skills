# Docker (and Podman) on Ubuntu — Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Docker packages one process at a time. That is the key difference between Docker and LXD: an LXD container is a whole userland with systemd inside; a Docker container is a single application plus the libraries it needs, started by `docker run` and killed when the process exits. This reference covers installing Docker Engine CE from the official Ubuntu repo, daemon configuration, the day-to-day container workflow, Dockerfile best practice, Compose v2, networks and volumes, resource limits, pinning images by digest, container security, running containers under systemd, and using Podman as a rootless alternative.

## Table of contents

- [Install Docker Engine on Ubuntu](#install-docker-engine-on-ubuntu)
- [Daemon configuration](#daemon-configuration)
- [Core workflow](#core-workflow)
- [Dockerfile best practice](#dockerfile-best-practice)
- [Compose v2](#compose-v2)
- [Networks](#networks)
- [Volumes](#volumes)
- [Restart policies](#restart-policies)
- [Resource limits](#resource-limits)
- [Pin images by digest](#pin-images-by-digest)
- [Security hardening](#security-hardening)
- [Systemd-managed containers](#systemd-managed-containers)
- [Podman as a rootless alternative](#podman-as-a-rootless-alternative)
- [Sources](#sources)

## Install Docker Engine on Ubuntu

**Do not** install `docker.io` from the Ubuntu archive on a production host — it lags upstream by months. Install Docker CE from Docker Inc.'s own apt repository:

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

## Compose v2

Compose v2 ships as the `docker compose` subcommand (two words, no hyphen, no separate binary). It reads `compose.yaml` (or the legacy `docker-compose.yml`) from the current directory.

```yaml
# compose.yaml
name: webstack
services:
  web:
    image: nginx:1.27-alpine@sha256:aaaa...   # pinned by digest
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - webdata:/usr/share/nginx/html
    networks: [frontend, backend]
    depends_on:
      app: { condition: service_healthy }
    deploy:
      resources:
        limits: { cpus: "1.0", memory: 256M }
    read_only: true
    tmpfs: ["/var/cache/nginx", "/var/run"]
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    security_opt: ["no-new-privileges:true"]
  app:
    image: registry.example.com/myapp:2026.04.10@sha256:bbbb...
    restart: unless-stopped
    env_file: .env
    networks: [backend]
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:3000/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    deploy:
      resources:
        limits: { cpus: "2.0", memory: 1G }
  db:
    image: postgres:16-bookworm@sha256:cccc...
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
      POSTGRES_DB: myapp
    volumes: [dbdata:/var/lib/postgresql/data]
    networks: [backend]
    secrets: [db_password]
volumes:
  webdata:
  dbdata:
networks:
  frontend:
  backend:
    internal: true
secrets:
  db_password:
    file: ./secrets/db_password.txt
```

Operate the stack:

```bash
docker compose up -d
docker compose ps
docker compose logs -f --tail 100 app
docker compose exec app sh
docker compose restart web
docker compose pull && docker compose up -d   # rolling update
docker compose down                            # stop and remove
docker compose down -v                         # and remove named volumes
docker compose config                           # validate without starting
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

## Restart policies

Pick a restart policy explicitly. The default is `no`, which means a container that crashes stays dead until a human notices.

| Policy | When to use |
|---|---|
| `no` | one-off batch jobs (default — fine for `docker run --rm`) |
| `on-failure[:max]` | batch jobs that should retry a bounded number of times |
| `always` | background services that must always run |
| `unless-stopped` | background services, but respect operator `docker stop` across reboots — **usually the right pick** |

```bash
docker run -d --name web --restart unless-stopped -p 80:80 nginx:1.27-alpine
```

## Resource limits

Unbounded containers happily eat every GB of RAM on the host. Always set limits — in Compose via `deploy.resources.limits`, or on the CLI:

```bash
docker run -d --name app \
    --memory 1g \
    --memory-swap 1g \
    --memory-reservation 512m \
    --cpus 2 \
    --pids-limit 200 \
    --ulimit nofile=65536:65536 \
    myapp:2026.04.10
```

`--memory` is a hard cap with OOM-kill on overrun. `--memory-swap` set equal to `--memory` disables swap entirely. `--memory-reservation` is a soft cap used under host pressure. `--cpus` accepts fractional values (`1.5` is fine). `--pids-limit` guards against fork-bombs. `--ulimit nofile` raises the file-descriptor cap for network servers.

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

## Systemd-managed containers

On a server, you want containers to start on boot, restart on failure, and show up in `systemctl status`. Drop this into `/etc/systemd/system/webstack.service`:

```ini
[Unit]
Description=Webstack Compose project
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/webstack
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```

Then enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now webstack
sudo systemctl status webstack
```

For Podman (see next section), the equivalent is `podman generate systemd`, which emits proper unit files directly from a running container. **Don't run Docker containers in a detached `docker run` started from a login shell** — that dies on reboot.

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

Build and run a pod, and generate a systemd unit from a running container:

```bash
podman pod create --name webpod -p 8080:80
podman run -d --pod webpod --name web   nginx:1.27-alpine
podman run -d --pod webpod --name cache redis:7-alpine

podman generate systemd --new --name --files web
mv container-web.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now container-web.service
```

Use Podman when you want rootless containers on a multi-tenant host, when you cannot justify running a root-level daemon, or when you want systemd-native integration without hand-writing unit files.

## Sources

- *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite* — Ghada Atef, 2023 (Docker, Podman, and container workflow chapters).
- Canonical. *Ubuntu Server Guide — Virtualization and Containers*. Canonical Ltd, 2020 (Focal 20.04 LTS edition). <https://ubuntu.com/server/docs>
- Docker Inc. *Docker Engine documentation*. <https://docs.docker.com/engine/>
- Docker Inc. *Compose specification*. <https://docs.docker.com/compose/compose-file/>
- Red Hat. *Podman documentation*. <https://docs.podman.io/>
- `dockerd(8)`, `docker(1)`, `docker-compose(1)`, `podman(1)` manual pages.
