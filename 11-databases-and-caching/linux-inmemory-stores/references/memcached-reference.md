# Memcached: configuration deep dive (both families)

> [GROUNDING-GAP: Redis/Memcached — grounded on official memcached.org docs, the
> memcached(1) man page, and the project wiki (github.com/memcached/memcached/wiki);
> deepen with the Memcached docs. Not present in the corpus; author conservatively.]

Memcached is a **pure cache with no persistence** — every restart starts empty.
It is configured entirely through command-line flags; the distro packages just
pass those flags from a defaults file to the daemon.

## Where flags live

| Family | File | Format |
|---|---|---|
| Debian/Ubuntu | `/etc/memcached.conf` | One flag per line (`-m 256`, `-l 127.0.0.1`) |
| RHEL family | `/etc/sysconfig/memcached` | Shell vars: `PORT=`, `USER=`, `MAXCONN=`, `CACHESIZE=`, `OPTIONS=` |

On RHEL, `CACHESIZE` maps to `-m`, `MAXCONN` to `-c`, `PORT` to `-p`, and extra
flags (e.g. `-l`, `-U 0`, SASL) go in `OPTIONS="..."`. Service unit is
`memcached` on both families. Restart after editing.

## Key flags

| Flag | Meaning | Notes |
|---|---|---|
| `-m <MB>` | Max memory for items | This **is** the ceiling; LRU eviction within slab classes happens automatically when full. No policy knob. |
| `-c <n>` | Max simultaneous connections | Default 1024. Raise for many clients. |
| `-l <addr[,addr]>` | Listen address(es) | Default localhost on the packaged config. Bind to a private IP only — never `0.0.0.0` on an untrusted net. |
| `-p <port>` | TCP port | Default 11211 |
| `-U <port>` | UDP port | **Set `-U 0` to disable UDP** — open UDP 11211 is a DDoS amplification vector. |
| `-t <n>` | Worker threads | Default 4 |
| `-I <size>` | Max item size | Default 1m |
| `-S` | Enable SASL authentication | Requires SASL libs (see below) |
| `-u <user>` | Run-as user | Package sets `memcache` |

Example Debian `/etc/memcached.conf`:
```
-d
-m 256
-c 1024
-p 11211
-U 0
-l 127.0.0.1
-u memcache
```

## Eviction

There is no eviction policy to choose. When the `-m` budget is full, Memcached
evicts the least-recently-used item within the relevant slab class. Watch the
`evictions` stat — sustained growth means `-m` is too small for the working set.

## SASL authentication

Memcached has no built-in password like Redis `requirepass`; authentication is
via SASL when started with `-S` (binary protocol only).

| Family | Packages | DB tool |
|---|---|---|
| Debian/Ubuntu | `libsasl2-modules`, `sasl2-bin` | `saslpasswd2` |
| RHEL family | `cyrus-sasl`, `cyrus-sasl-plain` | `saslpasswd2` |

```bash
# Create a SASL user (the secret should come from linux-secrets):
sudo saslpasswd2 -a memcached -c appuser
# then add -S to OPTIONS / memcached.conf and restart.
```

Use **`linux-secrets`** to manage the SASL password rather than typing it inline.
If the host firewall already restricts 11211 to localhost or a trusted subnet
(`linux-firewall-ssl`), SASL is the second layer, not the only one.

## Stats and visibility

```bash
# Raw protocol over the port:
echo -e 'stats\r' | nc 127.0.0.1 11211 | head -40
echo -e 'stats slabs\r' | nc 127.0.0.1 11211     # per-slab memory/eviction
echo -e 'stats items\r'  | nc 127.0.0.1 11211     # item counts/age per slab

# memcached-tool ships with the package (Debian: in the memcached pkg):
memcached-tool 127.0.0.1:11211 display            # slab usage
memcached-tool 127.0.0.1:11211 stats              # general stats
```

Key stats: `curr_items`, `bytes` (vs `limit_maxbytes` = the `-m` budget),
`evictions`, `get_hits` / `get_misses` (hit ratio), `curr_connections` vs the
`-c` limit, `cmd_get` / `cmd_set`.

## Security warning

Memcached has historically been a major UDP reflection/amplification source.
Disable UDP (`-U 0`), bind to localhost or a private interface (`-l`), firewall
11211, and enable SASL if any off-host client needs access. Never expose an
unauthenticated Memcached to the public internet.
