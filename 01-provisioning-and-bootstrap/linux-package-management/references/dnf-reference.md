# DNF and RPM reference

Parent: [`linux-package-management`](../SKILL.md)

Load this reference for Fedora, RHEL, CentOS Stream, Rocky Linux, AlmaLinux, or Oracle Linux package work.

## Inspect before mutation

```bash
dnf check-update
dnf info nginx
dnf --showduplicates list nginx
dnf repolist
dnf provides /usr/sbin/nginx
rpm -q nginx
rpm -ql nginx
rpm -qf /etc/nginx/nginx.conf
```

`dnf check-update` returns 100 when updates exist and 0 when none exist; do not treat 100 as a command failure. Use `dnf upgrade --assumeno` to inspect a proposed transaction, especially removals and repository source, before approval.

## Transactions and recovery

```bash
sudo dnf install nginx
sudo dnf upgrade
sudo dnf remove nginx
sudo dnf autoremove
sudo dnf reinstall nginx
dnf history
dnf history info <transaction-id>
```

Review `dnf history info` before attempting undo or downgrade. Repository retention and available package versions determine whether rollback is possible; retain configuration backups independently.

## Version locks, reboot checks, and EPEL

```bash
sudo dnf install python3-dnf-plugin-versionlock
sudo dnf versionlock add nginx
sudo dnf versionlock delete nginx
dnf needs-restarting -r
sudo dnf install epel-release
```

Enable EPEL only on RHEL-compatible distributions that need it; Fedora does not. Verify the distribution's supported EPEL release and repository signing identity.

## Repositories

Repository files live under `/etc/yum.repos.d/*.repo`. Verify the publisher, supported release, base URL, and signing key before enabling a third-party source.

## Automatic updates

"dnf-automatic" names two implementations. Find out which one the host has before following a step; the unit names, and so the evidence commands, differ.

| | `dnf-automatic` units as documented for RHEL 10 (Red Hat DNF guide, chapter 6, which does not name the dnf generation; these are the dnf4 names) | dnf5 `automatic` plugin (Fedora 41 and later; observed on Fedora 44, dnf5 5.4.6) |
|---|---|---|
| Package | `dnf-automatic` | `dnf5-plugin-automatic`; it also provides the name `dnf-automatic`, so `dnf install dnf-automatic` works |
| Configuration | `/etc/dnf/automatic.conf` | defaults in `/usr/share/dnf5/dnf5-plugins/automatic.conf`; your overrides in `/etc/dnf/automatic.conf` |
| Timers | `dnf-automatic.timer` (follows the file), plus `dnf-automatic-download.timer`, `dnf-automatic-install.timer`, `dnf-automatic-notifyonly.timer`, which override `apply_updates` and `download_updates` | `dnf5-automatic.timer`; `dnf-automatic.timer` is only an alias to it |
| Services | `dnf-automatic*.service`, one per timer | `dnf5-automatic.service` |
| Shipped state | not stated by the guide; check with `systemctl is-enabled` | timer `disabled` by preset: enable it yourself |

Which one is installed:

```bash
rpm -q dnf5-plugin-automatic dnf-automatic
systemctl list-unit-files 'dnf*automatic*'
```

Set it up (the file is the same on both; `upgrade_type = security` and `reboot` live in `[commands]`):

```bash
sudo dnf install dnf-automatic
sudoedit /etc/dnf/automatic.conf
# dnf4: either a config-driven timer ...
sudo systemctl enable --now dnf-automatic.timer
# ... or the install timer, which applies updates whatever apply_updates says:
#     sudo systemctl enable --now dnf-automatic-install.timer
# dnf5 (Fedora): the same first command works through the alias, or name the real unit:
#     sudo systemctl enable --now dnf5-automatic.timer
systemctl list-timers 'dnf*automatic*'
```

Defaults are `apply_updates = no`, `download_updates = yes`, `upgrade_type = default` and `reboot = never` (dnf5 documentation; the RHEL 10 guide describes the same default behaviour: check, download, report to standard output). Set `upgrade_type = security` and `apply_updates = yes` only after reviewing the maintenance and reboot policy, and decide who reboots: `reboot = never` leaves a patched kernel or library unloaded until someone restarts. `upgrade_type = security` only selects what the repositories mark as security advisories. List them first: `dnf updateinfo list updates security` (Red Hat's command; RHEL needs an attached subscription), or `dnf5 updateinfo list --security` on dnf5. An empty list means the setting will install nothing.

Evidence that it ran. The journal records the real unit name, not an alias, so `journalctl -u dnf-automatic` prints `-- No entries --` on a dnf5 host even when the job ran daily. Match both generations with a pattern:

```bash
journalctl -u 'dnf*automatic*' -n 50
```

Timer enablement is not evidence of a successful transaction. Read that journal, then confirm installed versions (`dnf history`, `rpm -q <package>`) and, for a kernel or core library, whether a restart is still pending (`dnf needs-restarting -r`).

Review-by: 2026-11-30 for the unit names and defaults above. Sources, accessed 2026-10-31: Red Hat, [Automating software updates in RHEL 10](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/managing_software_with_the_dnf_tool/automating-software-updates-in-rhel) and [Managing and monitoring security updates](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/risk_reduction_and_recovery_operations/managing-and-monitoring-security-updates); the [dnf5 automatic command](https://dnf5.readthedocs.io/en/stable/dnf5_plugins/automatic.8.html). The dnf5 column was also observed on a Fedora 44 host (package, aliases, preset and journal behaviour). Not assessed: a RHEL 10 host (which dnf generation its package ships, and that the dnf4 units behave as documented), CentOS Stream, Rocky, Alma and Oracle Linux advisory metadata.
