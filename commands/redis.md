---
description: Use as a guarded Redis reference. Confirm the exact host, port, database, version, owner, and recovery plan before commands that read broadly or mutate data.
---

# Redis - In-Memory Data Store

Redis is an in-memory key-value store used for caching, session storage, and message brokering.

> **Safety gate — verify before connecting.** Confirm the exact Redis endpoint, TLS/identity, instance role, package/server version, and database index with the service owner. A `redis-cli -n` index alone does not identify the server or prove the selected database is disposable. Do not paste passwords into command arguments, shell history, chat, or logs; use the approved secret path and keep command output redacted. Route target-specific work through [the Redis/Memcached operations skill](../11-databases-and-caching/linux-inmemory-stores/SKILL.md).
>
> **Destructive commands:** `DEL`, `FLUSHDB`, `FLUSHALL`, and runtime `CONFIG SET` require an approved change for the named target. `FLUSHDB` removes all keys from the selected database; `FLUSHALL` removes keys from every database. These command forms do not expose a dry-run argument in their documented syntax (inference); treat them as immediate destructive operations. Run flush commands only against an approved isolated non-production target with no unintended clients and a tested, recoverable restore copy. If target isolation, owner approval, or restore evidence is missing, stop. ([FLUSHDB](https://redis.io/docs/latest/commands/flushdb/); [FLUSHALL](https://redis.io/docs/latest/commands/flushall/))

## Installation

```bash
sudo apt install -y redis-server php8.4-redis
```

These are Debian/Ubuntu package examples; `php8.4-redis` specifically assumes a PHP 8.4 runtime. Do not copy them to a RHEL-family host or another PHP version. Check the target's distro, enabled repositories, Redis/PHP versions, package names, and service unit in the linked operations skill first.

Verify:
```bash
redis-server --version
php -m | grep redis
```

## Service Management

```bash
# Start / stop / restart
sudo systemctl start redis-server
sudo systemctl stop redis-server
sudo systemctl restart redis-server

# Enable on boot
sudo systemctl enable redis-server

# Check status
sudo systemctl status redis-server
```

## Common CLI Commands

```bash
# Connect to Redis
redis-cli

# Default instances use 16 logical databases (indexes 0-15); confirm this
# target's configured database count and role before choosing an index.
# See https://redis.io/docs/latest/operate/oss_and_stack/management/replication/
redis-cli -n 1

# Test connectivity
redis-cli ping
# → PONG

# Server info (all sections)
redis-cli INFO

# Memory usage
redis-cli INFO memory

# Connected clients
redis-cli INFO clients

# Key statistics per database
redis-cli INFO keyspace
```

## Key Operations

```bash
# Isolated/small test data only: KEYS blocks while it returns every match.
# For a large/shared store, prefer incremental SCAN and account for its iteration semantics.
redis-cli KEYS '*'

# Isolated/small test data only; confirm host and database before listing keys.
redis-cli -n 0 KEYS '*'

# Count keys in current database
redis-cli DBSIZE

# Get a key's value
redis-cli GET "key_name"

# Get a key's TTL (time-to-live in seconds)
redis-cli TTL "key_name"
# → -1 means no expiry, -2 means key doesn't exist

# Get key type
redis-cli TYPE "key_name"

# Delete a key
redis-cli DEL "key_name"

# Flush a specific database
# No preview: only run on the approved isolated target after owner approval and
# a tested restore. Confirm the exact endpoint and selected database first.
redis-cli -n 0 FLUSHDB

# Flush ALL databases (dangerous)
# No preview: only run on the approved isolated target after owner approval and
# a tested restore. Confirm the exact endpoint and all-database scope first.
redis-cli FLUSHALL
```

Redis documents `KEYS` as blocking until all keys are returned and recommends care; on a large database it may harm performance. Prefer `SCAN` for incremental inspection, noting that the keyspace can change during iteration. ([Redis keyspace commands](https://redis.io/docs/latest/develop/using-commands/keyspace/))

## Monitoring

```bash
# Short, approved diagnostic window on the exact instance only; output is sensitive.
# MONITOR streams processed commands and has runtime cost; stop with Ctrl+C.
redis-cli MONITOR

# Check memory usage of a specific key
redis-cli MEMORY USAGE "key_name"

# Slow log (commands that took too long)
redis-cli SLOWLOG GET 10
```

Treat `MONITOR` output as sensitive: Redis documents that it streams commands and shows command arguments in its examples; its note that `AUTH` is redacted does not establish that application data in other commands is safe to disclose (inference). Restrict collection to the approved diagnostic window, store it privately, and delete it under the applicable retention process. ([Redis MONITOR](https://redis.io/docs/latest/commands/monitor/))

## PHP Session Keys

When PHP uses Redis for sessions, keys look like:
```
PHPREDIS_SESSION:abc123def456...
```

Check active sessions:
```bash
redis-cli -n 0 KEYS 'PHPREDIS_SESSION:*' | wc -l
```

## Configuration

Config file: `/etc/redis/redis.conf`

```bash
# View current config values
redis-cli CONFIG GET maxmemory
redis-cli CONFIG GET maxmemory-policy
redis-cli CONFIG GET bind

# Set at runtime (does not persist across restarts)
# Runtime changes still alter the live service; verify the exact target, owner
# approval, prior value, and rollback/config persistence plan first.
redis-cli CONFIG SET maxmemory 512mb
```

Key settings:
| Setting | Recommended | Purpose |
|---------|-------------|---------|
| `bind` | `127.0.0.1 -::1` | Localhost only |
| `maxmemory` | `512mb` | Memory cap |
| `maxmemory-policy` | `volatile-lru` | Evict only keys with TTL set |

## Troubleshooting

- **"Could not connect to Redis"** — check if service is running: `systemctl status redis-server`
- **"OOM command not allowed"** — Redis hit maxmemory limit; check `redis-cli INFO memory`
- **Sessions not storing** — verify `php.ini` has `session.save_handler = redis` and `session.save_path` set
- **Permission denied on socket** — check redis.conf `unixsocketperm` or use TCP connection
