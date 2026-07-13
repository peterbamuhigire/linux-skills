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

## Repositories and automatic updates

Repository files live under `/etc/yum.repos.d/*.repo`. Verify the publisher, supported release, base URL, and signing key before enabling a third-party source.

```bash
sudo dnf install dnf-automatic
sudoedit /etc/dnf/automatic.conf
sudo systemctl enable --now dnf-automatic.timer
systemctl list-timers dnf-automatic.timer
journalctl -u dnf-automatic -n 50
```

Set `upgrade_type = security` and `apply_updates = yes` only after reviewing the maintenance and reboot policy. Timer enablement is not evidence of a successful transaction; inspect its journal and installed versions.
