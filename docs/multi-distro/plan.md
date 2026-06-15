# Multi-Distro Upgrade Plan — Debian/Ubuntu + RHEL family

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178
**Created:** 2026-06-15
**Status:** Phase 0 ✅ complete · Phase 1 ✅ complete · Phase 2 next

## Goal

Make the `linux-skills` engine a **two-family** engine instead of a
one-dimensional Debian/Ubuntu engine. After this upgrade every skill and
every `sk-*` script works on:

- **Debian family:** Debian, Ubuntu (and derivatives — Mint, Pop!_OS, Raspbian)
- **RHEL family:** Fedora, RHEL, CentOS Stream, Rocky Linux, AlmaLinux,
  Oracle Linux (and Amazon Linux, best-effort)

## Does a "Fedora layer" cover all Red Hat–style distros?

**Yes — if the abstraction is built on the *family*, not on Fedora.** The
whole RHEL family shares the parts that matter: `dnf`/`rpm`, `firewalld`,
**SELinux** (enforcing by default), `systemd`, NetworkManager/`nmcli`,
`httpd` with `/etc/httpd/conf.d/` (no `sites-available`), and the `wheel`
sudo group. The divergences inside the family are small and enumerable, and
we handle them as branch points rather than separate ports:

1. **EPEL** — required on RHEL/CentOS/Rocky/Alma for `fail2ban`, `certbot`,
   etc.; **not** needed on Fedora (those packages live in the main repos).
   `ensure_epel` must be a no-op on Fedora and enable EPEL elsewhere.
2. **dnf4 vs dnf5** — Fedora 41+ ships dnf5; RHEL 9 / rebuilds use dnf4. The
   command surface we use is effectively identical; flag-test where it isn't.
3. **subscription-manager / repos** — RHEL proper needs a subscription;
   rebuilds and Fedora do not. We document this; we do not automate it.
4. **Package/version drift** — Fedora is newer and a few package names
   differ. Captured in a family-keyed package-name map.

Design decision: **detect family via `ID` + `ID_LIKE`, validate primarily on
Fedora, treat EPEL + dnf5 as the two real branch points.** This yields one
codebase for the entire Red Hat world plus Debian/Ubuntu.

## Architecture principle: one body, family-aware primitives

No per-distro forks. `SKILL.md` stays the single portable unit (same model
used for the Claude/Codex dual-compatibility work). Distro differences are
pushed down into two layers:

- **`common.sh` primitives** — scripts call `pkg_install nginx`, not
  `apt install nginx`. The library knows the family.
- **Per-skill "Distro matrix" blocks** — a Debian-column / RHEL-column
  command table for the human/agent-facing commands inside each `SKILL.md`.

## The coupling we are removing (grounded scan, 2026-06-15)

| Marker | Files affected | RHEL-family equivalent |
|---|---|---|
| `apt` / `apt-get` | ~60 | `dnf` |
| `apache2` / `sites-available` / `a2en*` | ~38 | `httpd`, `/etc/httpd/conf.d/` |
| `ufw` | ~30 | `firewalld` (`firewall-cmd`) |
| `unattended-upgrades` | ~22 | `dnf-automatic` |
| `netplan` | ~14 | NetworkManager / `nmcli` |
| `snap` | ~12 | `flatpak` / native dnf |
| `apparmor` | ~14 | **SELinux** |
| `sudo` group | ~6 | `wheel` group |

The hard blocker today: `require_debian()` in `scripts/lib/common.sh`
hard-aborts on any non-Debian `ID`, and is called by `sk-audit` and
`sk-mysql-backup`. `require_cmd` hardcodes `apt install` hints.

## Phased execution

### Phase 0 — Foundation (`common.sh`) — *the unblocker*

Additive and non-breaking. Existing Debian-only scripts keep gating to
Debian (correct, because their logic is still Debian-only) until migrated.

- `detect_distro` — sets `SK_DISTRO_ID`, `SK_DISTRO_FAMILY`
  (`debian`|`rhel`|`unknown`), `SK_PKG` (`apt-get`|`dnf`|`yum`). Memoized.
- Package primitives: `pkg_install`, `pkg_remove`, `pkg_update`,
  `pkg_is_installed`, `ensure_epel`.
- Service/firewall/web primitives: `svc_name`, `firewall_allow`,
  `web_conf_dir`, `web_reload`.
- `require_family <debian|rhel|any>` replaces the hard gate.
  `require_debian` becomes a thin backward-compatible alias.
- `require_cmd` install hints become family-aware.
- Tests: mock both families in `common-sh.test.sh`.
- Contract doc updated (`linux-bash-scripting/references/common-sh-contract.md`).

### Phase 1 — Mechanical swaps (portable skills)

Add distro-matrix tables; swap package/service/path names. Skills:
`linux-package-management`, `linux-service-management`,
`linux-log-management`, `linux-disk-storage`, `linux-system-monitoring`,
`linux-secrets`, `linux-config-management`, `linux-observability`,
`linux-dns-server` (`bind`), `linux-mail-server` (Postfix).

### Phase 2 — Real rewrites (the three hard domains)

- **Firewall:** firewalld zones/services model alongside ufw
  (`linux-firewall-ssl`).
- **SELinux:** contexts, booleans, `audit2allow`/`semanage`/`restorecon`
  across `linux-server-hardening`, `linux-security-analysis`,
  `linux-intrusion-detection`. Biggest conceptual addition.
- **Web stack:** `httpd` + `conf.d` model, PHP-FPM path differences, SELinux
  booleans for web (`linux-webstack`, `linux-site-deployment`,
  `linux-troubleshooting`).

### Phase 3 — Provisioning & networking

- `netplan` → NetworkManager/`nmcli` (`linux-network-admin`).
- Kickstart alongside Ubuntu autoinstall; family-aware provisioning steps
  (`linux-server-provisioning`, `linux-cloud-init`).

### Phase 4 — Docs, gates, consistency

- Update `README.md`, `CLAUDE.md`, `AGENTS.md` to declare two-family support.
- Validation script asserting every `SKILL.md` carries a distro matrix.
- Migrate `sk-audit` and `sk-mysql-backup` onto the new primitives so they
  run on both families.

## Testing strategy

- **Now:** mocked `/etc/os-release` for both families in the unit tests;
  `detect_distro`/`require_family`/`svc_name` assertions.
- **Phase 2/3:** real validation on a Fedora LXD/container — SELinux and
  httpd behaviors cannot be unit-tested.

## Naming

The abstraction targets the **RHEL family**, not Fedora specifically.
`SK_DISTRO_FAMILY=rhel` covers Fedora, RHEL, CentOS Stream, Rocky, Alma,
Oracle Linux. Fedora is the primary validation target because it is the
upstream and the strictest (newest SELinux policy, dnf5).
