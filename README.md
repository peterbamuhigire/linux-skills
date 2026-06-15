# linux-skills

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

A **two-family Linux server management engine** — a curated knowledge base of
**25 specialist skills**, 5 RHEL-family deep-dive references, an engine
specification, and a growing suite of interactive, idempotent `sk-*` scripts
that wrap the skills as command-line tools.

The engine targets **both major server families**:

- **Debian family** — Debian, Ubuntu (and derivatives: Mint, Pop!_OS, Raspbian)
- **RHEL family** — Fedora, RHEL, CentOS Stream, Rocky Linux, AlmaLinux,
  Oracle Linux

Every skill carries a **Distro support** matrix that maps each Debian/Ubuntu
command, path, and service to its RHEL-family equivalent, and every `sk-*`
script resolves the difference automatically through the `common.sh` library.

The repository stays fully usable in **Claude Code** while also working cleanly
in **Codex**. `SKILL.md` is the portable unit; [`CLAUDE.md`](CLAUDE.md) and
[`AGENTS.md`](AGENTS.md) provide host-specific guidance layered on top.

---

## How the two-family design works

There are no per-distro forks. One `SKILL.md` serves both families, and the
difference is pushed down into two layers:

1. **`common.sh` primitives** — scripts call `pkg_install nginx`, never
   `apt install nginx`. The library detects the family and dispatches.
2. **Per-skill "Distro support" matrices** — a Debian-column / RHEL-column
   table at the top of every skill for the human/agent-facing commands.

### The `common.sh` distro primitives

| Need | Don't hardcode | Use this primitive |
|---|---|---|
| Detect the family | parse `/etc/os-release` | `detect_distro` → `SK_DISTRO_FAMILY`, `SK_PKG` |
| Install / remove / update | `apt` / `dnf` | `pkg_install`, `pkg_remove`, `pkg_update` |
| Is a package installed? | `dpkg -s` / `rpm -q` | `pkg_is_installed` |
| Enable extra repo | EPEL release RPM | `ensure_epel` (no-op off-RHEL **and** on Fedora) |
| Service unit name | `apache2` / `httpd` | `svc_name apache` |
| Open a firewall port | `ufw allow` / `firewall-cmd` | `firewall_allow` |
| Web config dir / reload | `sites-available` / `conf.d` | `web_conf_dir`, `web_reload` |
| Gate a script to a family | check `$ID` | `require_family <debian\|rhel\|any>` |

`detect_distro` classifies by `ID` then `ID_LIKE`, so derivatives resolve to the
right family automatically. The two real intra-RHEL branch points — **EPEL**
(needed on RHEL/Rocky/Alma, not Fedora) and **dnf4 vs dnf5** — are handled
inside the primitives. Full contract:
[`linux-bash-scripting/references/common-sh-contract.md`](linux-bash-scripting/references/common-sh-contract.md).

---

## The big family differences (and where they're documented)

| Domain | Debian/Ubuntu | RHEL family | Deep-dive reference |
|---|---|---|---|
| Packages | apt, snap, unattended-upgrades | dnf, flatpak, dnf-automatic, EPEL | `linux-package-management` |
| Firewall | UFW (flat allow-list) | **firewalld** (zones) | [`firewalld-reference.md`](linux-firewall-ssl/references/firewalld-reference.md) |
| Mandatory access control | AppArmor | **SELinux** (enforcing) | [`selinux-reference.md`](linux-server-hardening/references/selinux-reference.md) |
| Apache | `apache2`, sites-available | **`httpd`**, conf.d (no a2ensite) | [`httpd-reference.md`](linux-webstack/references/httpd-reference.md) |
| Networking | Netplan | **NetworkManager / nmcli** | [`networkmanager-reference.md`](linux-network-admin/references/networkmanager-reference.md) |
| Install automation | autoinstall (subiquity) | **Kickstart** (Anaconda) | [`kickstart-reference.md`](linux-cloud-init/references/kickstart-reference.md) |
| Admin group | `sudo` | `wheel` | `linux-access-control` |
| Containers | LXD / Docker | **Podman** / Docker | `linux-virtualization` |
| Time sync | systemd-timesyncd | chrony | `linux-network-admin` |

---

## Structure

```
docs/engine-design/      Engine specification + curated script inventory
docs/multi-distro/       The two-family upgrade plan + status
linux-bash-scripting/    Meta-skill: how every sk-* script is written
linux-<domain>/          23 specialist skills, each with SKILL.md + references/
scripts/                 Executable scripts (sk-* + common.sh library + tests)
commands/                Command references by topic
notes/                   Setup guides and troubleshooting
```

---

## Start here

1. **Pick the family-aware entry point.** Use `linux-sysadmin` as the routing
   hub: "what do you want to do?" → the right specialist skill.
2. **Read the engine design.** Conventions live in
   [`docs/engine-design/spec.md`](docs/engine-design/spec.md); the curated
   script catalogue is in
   [`docs/engine-design/script-inventory.md`](docs/engine-design/script-inventory.md).
3. **Understand the two-family model.** See
   [`docs/multi-distro/plan.md`](docs/multi-distro/plan.md) for the design,
   phasing, and current status.
4. **For Codex / non-Claude agents**, read [`AGENTS.md`](AGENTS.md).
5. **Install on a fresh server** with
   [`scripts/setup-claude-code.sh`](scripts/setup-claude-code.sh), then
   `sudo install-skills-bin core`.

---

## The 25 skills

Every specialist skill below leads with a **`## Distro support`** matrix
(Debian/Ubuntu ↔ RHEL family). The `linux-sysadmin` hub is the only exempt
skill (it routes, it doesn't operate).

**Foundation**
- [`linux-bash-scripting`](linux-bash-scripting/SKILL.md) — meta-skill. Script
  template, the `common.sh` contract **including the distro primitives**,
  standard flags, interactive UX, safety patterns.
- [`linux-sysadmin`](linux-sysadmin/SKILL.md) — the routing hub.

**Security**
- [`linux-security-analysis`](linux-security-analysis/SKILL.md) — 10-layer
  read-only audit (SELinux/AppArmor aware).
- [`linux-server-hardening`](linux-server-hardening/SKILL.md) — apply fixes;
  ships the shared [SELinux reference](linux-server-hardening/references/selinux-reference.md).
- [`linux-access-control`](linux-access-control/SKILL.md) — users, SSH keys,
  permissions, `sudo`/`wheel`.
- [`linux-firewall-ssl`](linux-firewall-ssl/SKILL.md) — UFW **and firewalld**,
  certbot, TLS.
- [`linux-intrusion-detection`](linux-intrusion-detection/SKILL.md) — fail2ban,
  AIDE, auditd, SELinux AVC denials.
- [`linux-secrets`](linux-secrets/SKILL.md) — scanning, age/sops, rotation.

**Operations**
- [`linux-server-provisioning`](linux-server-provisioning/SKILL.md) — fresh
  server setup on either family.
- [`linux-cloud-init`](linux-cloud-init/SKILL.md) — cloud-init (portable) +
  **autoinstall and Kickstart**.
- [`linux-site-deployment`](linux-site-deployment/SKILL.md) — deploy sites
  (static, PHP, Node), conf.d + SELinux docroot labeling.
- [`linux-repo-sync`](linux-repo-sync/SKILL.md) — safe git updates:
  `pull --rebase --autostash`, never `reset --hard`.
- [`linux-service-management`](linux-service-management/SKILL.md) — systemd
  (identical) with family unit-name mapping.
- [`linux-webstack`](linux-webstack/SKILL.md) — Nginx + Apache/httpd + PHP-FPM
  + Node.js; ships the [httpd reference](linux-webstack/references/httpd-reference.md).
- [`linux-package-management`](linux-package-management/SKILL.md) — apt/snap +
  **dnf/flatpak/dnf-automatic/EPEL**.
- [`linux-disk-storage`](linux-disk-storage/SKILL.md) — usage, cleanup, inodes,
  swap (ext4/XFS aware).
- [`linux-system-monitoring`](linux-system-monitoring/SKILL.md) — CPU, memory,
  disk, network health.
- [`linux-log-management`](linux-log-management/SKILL.md) — journalctl + the
  family log-path differences, logrotate.

**Networking**
- [`linux-network-admin`](linux-network-admin/SKILL.md) — interfaces, routes,
  Netplan **and NetworkManager/nmcli**, DNS client, NTP/chrony.
- [`linux-dns-server`](linux-dns-server/SKILL.md) — authoritative DNS
  (`bind9`/`bind`, unbound), SELinux zone contexts.
- [`linux-mail-server`](linux-mail-server/SKILL.md) — Postfix, Dovecot, SPF,
  DKIM (EPEL), DMARC.

**Containers & automation**
- [`linux-virtualization`](linux-virtualization/SKILL.md) — LXD/**Podman**,
  Docker, KVM/libvirt, SELinux volume labels.
- [`linux-config-management`](linux-config-management/SKILL.md) — Ansible
  (family-neutral modules), drift detection, AppArmor/SELinux.
- [`linux-observability`](linux-observability/SKILL.md) — Prometheus
  node_exporter, log shipping, `/health`.

**Recovery**
- [`linux-troubleshooting`](linux-troubleshooting/SKILL.md) — symptom-based
  diagnosis trees; SELinux as a hidden cause on RHEL.
- [`linux-disaster-recovery`](linux-disaster-recovery/SKILL.md) — restore from
  backup, GRUB2/dracut/xfs_repair differences.

---

## Scripts & the `common.sh` library

The `sk-*` scripts are an **optional fast path** — never a dependency. Every
script sources `/usr/local/lib/linux-skills/common.sh`, which provides output
primitives, guards, safe file ops, standard flag parsing, a cleanup trap, and
the **distro-detection primitives** above.

Currently migrated to be fully two-family:

| Script | Purpose |
|---|---|
| [`sk-audit`](scripts/sk-audit.sh) | Read-only 14-section security audit. Family-specific checks (updates, firewall, Apache, admin group, SELinux/AppArmor) auto-detect. |
| [`sk-mysql-backup`](scripts/sk-mysql-backup.sh) | GPG-encrypted MySQL/MariaDB backups with rclone upload and rotation. |

Install scripts with `sudo install-skills-bin <skill-name>` (or
`sudo install-skills-bin core` for the tier-1 foundation).

---

## Testing

```bash
# Library unit tests (run in an Ubuntu/Fedora LXD container via the harness)
sudo ./scripts/tests/run-test.sh --suite foundation

# Two-family invariant: every linux-* skill carries a Distro support matrix
# (pure bash — no container or root needed)
./scripts/tests/check-distro-matrix.sh
```

The unit tests cover the `common.sh` distro detection, family classifier,
`require_family`, `svc_name`, the backward-compatible `require_debian` alias,
and temp-file cleanup. The distro-matrix check is the gate that keeps the
two-family promise from regressing.

---

## Design principles

- **Two families, one body.** A single `SKILL.md` and a single `sk-*` script
  serve both Debian/Ubuntu and the RHEL family. Differences live in the matrix
  and the `common.sh` primitives, never in forks.
- **Skills are self-contained.** Every skill works with the tools that ship on
  a stock server of either family. The `sk-*` scripts are an optional
  accelerator.
- **Scripts track skill updates.** When a skill's knowledge changes, the
  affected scripts are updated in the same session.
- **Idempotency by default.** Every mutating script is safe to run twice.
- **Author attribution is mandatory.** Every file credits Peter Bamuhigire.

---

## Current status

- 25 skills, all specialist skills carrying a Distro support matrix.
- 5 RHEL-family deep-dive references (firewalld, SELinux, httpd,
  NetworkManager, Kickstart).
- `common.sh` family abstraction + unit tests + the distro-matrix invariant
  check.
- `sk-audit` and `sk-mysql-backup` migrated onto the primitives.
- **Pending: live validation on a Fedora/RHEL host** — the documentation and
  scripts are accurate to RHEL behavior but have not yet been executed on a
  real RHEL-family box. Tracked in
  [`docs/multi-distro/plan.md`](docs/multi-distro/plan.md).

---

## Legacy content

- [update-all-repos](scripts/sk-update-all-repos.sh) — pulls every registered
  repo safely (see [`linux-repo-sync`](linux-repo-sync/SKILL.md)).
- [rclone](commands/rclone.md), [redis](commands/redis.md) — command references.
- [notes/](notes/) — setup guides for Astro sites, MySQL backups, Redis,
  server security, new-repo onboarding.
