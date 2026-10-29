# MySQL / MariaDB: install & secure (both families)

MySQL and MariaDB are distinct server products. Verify package, service,
configuration include paths, client tools, authentication defaults, and
hardening command against the selected product and release.

## RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle)

RHEL 9 package streams vary by minor release. RHEL 9.6 documentation lists
MySQL 8.4; check the target's enabled AppStream and lifecycle before installing.
MySQL and MariaDB packages conflict on RHEL 9 — install one, not both. See the
[RHEL 9.6 release notes](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/pdf/9.6_release_notes/distribution).

```bash
# MySQL (confirm the supported stream and package for this RHEL minor release)
sudo dnf install mysql-server
sudo systemctl enable --now mysqld.service

# MariaDB (confirm the supported stream and package for this RHEL minor release)
sudo dnf install mariadb-server mariadb
sudo systemctl enable --now mariadb.service
```

## Debian / Ubuntu

```bash
sudo apt update
sudo apt install mariadb-server         # MariaDB (Debian default)
sudo systemctl enable --now mariadb

# Oracle MySQL: first add Oracle's official APT repository if it supports this
# Debian/Ubuntu release; follow Oracle's current repository instructions.
sudo apt install mysql-server
sudo systemctl enable --now mysql        # NOTE: unit is 'mysql', not 'mysqld'
```

## Secure the install

Use the hardening tool supplied by the selected server package. Verify its
name and supported options before invoking it.

```bash
sudo mysql_secure_installation
```

Do not assume the root authentication plugin or socket behavior. Inspect the
installed server's account configuration and preserve its approved
authentication policy; create a separate least-privilege account for apps.

## Create a least-privilege application user

```sql
CREATE DATABASE appdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'appuser'@'localhost' IDENTIFIED BY 'STRONG_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON appdb.* TO 'appuser'@'localhost';
FLUSH PRIVILEGES;
```

Avoid granting `ALL PRIVILEGES` or `%` (any-host) accounts. Audit grants with
the `linux-webstack` skill's `sk-mysql-user-audit` fast-path if installed.

## Credentials file for non-interactive tools

Backups and cron jobs should never put passwords on the command line. Use a
client config file at mode 600:

```ini
# ~/.my.cnf  (chmod 600)
[client]
user=appuser
password=STRONG_PASSWORD
[mysqldump]
user=appuser
password=STRONG_PASSWORD
```

```bash
chmod 600 ~/.my.cnf
mysql --defaults-file=~/.my.cnf -e "SHOW DATABASES;"
```

## Remote access (only if required)

By default the server binds to localhost. To accept remote connections, set
`bind-address = 0.0.0.0` (or a specific NIC) in a tuning drop-in, restart, open
the firewall (port 3306) via the `linux-firewall-ssl` skill, and grant the app
user from the specific client host — never from `%`.

<!-- Author: Peter Bamuhigire <techguypeter.com> +256784464178 -->
