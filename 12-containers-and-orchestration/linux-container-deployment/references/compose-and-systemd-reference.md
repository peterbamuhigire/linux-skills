# Compose & Systemd-managed Containers — Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This reference covers **running** containers as long-lived, supervised
workloads: Compose v2 (Docker) and `podman compose`, restart policies and
resource limits at run time, and the three ways to make containers survive a
reboot — a hand-written Docker compose unit, `podman generate systemd`, and
Quadlet `.container` units. Installing/configuring the engine is in
`linux-container-engine`; pruning is in `linux-image-hygiene`.

## Table of contents

- [Lifecycle verbs](#lifecycle-verbs)
- [Restart policies](#restart-policies)
- [Resource limits at run time](#resource-limits-at-run-time)
- [Compose v2 (Docker)](#compose-v2-docker)
- [podman compose](#podman-compose)
- [Docker compose as a systemd service](#docker-compose-as-a-systemd-service)
- [podman generate systemd](#podman-generate-systemd)
- [Quadlet .container units](#quadlet-container-units)
- [Sources](#sources)

## Lifecycle verbs

```bash
docker run -d --name web --restart unless-stopped -p 8080:80 nginx:1.27-alpine
docker ps                # running   /  docker ps -a for stopped too
docker logs -f --tail 100 web
docker top web           # processes inside
docker exec -it web sh
docker inspect web --format '{{.State.Status}}: {{.State.Error}}'
docker stop web; docker start web; docker restart web
docker rm -f web
```

Every verb works under `podman` with the name substituted. Rootless Podman
containers run in the invoking user's namespace.

## Restart policies

The default policy is `no` — a crashed container stays dead. Pick one
explicitly.

| Policy | When to use |
|---|---|
| `no` | one-off batch jobs (`docker run --rm`) |
| `on-failure[:max]` | retry a bounded number of times |
| `always` | always run, even after operator stop |
| `unless-stopped` | always run but respect operator `stop` across reboots — usual pick |

```bash
docker run -d --name web --restart unless-stopped -p 80:80 nginx:1.27-alpine
```

In a systemd/Quadlet unit, `Restart=always` / `Restart=on-failure` is the
systemd-native equivalent and should be preferred when the container is managed
by systemd.

## Resource limits at run time

Unbounded containers eat the host. Set limits on the CLI or in compose
(`deploy.resources.limits`):

```bash
docker run -d --name app \
    --memory 1g --memory-swap 1g --memory-reservation 512m \
    --cpus 2 --pids-limit 200 --ulimit nofile=65536:65536 \
    myapp:2026.04.10
```

`--memory` is a hard cap (OOM-kill on overrun); `--memory-swap` equal to
`--memory` disables swap; `--cpus` accepts fractions; `--pids-limit` guards
against fork-bombs.

## Compose v2 (Docker)

Compose v2 is the `docker compose` subcommand. It reads `compose.yaml` (or the
legacy `docker-compose.yml`) from the working directory.

```yaml
name: webstack
services:
  web:
    image: nginx:1.27-alpine@sha256:aaaa...
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - webdata:/usr/share/nginx/html
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
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:3000/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
volumes:
  webdata:
```

```bash
docker compose config            # validate without starting
docker compose up -d
docker compose ps
docker compose logs -f --tail 100 app
docker compose exec app sh
docker compose pull && docker compose up -d   # rolling update
docker compose down              # stop+remove (down -v also drops named volumes)
```

## podman compose

Podman provides `podman compose` (a wrapper that shells out to an installed
compose provider) and the standalone `podman-compose` package. The same
`compose.yaml` works, but add `:Z`/`:z` to bind-mount volumes on SELinux hosts:

```bash
sudo dnf install -y podman-compose          # or: pip install podman-compose
podman compose up -d
podman compose ps
podman compose down
```

`podman compose` is convenient but the **Podman-native** way to run a stack is a
**pod** plus Quadlet units (below) — that integrates with systemd and survives
reboot without a compose process in the loop.

```bash
podman pod create --name webpod -p 8080:80
podman run -d --pod webpod --name web   nginx:1.27-alpine
podman run -d --pod webpod --name cache redis:7-alpine
```

## Docker compose as a systemd service

A bare detached `docker run`/`docker compose up -d` from a login shell does not
survive a reboot. Wrap the project in a oneshot unit:

```ini
# /etc/systemd/system/webstack.service
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

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now webstack
sudo systemctl status webstack
```

## podman generate systemd

`podman generate systemd` emits a unit file from an **existing** container or
pod. It is the pre-Quadlet approach and still works on RHEL 8.

```bash
# create the container first, then generate its unit
mkdir -p ~/.config/systemd/user && cd ~/.config/systemd/user
podman generate systemd --new --name --files web
systemctl --user daemon-reload
loginctl enable-linger "$USER"        # start at boot, not just at login
systemctl --user enable --now container-web.service
```

`--new` makes the unit recreate the container from its image on start (rather
than reusing a stored container), which is what you want for reproducibility.
For root-level services drop the unit into `/etc/systemd/system/` and use
`systemctl` without `--user`.

> `[GROUNDING-GAP: podman generate systemd is documented in RHCSA 8 (Sander van Vugt, Ch. 26); Quadlet below is newer — grounded on Podman/Docker upstream docs; deepen with Container Security (Liz Rice)]`

## Quadlet .container units

On RHEL 9+ (Podman 4.4+), **Quadlet** is the recommended path: you write a
declarative `.container` (or `.pod`, `.network`, `.volume`) file, and systemd's
Quadlet generator turns it into a `.service` at daemon-reload. There is no
generated file to drift.

```ini
# /etc/containers/systemd/web.container        (system)
# ~/.config/containers/systemd/web.container    (rootless)
[Unit]
Description=nginx web container
After=network-online.target

[Container]
Image=docker.io/library/nginx:1.27-alpine
PublishPort=8080:80
Volume=/srv/www:/usr/share/nginx/html:ro,Z
Environment=TZ=UTC
NoNewPrivileges=true

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target default.target
```

```bash
sudo systemctl daemon-reload          # Quadlet generates web.service
sudo systemctl start web.service
systemctl status web.service
# rootless: systemctl --user daemon-reload && loginctl enable-linger "$USER"
```

> `[GROUNDING-GAP: Quadlet .container/.pod/.network units — grounded on Podman/Docker upstream docs; deepen with Container Security (Liz Rice)]`

## Sources

- *Red Hat RHCSA 8 Cert Guide (EX200)* — Sander van Vugt, 2nd ed. (Ch. 26: managing containers, `podman generate systemd`, rootless, registries).
- *Red Hat Enterprise Linux 9 for System Administrators* — Jerome Gotangco (container chapter: Podman, compose, container network).
- Docker Inc. *Compose specification*. <https://docs.docker.com/compose/compose-file/>
- Red Hat. *Podman & Quadlet documentation*. <https://docs.podman.io/>
- `podman-systemd.unit(5)` (Quadlet), `podman-generate-systemd(1)`, `docker-compose(1)` manual pages.
