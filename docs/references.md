# References and sources

Author: Peter Bamuhigire, [techguypeter.com](https://techguypeter.com), +256784464178.

This page holds the full list of sources behind the engine: books, adapted repositories, tool projects, standards and product documentation. It moved out of the [README](../README.md) on 31 October 2026 so the README stays short; the README keeps a summary and a link here. Nothing was removed.

Citations only. No book text is stored in this repository (see [`AGENTS.md`](../AGENTS.md), "Never store book extractions").

## Books

Cited as grounding in skill references:

- Atef, G. (2023) *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite*.
- Blum, R. and Bresnahan, C. *Linux Command Line and Shell Scripting Bible*, 5th edn. Wiley.
- Canonical. *Ubuntu Server Guide Documentation (Linux 20.04 LTS, Focal)*.
- Duguin, S. *Cybersecurity for NGOs: Attack Prevention and Threat Response*.
- Gotangco, J. *Red Hat Enterprise Linux 9 for System Administrators*.
- Gregg, B. *Systems Performance: Enterprise and the Cloud*, 2nd edn; and *BPF Performance Tools*.
- Hitchcock, K. (2022) *Linux System Administration for the 2020s: The Modern Sysadmin Leaving Behind the Culture of Build and Maintain*. Apress.
- Johnson, R. *Fedora Linux Essentials Definitive Reference*.
- Kalsi, T. *Practical Linux Security Cookbook*. Packt.
- Kerrisk, M. *The Linux Programming Interface*.
- Kirch, O. and Dawson, T. (2000) *Linux Network Administrator's Guide*, 2nd edn. O'Reilly.
- Taylor, D. and Perry, B. *Wicked Cool Shell Scripts*. No Starch Press.
- Tevault, D. A. *Mastering Linux Security and Hardening*, 3rd edn. Packt.
- van Vugt, S. *Red Hat RHCSA 8 Cert Guide (EX200)*, 2nd edn.
- Vickler. *Linux Command Lines and Shell Scripting*.
- *Beginner's Guide to the Unix Terminal* (the repository gives no author).
- *Pro Bash* (the repository gives no author).
- *RHEL 9 Recipes*, recipes 37 and 39 (the repository gives no author).

Named in planning documents (`docs/engine-upgrade-july-2026/05-reading-list.md`, `docs/evaluation/2026-04-13/suggested-reading.md`) and "deepen with" notes for further grounding:

- Beyer, B. et al. *Site Reliability Engineering*; and *The Site Reliability Workbook*.
- *Accelerate* (the repository gives the title only).
- Gregg, B. *Linux Performance*.
- Hertzog and Mas. *The Debian Administrator's Handbook*.
- Limoncelli, T. et al. *The Practice of System and Network Administration*.
- Nemeth, E., Snyder, Hein, Whaley and Mackin. *UNIX and Linux System Administration Handbook*, 5th edn.
- Rankin, K. *Linux Hardening in Hostile Networks*.
- Riggs and Ciolli. *PostgreSQL 16 Administration Cookbook*. Packt.
- Schwartz, B. et al. *High Performance MySQL*, 4th edn. O'Reilly.
- Ward, B. *How Linux Works*, 3rd edn.
- *Redis in Action*.
- *Terraform: Up & Running*.

## Repositories

Adapted into the engine:

- Everything Claude Code (ECC): https://github.com/affaan-m/ECC. The three `16-network-equipment` skills were adapted from ECC's `cisco-ios-patterns`, `netmiko-ssh-automation` and `network-config-validation` (imported 2026-09-20). The Pi-hole and VLAN references were adapted from `homelab-pihole-dns` and `homelab-vlan-segmentation`, and the OSI-layer network diagnostic workflow in `linux-troubleshooting` from `agents/network-troubleshooter.md`, and the Freeze Mode rule in `rules/common/core.md` from `skills/safety-guard/SKILL.md`. The installer's Git Bash path fix follows ECC's `install.sh`. `docs/agent-runtime-safety.md` draws on ECC's shortform, longform and security guides.
- addyosmani/agent-skills: https://github.com/addyosmani/agent-skills (MIT, commit `2686b62`). Four tier-1 lint rules in `meta/skill-writing/scripts/quick_validate.py` were paraphrased from `scripts/lib/skill-lint.js` (my-10-kaizen M10-03).
- obra/superpowers: https://github.com/obra/superpowers (MIT, commit `8ca22db`). The narrated-description check (SP-14) in `quick_validate.py` and the canonical `skill-writing` standard with a drift check (SP-04, M10-03/M10-04). The `docs/superpowers/` plans use its planning format.
- DietrichGebert/ponytail: https://github.com/DietrichGebert/ponytail (MIT). This is the thin `CLAUDE.md` → `@AGENTS.md` host-file bridge and single-source drift check (PT-01, PT-02, M10-02, commit `42b3c1b`).
- pbakaus/impeccable: https://github.com/pbakaus/impeccable (Apache-2.0). The `PROJECT.md` (`project_schema: 1`) read rule (IM-11, M10-12, commit `30ac859`) and the "Impeccable-derived AS overlay" quality gate in `AGENTS.md`.
- donvito/codex-astra-luna-orchestrator: https://github.com/donvito/codex-astra-luna-orchestrator. A concept reference for the `.codex/` model-policy helper (inspected at commit `21f4561`; implemented independently).
- chwezi-dev-engine `skill-writing` standard: https://github.com/peterbamuhigire/chwezi-dev-engine/blob/main/skills/sdlc-meta/skill-writing/SKILL.md.

Tool projects documented by the skills:

- age: https://github.com/FiloSottile/age, and age-plugin-yubikey: https://github.com/str4d/age-plugin-yubikey
- Ansible `community.sops`: https://github.com/ansible-collections/community.sops
- audit documentation: https://github.com/linux-audit/audit-documentation
- ComplianceAsCode (SCAP Security Guide): https://github.com/ComplianceAsCode/content
- detect-secrets: https://github.com/Yelp/detect-secrets
- fail2ban wiki: https://github.com/fail2ban/fail2ban/wiki
- FlameGraph: https://github.com/brendangregg/FlameGraph
- git-filter-repo: https://github.com/newren/git-filter-repo
- gitleaks: https://github.com/gitleaks/gitleaks
- LXD configuration: https://github.com/lxc/lxd/blob/master/doc/configuration.md
- Mozilla SSL Configuration Generator: https://github.com/mozilla/ssl-config-generator
- node_exporter: https://github.com/prometheus/node_exporter
- sops: https://github.com/getsops/sops
- testssl.sh: https://github.com/drwetter/testssl.sh
- TruffleHog: https://github.com/trufflesecurity/trufflehog

## Standards and official sources

- IETF RFCs: 1035 (DNS), 1323 (TCP extensions), 1337 (TIME-WAIT hazards), 1918 (private addressing), 1995 (IXFR), 1996 (DNS NOTIFY), 2308 (negative caching), 2317 (classless reverse delegation), 5246 (TLS 1.2), 5280 (X.509 PKI), 6376 (DKIM), 6409 (message submission), 6797 (HSTS), 6962 (Certificate Transparency), 7208 (SPF), 7469 (HPKP, deprecated), 7489 (DMARC), 8314 (implicit TLS for mail), 8375 (`home.arpa`), 8446 (TLS 1.3), 8555 (ACME), 8617 (ARC), 8659 (CAA), 8996 (deprecating TLS 1.0/1.1).
- CIS Benchmarks (Ubuntu/Debian and RHEL), DISA STIG and PCI-DSS profiles as delivered through OpenSCAP and the SCAP Security Guide: https://www.open-scap.org/
- Red Hat Enterprise Linux 9 documentation, including *Deploying web servers and reverse proxies*: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/
- Red Hat Enterprise Linux Security Hardening Guide (reading list).
- NIST incident-response and recovery guidance (named in `docs/evaluation/2026-04-13/suggested-reading.md` without a document number).
- Ubuntu Server documentation: https://ubuntu.com/server/docs
- Linux kernel documentation, `Documentation/admin-guide/sysctl/`, and the Linux man pages cited per skill.
- freedesktop.org systemd manuals (journald, journal-remote, journalctl): https://www.freedesktop.org/software/systemd/man/ ; XDG Base Directory specification: https://specifications.freedesktop.org/basedir/latest/
- Cisco IOS XE hardening guide: https://sec.cloudapps.cisco.com/security/center/resources/IOS_XE_hardening
- Mozilla server-side TLS configuration: https://ssl-config.mozilla.org

Product documentation: Apache HTTP Server 2.4 (https://httpd.apache.org/docs/2.4/), nginx (https://nginx.org/en/docs/), PHP-FPM and OPcache (https://www.php.net/manual/), MySQL 8.0 Reference Manual (https://dev.mysql.com/doc/refman/8.0/), Podman (https://docs.podman.io/), Docker Engine, Compose and pruning (https://docs.docker.com/), cloud-init (https://cloudinit.readthedocs.io/), Certbot (https://eff-certbot.readthedocs.io/), Let's Encrypt documentation and rate limits (https://letsencrypt.org/docs/), Ansible (https://docs.ansible.com/), rclone (https://rclone.org/docs/), Fluent Bit (https://docs.fluentbit.io/), rsyslog (https://www.rsyslog.com/doc/), Postfix (https://www.postfix.org/documentation.html), netfilter (https://www.netfilter.org/documentation/), nftables wiki (https://wiki.nftables.org/), UFW (https://wiki.ubuntu.com/UncomplicatedFirewall), OpenSSL (https://www.openssl.org/docs/), Lynis (https://cisofy.com/lynis/), AIDE (https://aide.github.io/), rkhunter (https://rkhunter.sourceforge.net/), chkrootkit (https://www.chkrootkit.org/), sops (https://getsops.io), age (https://filippo.io/age), pre-commit (https://pre-commit.com), jq (https://stedolan.github.io/jq/manual/), GNU awk (https://www.gnu.org/software/gawk/manual/gawk.html), Debian manpages (https://manpages.debian.org/) and pytest cache (https://docs.pytest.org/en/stable/how-to/cache.html).

## Websites and articles

- "journalctl" article on 0pointer.de: https://0pointer.de/blog/projects/journalctl.html
- LXD 2.0 blog series on stgraber.org: https://stgraber.org/2016/03/11/lxd-2-0-blog-post-series-012/
- Mail-deliverability checkers and sender portals: MXToolbox (https://mxtoolbox.com), mail-tester (https://www.mail-tester.com/), dmarcian DMARC inspector (https://dmarcian.com/dmarc-inspector/), Google Postmaster Tools (https://postmaster.google.com), Microsoft SNDS (https://sendersupport.olc.protection.outlook.com/snds/), Yahoo Sender Hub (https://senders.yahooinc.com/), Spamhaus (https://check.spamhaus.org/)
- TLS test services: Qualys SSL Labs (https://www.ssllabs.com/ssltest/), Mozilla Observatory (https://observatory.mozilla.org/), HSTS preload list (https://hstspreload.org), testssl.sh (https://testssl.sh)
- OpenAI image-generation and image-prompting guides, cited by `docs/ai-prompting/domain-prompt-compilation-contract.md`: https://developers.openai.com/api/docs/guides/image-generation
- Linux Skills repository: https://github.com/peterbamuhigire/linux-skills
