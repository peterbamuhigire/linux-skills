# Linux Skills

Linux Skills is an operations library of 48 skills for Linux server administration and network equipment. Its procedures cover provisioning, access, networking, web and mail services, storage, security, observability, troubleshooting, databases, containers, backup, performance, compliance, and Cisco IOS/IOS-XE configuration work. Procedures require a declared target, distribution support, preconditions, bounded changes, recovery or rollback, and verification; the server skills distinguish Debian/Ubuntu from RHEL-family systems.

The engine helps Linux administrators, infrastructure and network engineers, service owners, and support teams produce operational plans, commands, scripts, deployment and recovery procedures, and verification evidence. It is designed for agent-assisted use as well as direct reference: the hub routes to specialist skills, and the operating contract prioritises safe, distro-aware execution and clear failure handling.

## Installation

Install the native Claude Code plugin, or clone the repository and use its installer. The clone installer requires Node.js 18 or newer and supports user or project scope.

```text
/plugin marketplace add https://github.com/peterbamuhigire/linux-skills
/plugin install linux@chwezi-linux

git clone https://github.com/peterbamuhigire/linux-skills
cd linux-skills
./install.sh --scope project      # macOS/Linux/Git Bash
.\install.ps1 -scope project      # Windows PowerShell
```

## Skills

The table reflects the 48 active `SKILL.md` files in the current tree: 16 numbered operations categories, the `linux-sysadmin` hub, and three meta skills.

| Category | Skills | Focus |
|---|---:|---|
| [Provisioning and bootstrap](01-provisioning-and-bootstrap/) | 4 | Server provisioning, cloud-init, packages, and configuration management |
| [Users, access, and secrets](02-users-access-and-secrets/) | 2 | Accounts, privilege controls, secret discovery, and rotation |
| [Networking and DNS](03-networking-and-dns/) | 2 | Host network administration and DNS service operations |
| [Web and mail services](04-web-and-mail-services/) | 3 | Web stacks, site deployment, and mail services |
| [Services and virtualisation](05-services-and-virtualization/) | 2 | Service management and virtualisation |
| [Storage and filesystems](06-storage-and-filesystems/) | 1 | Disk, filesystem, inode, and swap operations |
| [Security and hardening](07-security-and-hardening/) | 5 | Server hardening, firewall and TLS, intrusion detection, security analysis, and cyber resilience |
| [Observability and logging](08-observability-and-logging/) | 3 | Monitoring, logs, and telemetry |
| [Troubleshooting and recovery](09-troubleshooting-and-recovery/) | 2 | Symptom-led diagnosis and disaster recovery |
| [Automation and scripting](10-automation-and-scripting/) | 2 | Repository sync and Bash scripting contracts |
| [Databases and caching](11-databases-and-caching/) | 3 | PostgreSQL, MySQL/MariaDB, and in-memory stores |
| [Containers and orchestration](12-containers-and-orchestration/) | 3 | Container engines, deployment, and image hygiene |
| [Backup and archiving](13-backup-and-archiving/) | 3 | Rsync, archive integrity, and filesystem snapshots |
| [Performance and kernel](14-performance-and-kernel/) | 3 | Performance profiling, kernel modules, and sysctl tuning |
| [Compliance and auditing](15-compliance-and-auditing/) | 3 | Auditd, file integrity, and benchmark scanning |
| [Network equipment](16-network-equipment/) | 3 | Cisco IOS patterns, Netmiko automation, and configuration validation |
| [Administration hub](linux-sysadmin/SKILL.md) | 1 | Routes broad requests to the appropriate specialist skill |
| [Meta skills](meta/) | 3 | Kaizen improvement, skill authoring, and skill safety review |

## References

- [Linux Skills repository](https://github.com/peterbamuhigire/linux-skills) — active skill inventory and source implementation.
- [Repository policy](AGENTS.md), [common rules](rules/common/core.md), [Linux administration hub](linux-sysadmin/SKILL.md), and the numbered category skills — operational boundaries and procedure contracts consulted for this overview.
- [Everything Claude Code (ECC)](https://github.com/affaan-m/ECC) — referenced by this repository’s installer comments and network-equipment skill provenance.
