# Redis Setup for PHP Applications

Guide for setting up Redis as a session store and application cache for PHP apps on Apache.

## What Was Configured

### 1. Redis Server (`/etc/redis/redis.conf`)

| Setting | Value | Why |
|---------|-------|-----|
| `bind` | `127.0.0.1 -::1` | Localhost only — no external access needed |
| `maxmemory` | `512mb` | Conservative limit; adjust based on actual usage |
| `maxmemory-policy` | `volatile-lru` | Only evicts keys with TTL; preserves persistent data |
| No password | — | Localhost-only binding is sufficient |

### 2. PHP Sessions (`/etc/php/8.4/apache2/php.ini`)

```ini
session.save_handler = redis
session.save_path = "tcp://127.0.0.1:6379?database=0"
```

This replaces file-based sessions (disk I/O) with in-memory Redis. No application code changes required — PHP handles it transparently.

### 3. BIRDC ERP Permission Cache (`/var/www/html/birdcerp/.env`)

```env
PERMISSION_CACHE_TYPE=redis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
PERMISSION_CACHE_DB=1
```

Uses the existing `PermissionCache.php` Redis backend. Falls back to database if Redis is unavailable.

## Redis Database Allocation

| DB | Purpose |
|----|---------|
| 0 | PHP sessions (all apps) |
| 1 | BIRDC ERP permission cache |
| 2-15 | Reserved for future use |

## Verification Steps

```bash
# 1. Redis is running
redis-cli ping
# → PONG

# 2. Check memory config
redis-cli CONFIG GET maxmemory
redis-cli CONFIG GET maxmemory-policy

# 3. Sessions are in Redis (after logging into any app)
redis-cli -n 0 KEYS 'PHPREDIS_SESSION:*'

# 4. Permission cache populated (after logging into BIRDC ERP)
redis-cli -n 1 KEYS '*'

# 5. Memory usage
redis-cli INFO memory

# 6. No Apache errors
sudo tail -20 /var/log/apache2/error.log
```

## Applying to a New Server

When setting up a new server with the same PHP apps:

1. Install packages:
   ```bash
   sudo apt install -y redis-server php8.4-redis
   ```

2. Configure Redis (`/etc/redis/redis.conf`):
   ```bash
   # After the commented maxmemory line, add:
   maxmemory 512mb

   # After the commented maxmemory-policy line, add:
   maxmemory-policy volatile-lru

   # Verify bind is localhost-only (should be default):
   bind 127.0.0.1 -::1
   ```

3. Enable and start:
   ```bash
   sudo systemctl enable redis-server
   sudo systemctl start redis-server
   ```

4. Configure PHP sessions (`/etc/php/8.4/apache2/php.ini`):
   ```ini
   session.save_handler = redis
   session.save_path = "tcp://127.0.0.1:6379?database=0"
   ```

5. Add BIRDC ERP env vars to `.env`:
   ```env
   PERMISSION_CACHE_TYPE=redis
   REDIS_HOST=127.0.0.1
   REDIS_PORT=6379
   PERMISSION_CACHE_DB=1
   ```

6. Restart services:
   ```bash
   sudo systemctl restart redis-server
   sudo systemctl restart apache2
   ```

## How Sessions Work with Redis

- PHP's `session_start()` stores session data in Redis instead of `/var/lib/php/sessions/`
- Each session key is `PHPREDIS_SESSION:<session_id>`
- Apps using different session names (e.g., `BIRDC_ERP_SESSION`, `MADUUKA_SESSID`, `PHPSESSID`) still share DB 0 safely — the session ID is unique per browser/cookie
- Session TTL is controlled by `session.gc_maxlifetime` in php.ini (unchanged)
- If Redis goes down, users need to re-login (sessions are ephemeral)

## Rollback Procedures

### Revert sessions to file-based
Edit `/etc/php/8.4/apache2/php.ini`:
```ini
session.save_handler = files
# Remove or comment out: session.save_path = "tcp://..."
```
Then: `sudo systemctl restart apache2`

### Revert permission cache to database
Edit `/var/www/html/birdcerp/.env`:
```env
PERMISSION_CACHE_TYPE=database
```
Takes effect immediately (no restart needed).

### Full removal
```bash
sudo apt remove redis-server php8.4-redis
sudo systemctl restart apache2
```

## Troubleshooting

| Problem | Check |
|---------|-------|
| Sessions not saving | `php -i \| grep session.save` — verify handler is `redis` |
| "Connection refused" in logs | `systemctl status redis-server` — is it running? |
| High memory usage | `redis-cli INFO memory` — check `used_memory_human` |
| Keys not expiring | `redis-cli TTL <key>` — check if TTL is set |
| Permission cache not working | Check `.env` has `PERMISSION_CACHE_TYPE=redis` |
| Apache won't start after change | Check `/var/log/apache2/error.log` for php-redis errors |
