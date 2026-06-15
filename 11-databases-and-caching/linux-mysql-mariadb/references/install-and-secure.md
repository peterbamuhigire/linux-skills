# MySQL / MariaDB: install & secure (both families)

Install/secure steps are grounded in RHEL 9 for SysAdmins Recipes 37 (MySQL),
38 (PostgreSQL — separate skill), and 39 (MariaDB). MySQL and MariaDB are forks
of one codebase; `mysql_secure_installation` and the client tools are shared.

## RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle)

RHEL 9 ships **MySQL 8** and **MariaDB 10.5** in the Application Stream. They
**conflict** — install one, not both.

```bash
# MySQL 8 (Recipe 37)
sudo dnf install mysql-server
sudo systemctl enable --now mysqld.service

# MariaDB 10.5 (Recipe 39)
sudo dnf update
sudo dnf install mariadb-server mariadb
sudo systemctl enable --now mariadb.service
```

## Debian / Ubuntu

```bash
sudo apt update
sudo apt install mariadb-server         # MariaDB (Debian default)
sudo systemctl enable --now mariadb

# — or — Oracle MySQL
sudo apt install mysql-server
sudo systemctl enable --now mysql        # NOTE: unit is 'mysql', not 'mysqld'
```

## Secure the install (both families, Recipe 37/39)

`mysql_secure_installation` walks you through: set/validate the root password,
remove anonymous users, disable remote root login, drop the `test` database,
and reload privileges.

```bash
sudo mysql_secure_installation
```

On modern MariaDB / MySQL the root account uses **socket (unix_socket / auth_socket)
authentication** by default — `sudo mysql` works with no password. Keep socket
auth for root; create a separate password account for apps.

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
