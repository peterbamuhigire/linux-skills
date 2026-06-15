# LXD System Containers — Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

LXD is Canonical's system-container manager. Where Docker packages one process, LXD packages a whole Linux userland that looks and feels like a small VM — systemd inside, SSH if you want it, its own users, its own `/etc` — while still sharing the host kernel. That trade-off (kernel shared, userland isolated) is what makes LXD fast to start, cheap to snapshot, and easy to migrate. This reference covers the daemon, the `lxc` client, storage backends, profiles, devices, networks, resource limits, privileged vs unprivileged containers, cloud-init, snapshots, backups, and worked examples end-to-end.

## Table of contents

- [Architecture](#architecture)
- [Install and initialise](#install-and-initialise)
- [Storage backends and trade-offs](#storage-backends-and-trade-offs)
- [Profiles](#profiles)
- [Devices](#devices)
- [Launch, exec, file push/pull](#launch-exec-file-pushpull)
- [Networks](#networks)
- [Storage pools and volumes](#storage-pools-and-volumes)
- [Snapshots and restore](#snapshots-and-restore)
- [Publishing images](#publishing-images)
- [Copy, move, and remotes](#copy-move-and-remotes)
- [Resource limits](#resource-limits)
- [Unprivileged vs privileged containers](#unprivileged-vs-privileged-containers)
- [Cloud-init integration](#cloud-init-integration)
- [Common errors](#common-errors)
- [Worked examples](#worked-examples)
- [Sources](#sources)

## Architecture

LXD is a daemon (`lxd`) that talks to a client (`lxc`) over a UNIX socket or HTTPS. Do not confuse this `lxc` — the LXD client — with the legacy `lxc-*` tools (`lxc-create`, `lxc-start`) from the original LXC project. LXD uses LXC under the covers for low-level container tasks, but maintains its own configuration store, its own image cache, and its own conventions. Mixing classic `lxc-*` commands with LXD containers is unsupported.

The LXD daemon owns: a local REST API on `/var/snap/lxd/common/lxd/unix.socket` (snap install) or `/var/lib/lxd/unix.socket` (deb); an optional HTTPS endpoint on a configurable port (`core.https_address`); storage pools (ZFS, btrfs, LVM, directory, Ceph); managed networks (`lxdbr0` by default); the image cache under `/var/snap/lxd/common/lxd/images/`; and profiles, which are reusable bundles of config and devices. The `lxc` client talks to the default local remote out of the box. You can add extra remotes (other LXD servers, image servers) and operate on them by prefixing commands with `remote:`.

Check which daemon is running and the client version:

```bash
lxd --version && lxc version
systemctl status snap.lxd.daemon    # snap install
systemctl status lxd                # deb install
```

## Install and initialise

Install via snap on Ubuntu 20.04 and newer — this is the Canonical path and the only one that gets timely updates:

```bash
sudo snap install lxd
sudo usermod -aG lxd "$USER"
newgrp lxd
```

Run `lxd init` once per host. It asks about clustering, storage backend, pool size, network bridge, and whether the API should listen on the network. Accept defaults for a single-host workstation; configure explicitly for a server:

```bash
sudo lxd init
```

For unattended provisioning (cloud-init, Ansible), feed a YAML preseed:

```bash
cat <<'EOF' | sudo lxd init --preseed
config:
  core.https_address: "[::]:8443"
  core.trust_password: "change-this-long-secret"
networks:
  - name: lxdbr0
    type: bridge
    config:
      ipv4.address: 10.10.10.1/24
      ipv4.nat: "true"
      ipv6.address: none
storage_pools:
  - name: default
    driver: zfs
    config:
      size: 50GB
profiles:
  - name: default
    devices:
      eth0:
        name: eth0
        network: lxdbr0
        type: nic
      root:
        path: /
        pool: default
        type: disk
EOF
```

Verify the daemon sees the pool, network, and profile:

```bash
lxc storage list
lxc network list
lxc profile list
```

## Storage backends and trade-offs

LXD supports multiple backends for container rootfs storage. Pick one **before** you launch containers — migrating a container between pools is supported but disruptive.

| Backend | Copy-on-write | Snapshots | Recommended for | Notes |
|---|---|---|---|---|
| `zfs` | yes | instant | **production servers** | Canonical's recommended default. Needs `zfsutils-linux`. Dataset per container, cheap clones, send/receive for migration. |
| `btrfs` | yes | instant | workstations, dev | Similar to ZFS, subvolume per container. Use when ZFS is off-limits (licensing, kernel). |
| `lvm` | yes (thin) | yes | shared SANs, enterprise | LVM thin pool on a dedicated VG. Good with hardware RAID. Slower to launch than ZFS. |
| `dir` | no | slow (rsync) | tiny test hosts only | Plain directories. No COW, no cheap snapshots, snapshot cost scales with container size. **Never** use in production. |
| `ceph` | yes | yes | clusters | Requires an external Ceph cluster. Enables live migration between LXD cluster members. |

With ZFS, launching a new container is effectively free — the new rootfs is a COW clone of the cached image dataset. Snapshots are instant and nearly free on disk until you diverge.

Create a secondary pool (for example, a fast NVMe pool for databases):

```bash
sudo lxc storage create fast zfs source=/dev/nvme0n1
lxc storage list
lxc storage info fast
```

Destroy a pool (must be empty first):

```bash
lxc storage delete fast
```

## Profiles

A profile is a named bag of config keys and devices that can be applied to any number of containers. Profiles are layered: multiple profiles apply in order, then container-specific overrides win. Every container starts with the `default` profile unless you say otherwise.

Look at the default profile, then create a hardened web profile with a 2 GiB memory cap, 2 CPU cores, and a rootfs disk quota of 10 GiB:

```bash
lxc profile show default

lxc profile create web
lxc profile set web limits.memory 2GiB
lxc profile set web limits.cpu 2
lxc profile device add web root disk path=/ pool=default size=10GiB
lxc profile device add web eth0 nic name=eth0 network=lxdbr0
```

Attach both `default` and `web` to a new container at launch, swap profiles on an existing container, and edit a profile in your `$EDITOR`:

```bash
lxc launch ubuntu:22.04 web-prod --profile default --profile web
lxc profile assign web-prod default,web,monitoring
lxc profile edit web
```

## Devices

Devices are the hardware surface of the container: disks, NICs, GPUs, proxies, UNIX sockets. They attach either via a profile (shared) or directly on the container (one-off).

| Device type | Purpose | Example key |
|---|---|---|
| `disk` | rootfs or bind-mount host path | `source=/opt path=/opt` |
| `nic` | network interface | `network=lxdbr0 name=eth0` |
| `proxy` | forward TCP/UDP/unix between host and container | `listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443` |
| `gpu` | expose a host GPU | `gputype=physical pci=0000:01:00.0` |
| `unix-char` / `unix-block` | pass a device node | `source=/dev/ttyUSB0` |
| `none` | mask an inherited device | — |

Bind-mount the host's `/srv/data` into the container at `/data`, forward host port 443 into the container's localhost:443, mask an inherited NIC, and remove a device:

```bash
lxc config device add web-prod data disk source=/srv/data path=/data
lxc config device add web-prod https proxy listen=tcp:0.0.0.0:443 connect=tcp:127.0.0.1:443
lxc config device add web-prod eth1 none
lxc config device remove web-prod data
```

## Launch, exec, file push/pull

Launch a fresh Ubuntu 22.04 container:

```bash
lxc launch ubuntu:22.04 web-prod
lxc list web-prod
```

`ubuntu:` is the Canonical image remote; `images:` is the community `linuxcontainers.org` remote. List available images:

```bash
lxc image list ubuntu: 22.04
lxc image list images: debian/12
lxc image info ubuntu:22.04
```

Open a shell and run one-off commands without entering:

```bash
lxc exec web-prod -- bash
lxc exec web-prod -- systemctl status nginx
lxc exec web-prod -- sudo -u www-data bash -c 'cd /var/www && ls -la'
```

Push and pull files across the host/container boundary:

```bash
lxc file push ./nginx.conf web-prod/etc/nginx/nginx.conf --mode 0644
lxc file push -r ./site/ web-prod/var/www/site/
lxc file pull web-prod/var/log/nginx/access.log ./access.log
lxc file edit web-prod/etc/hosts
```

Stop, start, restart, delete:

```bash
lxc stop  web-prod
lxc start web-prod
lxc restart web-prod
lxc delete web-prod            # stopped containers only
lxc delete web-prod --force    # stop and delete in one go
```

## Networks

LXD creates `lxdbr0` by default: a managed bridge with its own DHCP server (`dnsmasq`), NAT out to the host's default route, and a private `/24`. Containers on `lxdbr0` can reach the internet and each other; the outside world cannot reach them except via a `proxy` device or explicit host firewall rules.

Inspect the bridge, then create a second isolated bridge with no internet access (useful for a private database tier):

```bash
lxc network list
lxc network show lxdbr0
lxc network info lxdbr0

lxc network create lxdbr-private \
    ipv4.address=10.20.20.1/24 \
    ipv4.nat=false \
    ipv6.address=none
```

Attach a container to two networks — one public, one private:

```bash
lxc config device add db-prod eth0 nic network=lxdbr0 name=eth0
lxc config device add db-prod eth1 nic network=lxdbr-private name=eth1
```

You can also bridge containers directly onto an unmanaged host bridge (for example `br0` that netplan created on the physical NIC). In that case LXD will not run DHCP — the container will appear on the LAN with whatever address your upstream DHCP server hands out:

```bash
lxc profile device set default eth0 parent br0 nictype=bridged
```

Assign a static IPv4 to a container on `lxdbr0`:

```bash
lxc config device set web-prod eth0 ipv4.address 10.10.10.42
lxc restart web-prod
```

## Storage pools and volumes

Beyond the rootfs, you can create named volumes on any pool and attach them to one or more containers. Volumes are first-class — they survive container deletion, can be backed up independently, and can be shared.

Create and attach a custom volume, then inspect:

```bash
lxc storage volume create default shared-data size=20GiB
lxc storage volume attach default shared-data web-prod /mnt/shared
lxc storage volume attach default shared-data worker-prod /mnt/shared
lxc storage volume list default
lxc storage volume show default shared-data
```

Snapshot a volume independently of any container, then detach and delete:

```bash
lxc storage volume snapshot default shared-data pre-migration
lxc storage volume restore  default shared-data pre-migration
lxc storage volume detach default shared-data web-prod
lxc storage volume delete default shared-data
```

## Snapshots and restore

A container snapshot is a point-in-time copy of the rootfs plus the container's config. On ZFS and btrfs it is instant and costs almost nothing until the live container diverges. **Standing rule:** snapshot **before** any mutating change — package upgrade, config edit, kernel-level tweak. Name the snapshot after what you are about to do.

```bash
lxc snapshot web-prod before-nginx-upgrade-2026-04-10
lxc info web-prod | grep -A5 Snapshots
```

List all snapshots on the host (useful before a cleanup):

```bash
for c in $(lxc list -c n --format csv); do
    lxc info "$c" | awk '/Snapshots:/{f=1;next}/^[A-Z]/{f=0}f'
done
```

Roll back — this replaces the live rootfs with the snapshot and restarts the container — then delete a snapshot you no longer need:

```bash
lxc restore web-prod before-nginx-upgrade-2026-04-10
lxc delete web-prod/before-nginx-upgrade-2026-04-10
```

**Snapshots are not backups.** They live in the same ZFS pool; a disk failure takes them with the live container. For off-host protection, use `lxc export` (see next section).

## Publishing images

You can turn a prepared container into a reusable image — a golden base — and then launch fresh containers from it.

```bash
lxc stop web-prod
lxc publish web-prod --alias web-base-2026-04
lxc image list local: web-base-2026-04
```

Export the image to a tarball for off-host storage or transfer, then import on another host:

```bash
lxc image export web-base-2026-04 /backups/images/web-base-2026-04
# produces web-base-2026-04.tar.gz
lxc image import /backups/images/web-base-2026-04.tar.gz --alias web-base-2026-04
lxc launch web-base-2026-04 web-staging
```

For full container backups (rootfs + config + snapshots in one tar), use `lxc export` instead of `lxc publish`:

```bash
lxc export web-prod /backups/lxd/web-prod-$(date +%F).tar.gz
lxc import /backups/lxd/web-prod-2026-04-10.tar.gz
```

## Copy, move, and remotes

Add a second LXD server as a remote. The target server must have an HTTPS listener and a trust password set:

```bash
# on the target:
sudo lxc config set core.https_address "[::]:8443"
sudo lxc config set core.trust_password 'long-secret'

# on the source:
lxc remote add server-b 203.0.113.10:8443 --password 'long-secret'
lxc remote list
```

Copy a container to the remote preserving snapshots, live-migrate (the container keeps running, then stops on the source and starts on the target — requires matching storage driver and CRIU for a fully live transfer), or rename in place:

```bash
lxc copy web-prod server-b: --mode=push
lxc move web-prod server-b:web-prod --mode=pull
lxc move web-prod web-prod-old
```

## Resource limits

LXD enforces limits through cgroups. Set them in a profile (for everything that uses the profile) or on an individual container. Limits are mandatory in production — an unbounded container will happily eat all of the host's RAM.

```bash
# Memory
lxc config set web-prod limits.memory 2GiB
lxc config set web-prod limits.memory.swap false
lxc config set web-prod limits.memory.enforce hard    # OOM-kill on overrun

# CPU — pin to cores, cap share, or both
lxc config set web-prod limits.cpu 2              # 2 vCPUs
lxc config set web-prod limits.cpu 0,1            # pinned to cores 0 and 1
lxc config set web-prod limits.cpu.allowance 50%  # 50% of total CPU time

# Rootfs disk quota (ZFS/btrfs/LVM only — dir backend ignores this)
lxc config device set web-prod root size=10GiB

# Network priority under contention, and process cap against fork-bombs
lxc config set web-prod limits.network.priority 5
lxc config set web-prod limits.processes 500

# Inspect what's currently applied
lxc config show web-prod --expanded
```

## Unprivileged vs privileged containers

LXD creates **unprivileged** containers by default. This means root (UID 0) inside the container is mapped to a non-root UID (typically 100000) on the host. A compromise inside the container cannot touch host files it has no mapping for. Combined with the default AppArmor profile (which blocks dangerous syscalls and writes to un-namespaced sysctls) and a default seccomp policy (which blocks kernel module load, kexec, forced umount, `open_by_handle_at`), this gives strong isolation for the overwhelming majority of workloads.

A **privileged** container maps container-root to host-root. That removes the UID shift entirely. It is the right choice only when you genuinely need the container to perform host-level operations — for example, a container running `zfs` commands against host datasets, or holding a `/dev` device that the unprivileged mapping cannot reach. **Privileged containers are banned in production unless you have a written justification.**

Promote a container to privileged (destructive — existing files will be re-chowned) and enable nesting (needed to run LXD or Docker inside an LXD container):

```bash
lxc stop web-prod
lxc config set web-prod security.privileged true
lxc start web-prod
lxc config set web-prod security.nesting true
```

If you need kernel modules available to the container without going fully privileged, load them on the host:

```bash
echo "overlay"      | sudo tee -a /etc/modules-load.d/lxd.conf
echo "netlink_diag" | sudo tee -a /etc/modules-load.d/lxd.conf
sudo modprobe overlay netlink_diag
```

## Cloud-init integration

LXD images from the `ubuntu:` remote ship with cloud-init. Feed user-data through the `cloud-init.user-data` config key (or a profile device) and it runs on first boot — exactly as it would on a real VM.

One-shot container that installs Nginx on first boot:

```bash
lxc launch ubuntu:22.04 web-prod --config=user.user-data="$(cat <<'EOF'
#cloud-config
package_update: true
packages:
  - nginx
  - ufw
write_files:
  - path: /etc/nginx/sites-available/default
    content: |
      server {
        listen 80 default_server;
        root /var/www/html;
        index index.html;
      }
runcmd:
  - systemctl enable --now nginx
EOF
)"
```

Watch cloud-init finish, or put the same config into a reusable profile:

```bash
lxc exec web-prod -- cloud-init status --wait
lxc exec web-prod -- journalctl -u cloud-final --no-pager

lxc profile create cloud-web
lxc profile set cloud-web user.user-data - <<'EOF'
#cloud-config
packages: [nginx, ufw]
runcmd:
  - systemctl enable --now nginx
EOF
lxc launch ubuntu:22.04 web-staging --profile default --profile cloud-web
```

## Common errors

- **`Error: Failed to run: zfs list -r -H -o name rpool`** — the host has no ZFS pool named `rpool` but your LXD config references it. Run `lxd init` again or fix `lxc storage list`.
- **`Error: The "lxdbr0" device doesn't exist`** — the bridge was deleted or never created. Recreate with `lxc network create lxdbr0`.
- **`Error: Failed to start device "eth0"` / `ip link add`** — another container holds the same MAC or IP. Check `lxc list` for duplicates and either delete the orphan or reassign.
- **`Error: Failed container creation: not enough space`** — the storage pool is full. Run `lxc storage info default` and prune old snapshots (`lxc delete name/snap`) or grow the pool.
- **`Error: disk too small`** — you set `root size=` smaller than what is already on the rootfs. Clean up inside the container or raise the quota.
- **Container stuck in `Starting` / `Stopping`** — check the daemon log with `sudo journalctl -u snap.lxd.daemon -n 200 --no-pager` and `lxc info web-prod --show-log`.
- **AppArmor DENIED in `dmesg`** — a workload inside the container tried to do something the default profile blocks. Either adjust the workload or add a raw AppArmor override (rare; document why): `lxc config set web-prod raw.apparmor "mount fstype=fuse,"` then `lxc restart web-prod`.

## Worked examples

### 1. Single web container with static IP and port forward

```bash
lxc launch ubuntu:22.04 web-prod
lxc config device set web-prod eth0 ipv4.address 10.10.10.42
lxc config set web-prod limits.memory 2GiB
lxc config set web-prod limits.cpu 2
lxc config device set web-prod root size=10GiB
lxc exec web-prod -- apt update
lxc exec web-prod -- apt install -y nginx
lxc config device add web-prod http proxy \
    listen=tcp:0.0.0.0:80 \
    connect=tcp:127.0.0.1:80
lxc restart web-prod
curl -I http://$(hostname -I | awk '{print $1}')
```

### 2. Three containers sharing a dedicated ZFS pool

```bash
sudo lxc storage create app-pool zfs source=/dev/sdb
lxc profile copy default app
lxc profile device set app root pool=app-pool size=20GiB
lxc launch ubuntu:22.04 app-web     --profile default --profile app
lxc launch ubuntu:22.04 app-worker  --profile default --profile app
lxc launch ubuntu:22.04 app-db      --profile default --profile app
lxc storage volume create app-pool shared-cache size=5GiB
lxc storage volume attach app-pool shared-cache app-web    /mnt/cache
lxc storage volume attach app-pool shared-cache app-worker /mnt/cache
lxc list
```

### 3. Container with physical GPU passthrough (for ML inference)

```bash
lspci | grep -i nvidia                          # confirm GPU on host
lxc launch ubuntu:22.04 ml-inference
lxc config device add ml-inference gpu gpu \
    gputype=physical \
    pci=0000:01:00.0
lxc config set ml-inference nvidia.runtime true
lxc config set ml-inference nvidia.driver.capabilities compute,utility
lxc restart ml-inference
lxc exec ml-inference -- nvidia-smi
```

### 4. Live-migrate a container between two hosts

```bash
# host-a
sudo lxc config set core.https_address "[::]:8443"
sudo lxc config set core.trust_password 'long-secret-42'

# host-b (the source)
lxc remote add host-a 203.0.113.10:8443 --password 'long-secret-42'
lxc snapshot web-prod pre-migrate-2026-04-10
lxc move web-prod host-a:web-prod --mode=push
lxc list host-a:
```

### 5. Restore a container from an off-host backup tar

```bash
# nightly on each host
for c in $(lxc list -c n --format csv); do
    lxc export "$c" "/backups/lxd/${c}-$(date +%F).tar.gz" --optimized-storage
done
rclone copy /backups/lxd/ remote:lxd-backups/

# restore on a new host
rclone copy remote:lxd-backups/web-prod-2026-04-09.tar.gz /tmp/
sudo snap install lxd
sudo lxd init --auto
lxc import /tmp/web-prod-2026-04-09.tar.gz
lxc start web-prod
lxc info web-prod
```

### 6. Container nested inside a container (dev sandbox)

```bash
lxc launch ubuntu:22.04 sandbox
lxc config set sandbox security.nesting true
lxc config set sandbox limits.memory 4GiB
lxc config set sandbox limits.cpu 4
lxc restart sandbox
lxc exec sandbox -- bash -c 'snap install lxd && lxd init --auto'
lxc exec sandbox -- lxc launch ubuntu:22.04 inner
lxc exec sandbox -- lxc list
```

## Sources

- Canonical. *Ubuntu Server Guide — LXD, Virtualization, and LXC chapters*. Canonical Ltd, 2020 (Focal 20.04 LTS edition). <https://ubuntu.com/server/docs>
- LXD upstream configuration reference. <https://github.com/lxc/lxd/blob/master/doc/configuration.md>
- Stéphane Graber. *LXD 2.0 blog series*. <https://stgraber.org/2016/03/11/lxd-2-0-blog-post-series-012/>
- `lxd(1)`, `lxc(1)`, `lxc.container.conf(5)` manual pages on Ubuntu 22.04.
