# Redis - In-Memory Data Store

Redis is an in-memory key-value store used for caching, session storage, and message brokering.

## Installation

```bash
sudo apt install -y redis-server php8.4-redis
```

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

# Connect to a specific database (0-15)
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
# List all keys (use cautiously in production)
redis-cli KEYS '*'

# List keys in a specific database
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
redis-cli -n 0 FLUSHDB

# Flush ALL databases (dangerous)
redis-cli FLUSHALL
```

## Monitoring

```bash
# Watch all commands in real-time (Ctrl+C to stop)
redis-cli MONITOR

# Check memory usage of a specific key
redis-cli MEMORY USAGE "key_name"

# Slow log (commands that took too long)
redis-cli SLOWLOG GET 10
```

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
