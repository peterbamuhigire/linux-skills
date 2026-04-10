# Log Analysis Patterns

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This reference is a cookbook of awk/grep/sed/jq one-liners for extracting
value from Nginx and Apache access logs, error logs, and JSON-formatted
logs on Ubuntu/Debian servers. Every recipe assumes stock tools only —
no pipeline frameworks, no ELK — and targets the default combined log
format. Copy the pattern, change the column numbers if your format
differs, read the annotation to understand what it does.

## Table of contents

- [Know your log format](#know-your-log-format)
- [Top N IPs by request count](#top-n-ips-by-request-count)
- [Top N URLs by hit count](#top-n-urls-by-hit-count)
- [HTTP status code histogram](#http-status-code-histogram)
- [5xx errors with request context](#5xx-errors-with-request-context)
- [4xx breakdown by status and URL](#4xx-breakdown-by-status-and-url)
- [Response time percentiles ($request_time)](#response-time-percentiles-request_time)
- [Slow request finder (> N seconds)](#slow-request-finder--n-seconds)
- [Scraper / scanner detection (high 404 rate)](#scraper--scanner-detection-high-404-rate)
- [Brute-force detection (POST to login)](#brute-force-detection-post-to-login)
- [Path traversal and secret probing](#path-traversal-and-secret-probing)
- [JSON access logs with jq](#json-access-logs-with-jq)
- [Bandwidth by client IP](#bandwidth-by-client-ip)
- [Requests in a specific time window](#requests-in-a-specific-time-window)
- [Match specific User-Agent families](#match-specific-user-agent-families)
- [Referer analysis](#referer-analysis)
- [Unique visitors per day / per hour](#unique-visitors-per-day--per-hour)
- [Request rate (requests per minute)](#request-rate-requests-per-minute)
- [Detect log gaps (missing minutes)](#detect-log-gaps-missing-minutes)
- [Error log grouping (Nginx error.log)](#error-log-grouping-nginx-errorlog)
- [Cross-log correlation](#cross-log-correlation)
- [Performance note — working with gzip rotations](#performance-note--working-with-gzip-rotations)
- [Sources](#sources)

## Know your log format

The default **Nginx combined** format is:

```
log_format combined '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent"';
```

Field positions when parsed by whitespace:

```
198.51.100.14 - - [22/Mar/2025:14:32:11 +0000] "GET /index.html HTTP/1.1" 200 5123 "https://google.com/" "Mozilla/5.0 (...)"
^$1             ^$4                             ^$6    ^$7  ^$8  ^$9   ^$10                              ^$11...
```

- `$1` — client IP
- `$4` — `[timestamp`
- `$5` — `timezone]`
- `$6` — `"METHOD` (with opening quote)
- `$7` — URI
- `$8` — `HTTP/x.y"` (with closing quote)
- `$9` — status code
- `$10` — body bytes sent
- `$11+` — referer, then user-agent, both quoted

Apache's combined format is byte-identical. If you have added
`$request_time` at the end (strongly recommended), the column count
shifts — verify with `head -1`.

Write-once-use-everywhere custom format with timing data:

```nginx
log_format timed '$remote_addr - $remote_user [$time_local] '
                 '"$request" $status $body_bytes_sent '
                 '"$http_referer" "$http_user_agent" '
                 'rt=$request_time urt="$upstream_response_time"';
```

`$request_time` is the full time the request spent in Nginx (including
client-body read). `$upstream_response_time` is just the time the
upstream (PHP-FPM, Node, etc.) took.

## Top N IPs by request count

```bash
sudo awk '{print $1}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn | head -20
```

Read as:

- `awk '{print $1}'` — pull the first field (client IP).
- `sort` — group identical values next to each other.
- `uniq -c` — count adjacent duplicates.
- `sort -rn` — reverse numeric sort (largest first).
- `head -20` — top 20.

Across rotated gzip files:

```bash
sudo zcat /var/log/nginx/access.log*.gz /var/log/nginx/access.log \
  | awk '{print $1}' | sort | uniq -c | sort -rn | head -20
```

## Top N URLs by hit count

```bash
sudo awk -F'"' '{print $2}' /var/log/nginx/access.log \
  | awk '{print $2}' | sort | uniq -c | sort -rn | head -20
```

- `-F'"'` splits on the double quote, so `$2` is `GET /path HTTP/1.1`.
- The inner `awk '{print $2}'` then picks the URL portion.

To strip query strings (`/search?q=foo` → `/search`):

```bash
sudo awk -F'"' '{print $2}' /var/log/nginx/access.log \
  | awk '{print $2}' | cut -d'?' -f1 \
  | sort | uniq -c | sort -rn | head -20
```

## HTTP status code histogram

```bash
sudo awk '{print $9}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn
```

Typical healthy output:

```
 254312 200
  32451 304
   8211 301
   1923 404
    412 499
     87 500
     12 502
```

`499` is Nginx-specific — "client closed connection" — and should stay
low. A sudden spike in `499` often means the upstream is slow and
impatient clients are disconnecting.

By status code class (2xx / 3xx / 4xx / 5xx):

```bash
sudo awk '{print substr($9,1,1)"xx"}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn
```

## 5xx errors with request context

```bash
sudo awk '$9 ~ /^5/' /var/log/nginx/access.log | tail -30
```

Just the URLs producing 5xx, ranked:

```bash
sudo awk -F'"' '$0 ~ / 5[0-9][0-9] / {print $2}' /var/log/nginx/access.log \
  | awk '{print $2}' | sort | uniq -c | sort -rn | head
```

Pair each 5xx with the matching error.log entry (timestamps should
collide within ~1 second):

```bash
sudo grep ' 5[0-9][0-9] ' /var/log/nginx/access.log | tail -5
sudo tail -20 /var/log/nginx/error.log
```

## 4xx breakdown by status and URL

```bash
sudo awk -F'"' '$0 ~ / 4[0-9][0-9] / {
  # extract URL from field 2 (GET /path HTTP/1.1)
  split($2, a, " ")
  # $9 is an awk positional; re-split whole line by spaces to grab it
  n=split($0, f, " ")
  print f[9], a[2]
}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20
```

Simpler: grep per code.

```bash
for code in 400 401 403 404 429; do
  echo "== $code =="
  sudo awk -v c=$code '$9==c {print}' /var/log/nginx/access.log | wc -l
done
```

## Response time percentiles ($request_time)

Assuming your log format appends `rt=$request_time` (a float), the value
is the last token on the line:

```bash
# Raw values in seconds, sorted ascending:
sudo awk '{for(i=NF;i>=1;i--) if($i ~ /^rt=/){print substr($i,4); break}}' \
  /var/log/nginx/access.log > /tmp/rt.txt

wc -l /tmp/rt.txt

# p50, p90, p95, p99 via awk:
sort -n /tmp/rt.txt | awk '
  { a[NR]=$1 }
  END {
    printf "count=%d\n", NR
    printf "p50=%.3f\n", a[int(NR*0.50)]
    printf "p90=%.3f\n", a[int(NR*0.90)]
    printf "p95=%.3f\n", a[int(NR*0.95)]
    printf "p99=%.3f\n", a[int(NR*0.99)]
    printf "max=%.3f\n", a[NR]
  }'
```

If `$request_time` is in the same fixed column (say `$NF`), shorter:

```bash
sudo awk '{print $NF}' /var/log/nginx/access.log \
  | sed 's/rt=//' | sort -n > /tmp/rt.txt
```

Everything in one pipe, no temp file:

```bash
sudo awk '{for(i=NF;i>=1;i--) if($i ~ /^rt=/){print substr($i,4); break}}' \
  /var/log/nginx/access.log | sort -n | awk '
  { a[NR]=$1 }
  END {
    printf "p50=%.3f  p90=%.3f  p95=%.3f  p99=%.3f  max=%.3f  count=%d\n",
           a[int(NR*0.5)], a[int(NR*0.9)], a[int(NR*0.95)],
           a[int(NR*0.99)], a[NR], NR
  }'
```

## Slow request finder (> N seconds)

```bash
# Requests slower than 2 seconds (with rt= in log format):
sudo awk '{
  for(i=NF;i>=1;i--) if($i ~ /^rt=/){ t=substr($i,4)+0; break }
  if (t > 2) print
}' /var/log/nginx/access.log | tail -20

# Slow requests grouped by URL:
sudo awk '{
  for(i=NF;i>=1;i--) if($i ~ /^rt=/){ t=substr($i,4)+0; break }
  if (t > 2) {
    n=split($0, f, "\"")
    split(f[2], req, " ")
    print req[2]
  }
}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head
```

Without `rt=` in the log format you cannot compute per-request timing
from the access log. Turn on `$request_time` now — it is the single
most useful log field you are not writing today.

## Scraper / scanner detection (high 404 rate)

```bash
# IPs with the most 404s:
sudo awk '$9 == 404 {print $1}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn | head -20
```

404 *ratio* per IP (404s / total, sorted by ratio):

```bash
sudo awk '
  { total[$1]++ }
  $9 == 404 { fourofour[$1]++ }
  END {
    for (ip in total) {
      if (total[ip] > 50 && fourofour[ip] > 0) {
        pct = fourofour[ip] * 100 / total[ip]
        printf "%6.1f%%  %6d/%-6d  %s\n", pct, fourofour[ip], total[ip], ip
      }
    }
  }' /var/log/nginx/access.log | sort -rn | head
```

Output:

```
 96.7%    204/211    198.51.100.4
 91.2%    124/136    203.0.113.88
 12.4%     45/362    192.0.2.14       <- borderline
```

A benign client sits around 1–3 % 404 (favicons, deleted pages). Above
30 % it is either a scanner or a misconfigured client.

## Brute-force detection (POST to login)

```bash
# Count POSTs to login-like URLs per IP:
sudo awk -F'"' '
  $2 ~ /^POST \/(wp-login|login|admin|user\/login|xmlrpc)/ {
    n=split($0, f, " ")
    print f[1]
  }' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head
```

Time-windowed version (last hour only):

```bash
HOUR=$(date +%d/%b/%Y:%H)
sudo awk -F'"' -v h="[$HOUR" '
  $0 ~ h && $2 ~ /^POST \/(wp-login|login|admin|xmlrpc)/ {
    n=split($0, f, " ")
    print f[1]
  }' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head
```

Any IP with > 50 POSTs to a login URL in an hour is an attacker or a
runaway script. Feed the list to fail2ban or UFW:

```bash
sudo ufw insert 1 deny from <ip>
```

## Path traversal and secret probing

```bash
# Common secret/traversal patterns:
sudo grep -E '\.(env|git|htaccess|svn|bak|sql)|\.\./|/wp-admin|/xmlrpc|/phpmyadmin' \
  /var/log/nginx/access.log | tail -30
```

Top attacker IPs for these patterns:

```bash
sudo awk '{print $1, $0}' /var/log/nginx/access.log \
  | grep -E '\.env|\.git/|/phpmyadmin|wp-login|xmlrpc|\.\./|//etc/passwd' \
  | awk '{print $1}' | sort | uniq -c | sort -rn | head
```

Per-path hit count — tells you what attackers are scanning for:

```bash
sudo awk -F'"' '$2 ~ /\.env|\.git|phpmyadmin|wp-login|xmlrpc/ {print $2}' \
  /var/log/nginx/access.log \
  | awk '{print $2}' | cut -d'?' -f1 \
  | sort | uniq -c | sort -rn | head
```

## JSON access logs with jq

If you switch Nginx to JSON logging:

```nginx
log_format json_combined escape=json
  '{'
    '"time":"$time_iso8601",'
    '"remote_addr":"$remote_addr",'
    '"request_method":"$request_method",'
    '"request_uri":"$request_uri",'
    '"status":$status,'
    '"body_bytes_sent":$body_bytes_sent,'
    '"request_time":$request_time,'
    '"upstream_response_time":"$upstream_response_time",'
    '"http_referer":"$http_referer",'
    '"http_user_agent":"$http_user_agent"'
  '}';

access_log /var/log/nginx/access.json.log json_combined;
```

Then everything becomes a one-liner in jq:

```bash
# Top 10 IPs:
sudo jq -r '.remote_addr' /var/log/nginx/access.json.log \
  | sort | uniq -c | sort -rn | head

# Only 5xx, with time and URI:
sudo jq -r 'select(.status>=500) | "\(.time) \(.status) \(.remote_addr) \(.request_uri)"' \
  /var/log/nginx/access.json.log | tail

# p95 request time:
sudo jq -r '.request_time' /var/log/nginx/access.json.log \
  | sort -n | awk '{a[NR]=$1} END{print a[int(NR*0.95)]}'

# Status histogram:
sudo jq -r '.status' /var/log/nginx/access.json.log \
  | sort | uniq -c | sort -rn

# Slow requests over 2s:
sudo jq -r 'select(.request_time>2) | "\(.request_time) \(.status) \(.request_uri)"' \
  /var/log/nginx/access.json.log | sort -rn | head
```

JSON logs are strictly better than text logs for anything beyond casual
tailing. The extra disk cost (~15 %) buys you reliable parsing in jq,
Loki, Elastic, and any language's standard library.

## Bandwidth by client IP

```bash
# Bytes sent, per IP (combined format, $10 = body_bytes_sent):
sudo awk '{bytes[$1]+=$10} END {for (ip in bytes) print bytes[ip], ip}' \
  /var/log/nginx/access.log | sort -rn | head -20

# Human-readable (MB):
sudo awk '{bytes[$1]+=$10} END {
  for (ip in bytes) printf "%8.2f MB  %s\n", bytes[ip]/1048576, ip
}' /var/log/nginx/access.log | sort -rn | head -20
```

An IP that downloaded 40 GB in a day is either a CDN origin-pull or a
crawler. Cross-reference the User-Agent.

## Requests in a specific time window

Nginx's `$time_local` format is `[22/Mar/2025:14:32:11 +0000]`. Grep
against it directly — it is a pure string match, so no date parsing
needed:

```bash
# All requests on a specific day:
sudo grep "22/Mar/2025" /var/log/nginx/access.log | wc -l

# Requests in one hour:
sudo grep "22/Mar/2025:14:" /var/log/nginx/access.log

# Requests in a 10-minute window:
sudo awk '/22\/Mar\/2025:14:3[0-9]:/' /var/log/nginx/access.log

# Between two exact timestamps:
sudo awk '
  /22\/Mar\/2025:14:32:00/,/22\/Mar\/2025:14:35:00/
' /var/log/nginx/access.log
```

The last form is awk's **range pattern**: everything from the first
match to the first match of the second regex. Perfect for incident
post-mortems when you know the exact window.

## Match specific User-Agent families

```bash
# Googlebot traffic:
sudo grep -i "googlebot" /var/log/nginx/access.log | wc -l

# All major search-engine bots:
sudo grep -iE "googlebot|bingbot|yandex|baidu|duckduck" \
  /var/log/nginx/access.log | awk '{print $1}' | sort -u | wc -l

# Count requests by bot family:
sudo awk -F'"' '{print $6}' /var/log/nginx/access.log \
  | grep -oiE "googlebot|bingbot|yandexbot|duckduckbot|facebookexternalhit|twitterbot" \
  | sort | uniq -c | sort -rn

# All non-browser User-Agents (no Mozilla token):
sudo awk -F'"' '$6 !~ /Mozilla/ {print $6}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn | head
```

## Referer analysis

```bash
# Top referers (excluding direct/empty):
sudo awk -F'"' '$4 != "-" {print $4}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn | head -20

# By referer domain only:
sudo awk -F'"' '$4 != "-" {print $4}' /var/log/nginx/access.log \
  | awk -F/ '{print $3}' | sort | uniq -c | sort -rn | head
```

Useful when a new landing page goes viral, or when you want to find
hotlinked images eating bandwidth.

## Unique visitors per day / per hour

```bash
# Unique IPs today:
sudo awk -v d="$(date +%d/%b/%Y)" '$4 ~ d {print $1}' /var/log/nginx/access.log \
  | sort -u | wc -l

# Unique IPs per day across a week:
sudo awk '{split($4, a, ":"); print a[1]}' /var/log/nginx/access.log \
  | sed 's/\[//' > /tmp/days.txt

sudo awk '{
  split($4, a, ":"); day=a[1]; gsub(/\[/, "", day)
  ip=$1
  key=day"|"ip
  if (!(key in seen)) { count[day]++; seen[key]=1 }
}
END { for (d in count) print d, count[d] }' /var/log/nginx/access.log \
  | sort
```

## Request rate (requests per minute)

```bash
sudo awk '{print substr($4, 2, 17)}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn | head -20
# 22/Mar/2025:14:32 → requests per minute
```

Top peak minutes tell you exactly when a spike started. Compare with
server load graphs and you can correlate a load spike to a specific
attacker, spider, or campaign.

Per-second for micro-bursts:

```bash
sudo awk '{print substr($4, 2, 20)}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn | head
```

## Detect log gaps (missing minutes)

Sometimes an incident correlates with "the log has no entries for three
minutes in the middle of the hour" — the worker process was wedged.

```bash
sudo awk '{print substr($4, 2, 17)}' /var/log/nginx/access.log \
  | uniq > /tmp/minutes.txt
wc -l /tmp/minutes.txt

# Verify they are consecutive (awk diff):
awk -F: 'NR==1{prev=$2*60+$3; print; next}
         {cur=$2*60+$3; if (cur-prev > 1) print "GAP", prev, "→", cur, "(", cur-prev-1, "min missing)"
         prev=cur}' /tmp/minutes.txt
```

A gap of more than 1 minute on a production web server means something
was very wrong.

## Error log grouping (Nginx error.log)

The Nginx error.log format is unstructured — timestamps, severity, PID,
connection id, then a freeform message. Still useful to bucket:

```bash
# Severity histogram:
sudo awk '{print $3}' /var/log/nginx/error.log | sort | uniq -c | sort -rn

# Message templates (strip timestamps and numbers):
sudo sed -E 's/^[^:]+: //;
             s/[0-9]+/#/g;
             s/\(#:[^)]*\)//g' /var/log/nginx/error.log \
  | sort | uniq -c | sort -rn | head -20
```

The last pipeline replaces numbers with `#` so that
`connect() failed (111: Connection refused)` and
`connect() failed (13: Permission denied)` group together for easier
counting.

Recent crits:

```bash
sudo grep -iE " \[crit\]| \[alert\]| \[emerg\]" /var/log/nginx/error.log | tail -20
```

## Cross-log correlation

A 500 in the access log should have a matching entry in the Nginx
error.log and in the PHP-FPM or app log at the same second:

```bash
ts="22/Mar/2025:14:32:15"

echo "== access.log =="
sudo grep " $ts " /var/log/nginx/access.log | grep ' 5[0-9][0-9] '

echo "== nginx error.log =="
sudo awk -v t="2025/03/22 14:32" '$0 ~ t' /var/log/nginx/error.log | tail

echo "== php-fpm =="
sudo journalctl -u php8.3-fpm --since "2025-03-22 14:32:00" --until "2025-03-22 14:33:00" --no-pager
```

Note the **format difference**: Nginx access.log uses `22/Mar/2025`,
error.log uses `2025/03/22`, journald uses ISO. Always convert
explicitly.

## Performance note — working with gzip rotations

Rotated logs are gzipped. Never `gunzip -k` and grep the result — use
`zgrep`, `zcat`, `zawk`:

```bash
sudo zgrep " 500 " /var/log/nginx/access.log*.gz | tail
sudo zcat /var/log/nginx/access.log*.gz /var/log/nginx/access.log | awk '{print $1}' | sort -u | wc -l
```

For huge logs `parallel` can help (`apt install parallel`):

```bash
ls /var/log/nginx/access.log*.gz | parallel -j 4 --will-cite 'zcat {} | awk "{print \$1}"' \
  | sort | uniq -c | sort -rn | head
```

Or process in one pass with GNU `awk` over a pipe — `awk` does not care
about file count, only memory:

```bash
sudo zcat /var/log/nginx/access.log.{1..14}.gz /var/log/nginx/access.log \
  | awk '{count[$1]++} END {for(ip in count) print count[ip], ip}' \
  | sort -rn | head
```

## Sources

- Canonical, *Ubuntu Server Guide* (20.04 LTS), logging section.
- Richard Blum and Christine Bresnahan, *Linux Command Line and Shell
  Scripting Bible* (5th ed., Wiley) — awk, sed, and sort pipelines.
- Dave Taylor and Brandon Perry, *Wicked Cool Shell Scripts* (No Starch
  Press) — access-log analysis recipes.
- Nginx `ngx_http_log_module` —
  <https://nginx.org/en/docs/http/ngx_http_log_module.html>.
- jq manual — <https://stedolan.github.io/jq/manual/>.
- GNU awk manual —
  <https://www.gnu.org/software/gawk/manual/gawk.html>.
