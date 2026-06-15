# Linux Engine Hardening & Expansion Plan

> Goal: make the linux-skills engine an enterprise-grade autonomous sysadmin — 15 categories,
> every "must-not-miss" skill present and deep, grounded in authoritative references, dual-family
> (Debian/Ubuntu + RHEL/Fedora), following engine conventions. Date: 2026-06-15.

## 0. Principles & grounding rules

- **Book-grounded:** every new/expanded skill cites the mapped reference book section (see the
  coverage map below). Where the corpus is thin, mark `[GROUNDING-GAP]` in the skill and ground
  on upstream docs + man pages until a purchased book fills it.
- **Dual-family:** keep the mandatory `## Distro support` matrix (Debian/Ubuntu + RHEL family).
  The corpus is ~5:1 RHEL-heavy, so Debian/Ubuntu sides need extra care (see book recs).
- **Engine conventions:** SKILL.md frontmatter, `## Distro support`, `## Scripts` manifest of
  `sk-*` scripts on the `common.sh` contract, `references/`. Must pass
  `scripts/tests/check-distro-matrix.sh` and the link-resolution check.
- **Idempotent, safe scripts:** `set -uo pipefail` per the engine contract; ask-before-mutate.

## 1. Book corpus coverage (what we can ground on today)

Usable books (1 was an empty 18-byte extraction — `Debian_125_Bookworm...` — excluded):

| Category | Best grounding | Depth |
|---|---|---|
| 01 Provisioning | Mastering Debian (apt), RHCSA8/10 (dnf/rpm, GRUB2), Fedora Essentials (cloud-init) | DEEP |
| 02 Users/Access | RHCSA10/8 (sudoers, ssh, ed25519) | DEEP (PAM only MODERATE) |
| 03 Networking/DNS | RHCSA8/10 (nmcli/firewalld), Mastering Debian (iptables, BIND9), RHEL9 (nftables) | DEEP (DNS MODERATE) |
| 04 Web/Mail | RHEL9 (httpd/nginx/certbot/HAProxy), Mastering Debian (Postfix/Dovecot) | DEEP |
| 05 Services/Virt | RHCSA10/8 (systemd/timers), Debian+RHEL9 (KVM/libvirt) | DEEP (KVM MODERATE) |
| 06 Storage | RHCSA8 (LVM/fstab/NFS/CIFS/Stratis/VDO) | DEEP (resize2fs/xfs_growfs thin) |
| 07 Security | RHCSA8/10 (SELinux 231), Mastering Debian (AppArmor/Fail2Ban) | DEEP SELinux (rkhunter/chkrootkit = 0) |
| 08 Observability | RHCSA8/10 (journalctl/logrotate), RHEL9 (Prometheus recipe) | DEEP journald (node_exporter/Telegraf ≈ 0) |
| 09 Troubleshooting | RHCSA8/10 (dmesg/OOM) | MODERATE (lsof=0, ltrace≈0, strace/tcpdump thin) |
| 10 Automation | RHCSA8 (cron) | MODERATE (set -euo pipefail = 0 grounding) |
| 11 Databases | RHEL9 (install/manage MySQL/Postgres/Maria recipes) | MODERATE (tuning/WAL/binlog/Redis ≈ NONE) |
| 12 Containers | RHCSA8 (Podman 113, container units), RHEL9 (compose) | DEEP Podman (image prune = 0; RHCSA10 dropped Podman) |
| 13 Backup | RHCSA8 (rsync/tar), Fedora Essentials (ZFS/Btrfs concept) | MODERATE (snapshot send/recv, checksum/bwlimit thin) |
| 14 Performance/Kernel | RHCSA8/10 (modprobe/blacklist), Fedora Ess (sysctl/perf) | MODERATE (swappiness/BBR/perf/iostat thin) |
| 15 Compliance | RHEL9 (auditd recipes), Fedora Ess (cis mention) | MODERATE auditd (AIDE = 0 in books; CIS mention-only) |

**Ungrounded in the corpus (need upstream docs and/or purchased books):** `lsof`/`ltrace`,
`rkhunter`/`chkrootkit`, **AIDE**, `set -euo pipefail` patterns, `netplan`/systemd-networkd
(no Ubuntu book), node_exporter/Telegraf setup, container `image prune`, DB tuning
(InnoDB/postgresql.conf/Redis), ZFS/Btrfs snapshot workflows, swappiness/BBR/`perf`, CIS controls.

## 2. Existing-category gaps to fix (Phase A — harden the 10)

Ranked by impact. Each is an enhancement to an existing skill unless noted.

| # | Skill | Gap (must-not-miss) | Grounding |
|---|---|---|---|
| A1 | `07.../linux-firewall-ssl` | **iptables AND nftables** rulesets/routing (currently ufw/firewalld only) | RHEL9 nftables; Mastering Debian iptables; `[GROUNDING-GAP]` nftables wiki |
| A2 | `07.../linux-intrusion-detection` | **rkhunter / chkrootkit** rootkit scanning | `[GROUNDING-GAP]` upstream + Nemeth handbook |
| A3 | `06.../linux-disk-storage` | **CIFS/Samba** mounts + automount (NFS present) | RHCSA8 Samba/CIFS (95 hits) |
| A4 | `05.../linux-service-management` | **nice/ionice** priority; deepen systemd `targets` | RHCSA8/10 systemd |
| A5 | `09.../linux-troubleshooting` | **tcpdump** as first-class capture workflow; surface lsof/ltrace | RHCSA dmesg/OOM; `[GROUNDING-GAP]` strace/lsof upstream |
| A6 | `01.../linux-server-provisioning` (+ new boot skill?) | **GRUB2 + kernel rollback on panic** (currently only in DR) | RHCSA8/10 GRUB2 (41/31 hits) |
| A7 | `07.../linux-server-hardening` | **deepen SELinux** (semanage/setsebool/restorecon/booleans) to AppArmor parity | RHCSA8 SELinux (231) |
| A8 | `08.../linux-observability` | **Telegraf + Datadog** agents (Prometheus present) | `[GROUNDING-GAP]` upstream |
| A9 | `10.../linux-repo-sync` | add missing **`## Scripts` manifest** (only structural spec violation) | engine spec |

## 3. New categories (Phases B & C)

**Phase B — restructure/expand from existing content (lower risk, content already exists):**

- **12-containers-and-orchestration** — SPLIT Docker/Podman/compose/prune OUT of
  `05.../linux-virtualization` (which is container-heavy) into its own category; keep KVM/libvirt
  in virtualization (move it to 05 as-is). Add daemon hardening + image-prune automation.
  Skills: `linux-container-engine` (Docker/Podman daemon, storage drivers, bridges),
  `linux-container-deployment` (compose ↔ systemd/podman units), `linux-image-hygiene` (prune).
  Grounding: RHCSA8 Podman (DEEP), RHEL9 compose.
- **13-backup-and-archiving** — CONSOLIDATE rsync/tar/snapshot scattered across
  `09.../linux-disaster-recovery` + `06.../linux-disk-storage` into a dedicated category.
  Skills: `linux-rsync-sync` (checksum/dry-run/bwlimit), `linux-archive-integrity`
  (tar.gz/xz + verify + perms/ownership), `linux-filesystem-snapshots` (ZFS/Btrfs send/recv).
  Grounding: RHCSA8 rsync/tar; Fedora Essentials ZFS/Btrfs; `[GROUNDING-GAP]` borg/restic.
- **15-compliance-and-auditing** — auditd + AIDE already strong in
  `07.../linux-intrusion-detection`; MOVE/clone the FIM+auditd content here and ADD the missing
  CIS/automated-scanning skill. Skills: `linux-auditd-rules`, `linux-file-integrity` (AIDE),
  `linux-benchmark-scanning` (CIS via OpenSCAP/`oscap`, Lynis). Grounding: RHEL9 auditd;
  `[GROUNDING-GAP]` CIS PDFs + OpenSCAP/Lynis docs.

**Phase C — greenfield (genuinely new, thin book grounding — flag heavily):**

- **11-databases-and-caching** — new. Skills: `linux-mysql-mariadb` (my.cnf/InnoDB buffer pool,
  connections, mysqldump, binlog/PITR), `linux-postgresql` (postgresql.conf, pg_dump, WAL
  archiving/PITR), `linux-inmemory-stores` (Redis/Memcached eviction + persistence). Seed from
  existing orphans: `scripts/sk-mysql-backup.sh`, `notes/mysql-backup-setup.md`,
  `notes/redis-setup.md`, `commands/redis.md`. Grounding: RHEL9 install/manage; **tuning is a
  `[GROUNDING-GAP]` — needs purchased DB books.**
- **14-performance-and-kernel** — new. Skills: `linux-sysctl-tuning` (TCP buffers/BBR/swappiness —
  consolidate from hardening's sysctl-reference), `linux-kernel-modules` (modprobe/lsmod/blacklist),
  `linux-perf-profiling` (perf/iostat/htop/I/O wait). Grounding: RHCSA8/10 modprobe;
  **perf/BBR are a `[GROUNDING-GAP]` — needs Brendan Gregg books.**

## 4. Quality gates (every skill, enforced before commit)

1. `## Distro support` matrix present (both families) → `scripts/tests/check-distro-matrix.sh` passes.
2. `## Scripts` manifest present; scripts follow `common.sh` contract; `bash -n` clean.
3. `references/` with the cited book/source per claim.
4. Link-resolution check passes (no broken relative links).
5. Hub `linux-sysadmin/SKILL.md` routing table + `CLAUDE.md`/`AGENTS.md` structure + global router
   note updated for new categories 11-15.
6. Commit per phase; push to `main` after verification.

## 5. Execution model (sessions + subagents)

- One subagent per skill (fresh context), given: the skill spec, the mapped book section(s) to
  read, the engine conventions, and the existing sibling skills as style templates. Two-stage
  review (spec-compliance, then quality) per the subagent-driven workflow.
- Sequence: **Phase A** (9 enhancements) → **Phase B** (12, 13, 15 restructure) → **Phase C**
  (11, 14 greenfield). Re-run distro-matrix + link checks after each phase; commit + push.
- Skills whose grounding is a `[GROUNDING-GAP]` will be authored from upstream docs now and
  flagged for a deepening pass once the recommended books are provided.

## 6. Recommended books to purchase (fills the corpus gaps)

**Tier 1 — buy first (broad + highest-leverage gaps):**
- **UNIX and Linux System Administration Handbook, 5th ed.** — Nemeth, Snyder, Hein, Whaley, Mackin. The definitive dual-family bible; covers AIDE, backups, performance, DNS, mail, the lot.
- **The Debian Administrator's Handbook** — Hertzog & Mas (free, debian-handbook.info). Fills the Debian/Ubuntu gap: apt pinning, networking. Pair with an **Ubuntu Server** title for **netplan/systemd-networkd**.

**Tier 2 — category-specific depth (the `[GROUNDING-GAP]` topics):**
- **Systems Performance, 2nd ed.** and **BPF Performance Tools** — Brendan Gregg → Category 14 (perf, iostat, BBR, tracing).
- **High Performance MySQL, 4th ed.** (Schwartz et al.) + **PostgreSQL 16 Administration Cookbook** (Riggs/Ciolli) + **Redis in Action / official Redis docs** → Category 11 tuning.
- **SELinux System Administration, 3rd ed.** — Vermeulen → deepen A7.
- **Container Security** — Liz Rice (+ Podman/Docker upstream docs) → Category 12 hardening.

**Tier 3 — reference/free:**
- **DNS and BIND** — Cricket Liu (Cat 03 DNS depth).
- **CIS Benchmarks** (free PDFs, cisecurity.org) + **OpenSCAP** & **Lynis** docs → Category 15.
- **nftables wiki** (free, wiki.nftables.org) → A1.
- **The Linux Programming Interface** — Kerrisk (deep troubleshooting/syscalls → A5).
- man pages for `rkhunter`, `chkrootkit`, `aide` → A2 and Cat 15.

## 7. Net scope
- 9 existing-skill enhancements (Phase A)
- 5 new categories, ~13 new skills (Phases B greenfield-light + C greenfield)
- 1 structural fix (repo-sync manifest)
- Hub/routing/global-doc updates
