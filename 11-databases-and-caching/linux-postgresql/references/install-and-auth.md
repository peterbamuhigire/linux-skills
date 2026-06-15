# PostgreSQL: install, initialize & client authentication (both families)

Install/init/`pg_hba.conf` are grounded in RHEL 9 for SysAdmins Recipe 38;
auth-method details are filled from the official PostgreSQL documentation.

## RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle)

The cluster is **not** auto-created — you must initialize it once after install
(Recipe 38). The default version is the Application Stream default (PostgreSQL 13
on RHEL 9; newer streams are selectable).

```bash
sudo dnf install postgresql-server postgresql-contrib
sudo postgresql-setup --initdb          # creates the cluster under /var/lib/pgsql/data
sudo systemctl enable --now postgresql.service
```

`postgresql-contrib` adds widely used extensions and helpers (`pg_stat_statements`,
`pgcrypto`, `uuid-ossp`, `pg_trgm`, etc.). On RHEL the `postgresql.conf` and
`pg_hba.conf` live **inside the data dir** (`/var/lib/pgsql/data`).

## Debian / Ubuntu

The package **auto-creates** a cluster on install — no separate init step.

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl enable --now postgresql
```

Config lives under `/etc/postgresql/<ver>/main/` and the data dir under
`/var/lib/postgresql/<ver>/main`. Debian wraps clusters in its own tooling:

```bash
pg_lsclusters                            # list clusters (version, port, status)
sudo pg_ctlcluster 16 main restart       # control a specific cluster
```

## The `postgres` role and `psql` basics

PostgreSQL installs an OS user `postgres` and a matching superuser **role**
`postgres`. Locally you connect through **peer** auth, which maps the OS user to
the same-named DB role — so no password is needed for `postgres`:

```bash
sudo -u postgres psql                    # superuser shell
```

```sql
\l                 -- list databases
\du                -- list roles and their attributes
\dn                -- list schemas
\conninfo          -- show current connection
\q                 -- quit
```

Create a least-privilege application role and database (Recipe 38):

```sql
CREATE USER appuser WITH LOGIN PASSWORD 'STRONG_PASSWORD';
CREATE DATABASE appdb OWNER appuser;
GRANT ALL PRIVILEGES ON DATABASE appdb TO appuser;
```

Role attributes worth knowing (grant only what is needed):

| Attribute | Meaning |
|---|---|
| `LOGIN` | role may connect (a "user"); without it the role is a group |
| `SUPERUSER` | bypasses all permission checks — grant sparingly |
| `CREATEDB` | may create databases |
| `CREATEROLE` | may create/alter other (non-superuser) roles |
| `NOLOGIN` | a group role you `GRANT` to other roles |

Change/inspect attributes with `ALTER ROLE appuser WITH CREATEDB;` and
`\du`.

## Client authentication: `pg_hba.conf`

`pg_hba.conf` (Host-Based Authentication) is evaluated **top-down, first match
wins** — order specific rules before broad ones. Each line is:

```conf
# TYPE  DATABASE  USER      ADDRESS          METHOD
local   all       postgres                   peer
local   all       all                        scram-sha-256
host    appdb     appuser   10.0.0.0/24      scram-sha-256
host    all       all       0.0.0.0/0        reject
```

- `local` lines match Unix-socket connections (no ADDRESS column).
- `host` lines match TCP/IP; supply a CIDR ADDRESS. `hostssl`/`hostnossl`
  restrict to TLS / non-TLS.

### Auth methods

| Method | When to use |
|---|---|
| `peer` | local socket only; maps the OS username to the DB role. Ideal for `postgres` admin access. |
| `scram-sha-256` | **Preferred** password method. Salted challenge-response; the password never crosses the wire in a reversible form. Default `password_encryption` on PostgreSQL 14+. |
| `md5` | Legacy password hashing. Weaker than SCRAM; migrate off it. |
| `trust` | **No authentication at all** — anyone who can reach the line is let in as the requested role. Never use on a `host` line reachable from the network; acceptable only for tightly controlled local sockets. |
| `reject` | Explicitly deny. Use a final catch-all `reject` for a default-deny posture. |

### Migrating off `md5` to `scram-sha-256`

```sql
-- 1. Ensure new/changed passwords are stored as SCRAM:
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SELECT pg_reload_conf();
-- 2. Re-set each affected user's password so it is re-hashed under SCRAM:
ALTER USER appuser WITH PASSWORD 'STRONG_PASSWORD';
-- 3. Change the pg_hba.conf method from md5 to scram-sha-256, then reload.
```

Reload after editing `pg_hba.conf` — no restart needed:

```bash
sudo -u postgres psql -c "SELECT pg_reload_conf();"
# or: sudo systemctl reload postgresql
```

Check which rule matched a connection and the effective rules:

```sql
SELECT * FROM pg_hba_file_rules;        -- parsed rules + any errors
SELECT * FROM pg_stat_ssl;              -- which sessions are using TLS
```

## Listening on the network: `listen_addresses`

By default PostgreSQL listens only on `localhost`. Two independent gates control
remote access — **both** must be opened:

1. `listen_addresses` in `postgresql.conf` (which interfaces the server binds).
2. A matching `host` rule in `pg_hba.conf`.

```conf
# postgresql.conf  — requires a RESTART (not just reload)
listen_addresses = 'localhost,10.0.0.5'   # specific NICs; '*' = all (use with care)
port = 5432
```

```bash
sudo systemctl restart postgresql
sudo -u postgres psql -c "SHOW listen_addresses;"
```

Then add the `host ... scram-sha-256` rule for the client subnet and open the
firewall (port 5432) only to trusted hosts. Prefer binding to a specific private
NIC over `'*'`.

## Sources

- RHEL 9 for SysAdmins, Recipe 38 (PostgreSQL install, init, role/DB creation,
  `pg_hba.conf`).
- Official PostgreSQL documentation: "Client Authentication" (`pg_hba.conf`,
  auth methods) and "Server Configuration" (`listen_addresses`,
  `password_encryption`).
