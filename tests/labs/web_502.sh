#!/usr/bin/env bash
#: Title: Disposable Nginx/PHP-FPM 502 diagnosis and rollback fixture
#: Author: Peter Bamuhigire <techguypeter.com>
#: Contact: +256784464178
set -uo pipefail
if [[ "${SK_LAB_DISPOSABLE:-}" != 1 ]] || [[ ! -f /run/.containerenv && ! -f /.dockerenv ]]; then
    printf 'Refusing: requires explicit disposable-container context\n' >&2
    exit 3
fi
for cmd in nginx curl mktemp; do command -v "$cmd" >/dev/null || exit 5; done
fpm="$(command -v php-fpm || true)"
if [[ -z "$fpm" ]]; then
    for candidate in /usr/sbin/php-fpm[0-9]*; do
        [[ -x "$candidate" ]] && fpm="$candidate" && break
    done
fi
[[ -n "$fpm" ]] || exit 5
fixture=$(mktemp -d)
chmod 0755 "$fixture"
fpm_pid=""
cleanup() {
    nginx -c "$fixture/nginx.conf" -s quit >/dev/null 2>&1 || true
    if [[ -n "$fpm_pid" ]]; then kill "$fpm_pid" 2>/dev/null || true; wait "$fpm_pid" 2>/dev/null || true; fi
    rm -rf -- "$fixture"
}
trap cleanup EXIT
printf '<?php echo "fixture-ok";\n' > "$fixture/health.php"
group=$(id -gn nobody)
for port in 19001 19002; do
    cat > "$fixture/fpm-$port.conf" <<EOF
[global]
error_log = $fixture/fpm-$port.log
daemonize = no
[fixture]
user = nobody
group = $group
listen = 127.0.0.1:$port
pm = static
pm.max_children = 1
EOF
done
cat > "$fixture/nginx.conf" <<EOF
user nobody $group;
pid $fixture/nginx.pid;
error_log $fixture/nginx.log;
events {}
http {
  access_log off;
  server {
    listen 127.0.0.1:18080;
    location / {
      include /etc/nginx/fastcgi_params;
      fastcgi_param SCRIPT_FILENAME $fixture/health.php;
      fastcgi_pass 127.0.0.1:19001;
    }
  }
}
EOF
start_fpm() { "$fpm" -y "$fixture/fpm-$1.conf" -F > "$fixture/fpm-start.log" 2>&1 & fpm_pid=$!; }
request() { curl --max-time 2 -s -o "$fixture/body" -w '%{http_code}' http://127.0.0.1:18080/; }
expect() {
    local expected="$1" actual="" i
    for ((i=0; i<40; i++)); do
        actual=$(request || true)
        [[ "$actual" == "$expected" ]] && break
        sleep 0.1
    done
    [[ "$actual" == "$expected" ]] || { printf 'FAIL expected %s got %s\n' "$expected" "$actual"; exit 1; }
    printf 'PASS HTTP %s\n' "$actual"
    if [[ "$expected" == 200 ]]; then [[ "$(cat "$fixture/body")" == fixture-ok ]] || exit 1; fi
}
"$fpm" -v | head -1
nginx -v 2>&1
start_fpm 19001
nginx -t -c "$fixture/nginx.conf" || exit 1
nginx -c "$fixture/nginx.conf" || exit 1
expect 200
cp "$fixture/nginx.conf" "$fixture/nginx.known-good"
kill "$fpm_pid"; wait "$fpm_pid" 2>/dev/null || true
start_fpm 19002
expect 502
printf 'Observed failing hop:\n'
tail -2 "$fixture/nginx.log"
printf 'Configured and new listener:\n'
grep fastcgi_pass "$fixture/nginx.conf"
grep listen "$fixture/fpm-19002.conf"
sed -i 's/127.0.0.1:19001/127.0.0.1:19002/' "$fixture/nginx.conf"
nginx -t -c "$fixture/nginx.conf" || exit 1
nginx -c "$fixture/nginx.conf" -s reload || exit 1
expect 200
# Repeat successful validation without another mutation.
nginx -t -c "$fixture/nginx.conf" || exit 1
expect 200
cp "$fixture/nginx.conf" "$fixture/invalid.conf"
printf '\ninvalid_directive;\n' >> "$fixture/invalid.conf"
if nginx -t -c "$fixture/invalid.conf" >/dev/null 2>&1; then exit 1; fi
printf 'PASS invalid configuration rejected before reload\n'
# Actual rollback: restore original upstream and restart the original pool.
kill "$fpm_pid"; wait "$fpm_pid" 2>/dev/null || true
start_fpm 19001
cp "$fixture/nginx.known-good" "$fixture/nginx.conf"
nginx -t -c "$fixture/nginx.conf" || exit 1
nginx -c "$fixture/nginx.conf" -s reload || exit 1
expect 200
printf 'PASS actual upstream rollback and response-body verification\n'
