---
name: linux-firewall-ssl
description: Use when inspecting or changing UFW/firewalld policy, issuing or renewing Certbot certificates, or validating host TLS exposure; use linux-webstack for application-server faults.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Firewall & SSL Management

## Distro support

Two-family skill. **UFW** is the Debian/Ubuntu firewall; the RHEL family
(Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) uses **firewalld** — a
zone-based model, not a flat allow-list. `certbot` works on both; only install
and the renew timer differ. The body below uses UFW/Debian; full RHEL detail is
in [`references/firewalld-reference.md`](references/firewalld-reference.md).

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Firewall | `ufw` | `firewalld` (`firewall-cmd`) |
| Show rules | `ufw status verbose` | `firewall-cmd --list-all` |
| Allow HTTP/HTTPS | `ufw allow 80,443/tcp` | `firewall-cmd --permanent --add-service={http,https}` |
| Allow a raw port | `ufw allow 9100/tcp` | `firewall-cmd --permanent --add-port=9100/tcp` |
| Apply changes | immediate | `firewall-cmd --reload` (permanent vs runtime!) |
| Enable on boot | `ufw enable` | `systemctl enable --now firewalld` |
| Backend (raw netfilter) | nftables (`nft`); `iptables` = `iptables-nft` shim | nftables (`nft`); `iptables` = `iptables-nft` shim |
| nftables persistence | `nftables.service` → `/etc/nftables.conf` | `nftables.service` → `/etc/sysconfig/nftables.conf` |
| iptables persistence | `netfilter-persistent` → `/etc/iptables/rules.v4` | `iptables-save` (legacy retired on RHEL 9+) |
| certbot install | `apt install certbot python3-certbot-nginx` | `dnf install certbot python3-certbot-nginx` (EPEL on RHEL/Rocky/Alma) |
| Renew timer | `certbot.timer` / `snap.certbot.renew.timer` | `certbot-renew.timer` |

Both UFW and firewalld emit **nftables** rules through the kernel's `nf_tables`
subsystem — they are front-ends over the same backend. Drop to raw `nft` /
`iptables` only for rules a front-end can't express (custom NAT, port
forwarding), to read what a front-end produced, or on hosts managed directly.
Full detail in
[`references/nftables-and-iptables.md`](references/nftables-and-iptables.md).

In `sk-*` scripts use the `firewall_allow` helper from `common.sh`, which
targets whichever firewall is active. See
[`references/firewalld-reference.md`](references/firewalld-reference.md) and
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

<!-- dual-compat-start -->

## Use when

- Managing UFW rules on a server.
- Issuing, renewing, or debugging TLS certificates with certbot.
- Verifying HTTPS posture, renewal state, or TLS config for a site.

## Do not use when

- The task is broader web stack tuning or 502 troubleshooting; use `linux-webstack`.
- The task is user access or SSH key management; use `linux-access-control`.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Host, management path, and distro | Operator or inventory | yes | Inspect only; do not select UFW/firewalld by guesswork |
| Required services, sources, ports, and zones | Network/application owner | for firewall change | Do not open a port or range |
| Certificate names and DNS control | Certificate owner and authoritative DNS | for issuance | Do not request or expand a certificate |
| Change window and rollback access | Operations owner | for mutation | Return a proposed rule/certificate plan |

## Capability Contract

Read/search inspection may be read-only. Firewall mutation, package installation, certificate issuance, web-server edits, and reloads require explicit change authority and root access. Preserve an independent management session before default-deny or SSH rule changes.

## Degraded Mode

Without DNS, network, root, Certbot, or a second management session, report verified local state and label public reachability, issuance, renewal, or lockout safety `not assessed`. Never interpret an unavailable probe as success.

## Decision Rules

| Condition | Action | Failure avoided |
|---|---|---|
| Front-end firewall is active | Change rules through that front end | Reload overwriting hand-written nftables rules |
| Remote default-deny change | Preserve SSH and established traffic; test from a second session | Administrator lockout |
| DNS or HTTP-01 path is wrong | Stop issuance and repair prerequisite | Rate-limit consumption and failed renewals |
| Existing certificate covers required names | Renew; expand only for an authorised new SAN | Unnecessary key/certificate churn |

## Workflow

1. Detect distro, active firewall front end, live rules, listening sockets, certificate inventory, and renewal timer.
2. Compare requested exposure with actual application listeners and DNS; stop on an unexplained mismatch.
3. Choose the narrow rule, zone, or certificate action from the decision table and establish rollback access.
4. Syntax-check configuration or dry-run renewal before applying; recover by restoring the saved rules/config on failure.
5. Apply the authorised change and reload only the owning service.
6. Verify local rules, external reachability where available, certificate chain/names/expiry, and renewal dry run.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Exposure and TLS assessment | Service owner | Maps listeners to allowed sources/ports and certificate names |
| Change record | Operations | Includes exact rule/config change and rollback command |
| Verification record | Release owner | Shows active rules, successful TLS/name checks, and renewal status |

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Firewall/TLS evidence pack | Includes before/after rules, listeners, config test, Certbot inventory/dry run, external probe result, and redactions |

## Quality Standards

- Rules expose only named services to approved sources or zones.
- Management access remains independently verified during policy changes.
- Certificate identity, chain, expiry, and automated renewal are checked.
- Failed external checks remain failures or unassessed, never passes.

## Anti-Patterns

- Opening a broad port range for convenience. Fix: map each listener to an approved service.
- Mixing raw nftables rules with an active UFW/firewalld owner. Fix: use one control plane.
- Enabling default-deny over the only SSH session. Fix: preserve and test a second session.
- Reissuing before diagnosing DNS or ACME failure. Fix: validate prerequisites and use a dry run.
- Treating a local HTTPS response as proof of public reachability. Fix: use an external probe or mark it unassessed.
- Storing private keys or credentials in evidence. Fix: record paths, permissions, and fingerprints only.

## Worked Example

A Rocky host must expose HTTPS publicly and SSH only from `198.51.100.0/24`. Confirm `public` is the interface zone, preserve a second SSH session, add `https` and the source-limited SSH rule permanently, reload, then verify both runtime and permanent rules before running `certbot renew --dry-run`.

<!-- dual-compat-end -->

## References

- [`references/ufw-reference.md`](references/ufw-reference.md)
- [`references/firewalld-reference.md`](references/firewalld-reference.md)
- [`references/nftables-and-iptables.md`](references/nftables-and-iptables.md)
- [`references/certbot-reference.md`](references/certbot-reference.md)
- [`references/ssl-config.md`](references/ssl-config.md)

**This skill is self-contained.** Every command below is a standard tool on its
family — `ufw` + `certbot` on Debian/Ubuntu, `firewall-cmd` (firewalld) +
`certbot` on the RHEL family (see
[`references/firewalld-reference.md`](references/firewalld-reference.md)). The
`sk-*` scripts in the **Optional fast path** section are convenience wrappers —
never required.

## UFW Firewall

```bash
sudo ufw status verbose                 # current rules
sudo ufw status numbered                # numbered for easy deletion

# Standard web server rule set:
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw enable

# Add a rule
sudo ufw allow <port>/tcp
sudo ufw allow from <ip> to any port 22   # restrict SSH to trusted IP

# Remove a rule
sudo ufw status numbered
sudo ufw delete <number>

# Rate limiting (brute-force protection)
sudo ufw limit 22/tcp

# Logging
sudo ufw logging on
sudo tail -f /var/log/ufw.log
```

---

## SSL Certificates (Certbot)

```bash
# Issue new cert (nginx plugin — modifies config automatically)
sudo certbot --nginx -d example.com
sudo certbot --nginx -d example.com -d www.example.com

# Check all cert expiry
sudo certbot certificates

# Test auto-renewal
sudo certbot renew --dry-run

# Force renew
sudo certbot renew --force-renewal

# Add domain to existing cert
sudo certbot --nginx --expand -d existing.com -d new.com

# Check renewal timer
sudo systemctl status certbot.timer
```

---

## Troubleshoot Renewal Failure

Every HTTP server block needs this for ACME challenge:
```nginx
location /.well-known/acme-challenge/ { root /var/www/html; }
```

```bash
# Verify all vhosts have it:
sudo grep -r "acme-challenge" /etc/nginx/sites-enabled/

# Test challenge path is reachable:
curl -s http://example.com/.well-known/acme-challenge/test
# Should return 404, not connection refused

# Debug renewal:
sudo certbot renew --dry-run --debug
sudo journalctl -u certbot --no-pager | tail -30
```

Full SSL parameters and cipher config: `references/ssl-config.md`

---

## Raw netfilter (nftables / iptables)

UFW and firewalld are the recommended front-ends; both compile down to
**nftables**. Manage rules through the front-end on a normal host. Drop to raw
`nft`/`iptables` only for what a front-end can't express (custom NAT, port
forwarding), to read what a front-end produced, or on directly-managed hosts.
**Do not mix hand-written rules with an active front-end** — it owns its
tables and overwrites them on reload.

```bash
# View — works regardless of front-end (shows ufw/firewalld output too)
sudo nft list ruleset
sudo nft -a list chain inet filter input    # -a = rule handles (needed to delete)
sudo iptables -S                             # legacy command surface (nft shim)

# A safe default-deny inet/filter ruleset (loopback + established + SSH + web).
# Load atomically; `flush ruleset` makes it idempotent:
sudo nft -c -f /etc/nftables.conf            # -c = syntax check only (dry run)
sudo nft -f /etc/nftables.conf               # apply (replaces live ruleset)

# Delete one rule by handle; flush a chain
sudo nft delete rule inet filter input handle 7
sudo nft flush chain inet filter input

# NAT / masquerade / port forward
sudo nft add rule ip nat postrouting oifname "eth0" masquerade
sudo nft add rule ip nat prerouting tcp dport 80 dnat to 192.0.2.10:8080

# Persist: Debian → /etc/nftables.conf, RHEL → /etc/sysconfig/nftables.conf
sudo sh -c 'nft list ruleset > /etc/nftables.conf' && sudo systemctl enable --now nftables

# IP routing table
ip route show
sudo ip route add 10.20.0.0/16 via 192.0.2.1 dev eth0
```

> Default-deny on a remote host can lock you out: always keep an `accept` rule
> for SSH and for `ct state established,related` **above** the drop, and test
> in a second session before disconnecting.

Full detail — iptables vs nftables, NAT, sets/maps, the front-end backend
relationship, `iptables-save`/`netfilter-persistent`, migration, and
`ip route` persistence — is in
[`references/nftables-and-iptables.md`](references/nftables-and-iptables.md).

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-firewall-ssl` installs:

| Task | Fast-path script |
|---|---|
| List certs, days-to-expiry, renewal timer | `sudo sk-cert-status` |
| Interactive UFW profile picker + apply | `sudo sk-ufw-reset` |
| Diff UFW rules against a baseline | `sudo sk-ufw-audit` |
| Force-renew cert + reload web server | `sudo sk-cert-renew --domain <d>` |
| Show raw netfilter (nft/iptables) + routes | `sudo sk-nft-show` |
| Apply a default-deny nftables ruleset (dry-run) | `sudo sk-nft-apply --profile web-server --dry-run` |

These are optional wrappers. The `ufw` and `certbot` commands above are the
source of truth.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-firewall-ssl
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-cert-status | scripts/sk-cert-status.sh | yes | List all certbot certs, days-to-expiry, domains covered, renewal timer state. |
| sk-ufw-reset | scripts/sk-ufw-reset.sh | no | Interactive UFW wizard: pick profile (web-server / bastion / db / custom), apply, enable. |
| sk-ufw-audit | scripts/sk-ufw-audit.sh | no | Diff active UFW rules against a baseline file; flag drift. |
| sk-cert-renew | scripts/sk-cert-renew.sh | no | Force certbot renewal for one or all domains, reload nginx/apache on success. |
| sk-nft-show | scripts/sk-nft-show.sh | yes | Read-only view of the raw netfilter layer: active front-end, live nftables ruleset, iptables backend mode, persistence state, IP routing table. Both families. |
| sk-nft-apply | scripts/sk-nft-apply.sh | no | Apply a raw nftables ruleset from a built-in profile (web-server/ssh-only) or a .nft file; always syntax-checks, dry-run-capable, asks before replacing the live ruleset; optional persistence. Refuses while ufw/firewalld is active unless --force. |
