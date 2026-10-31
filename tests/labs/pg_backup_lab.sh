#!/usr/bin/env bash
#: Title: sk-pg-backup lab against a real PostgreSQL (modes, repeat, retention, controlled failures)
#: Synopsis: SK_LAB_DISPOSABLE=1 pg_backup_lab.sh <path-to-sk-pg-backup.sh>
#: Description: Creates synthetic data, runs the script for real, and leaves the newest backup set and
#:              the dump-time reconciliation figures in /root/lab-out for tests/labs/pg_restore_lab.sh.
#:              Needs systemd as PID 1 (to stop and start PostgreSQL), sudo and a running cluster.
#: Author: Peter Bamuhigire <techguypeter.com>
#: Contact: +256784464178
set -u
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab_common.sh
source "$LAB_DIR/lab_common.sh"
SCRIPT=${1:?usage: pg_backup_lab.sh <path-to-sk-pg-backup.sh>}
BK=/srv/pgbk
OUT=/root/lab-out
mkdir -p "$OUT"
plain() { sed 's/\x1b\[[0-9;]*m//g'; }
snap()  { ls -A "$BK" | sort | md5sum | cut -c1-12; }
run_script() { ( set -o pipefail; cd /root && bash "$SCRIPT" --yes --backup-dir "$BK" "$@" 2>&1 | plain ); }
not_a_backup() { # true when some script-named dump cannot be read by pg_restore --list
    local f
    for f in "$BK"/lab*.dump; do [[ -e $f ]] || continue; pg_restore --list "$f" >/dev/null 2>&1 || return 0; done
    return 1
}

. /etc/os-release
lab_info "$PRETTY_NAME; $(sudo -u postgres psql -X -Atc 'select version()' 2>/dev/null | cut -c1-48)"
lab_info "script: $(grep -m1 '^#: Version' "$SCRIPT")"

# ---- synthetic data, created once ------------------------------------------------------------------
psqlp() { sudo -u postgres psql -X -v ON_ERROR_STOP=1 "$@" 2>/dev/null; }
if [[ "$(psqlp -Atc "select count(*) from pg_database where datname='lab_a'" postgres)" == 0 ]]; then
    psqlp postgres >/dev/null <<'SQL'
CREATE ROLE app_user LOGIN PASSWORD 'lab-secret-one';
CREATE ROLE app_ro NOLOGIN;
CREATE DATABASE lab_a OWNER app_user;
CREATE DATABASE "lab odd;db" OWNER app_user;
SQL
    psqlp lab_a >/dev/null <<'SQL'
CREATE EXTENSION pgcrypto;
CREATE TABLE customers(id serial PRIMARY KEY, name text NOT NULL, balance numeric(12,2) NOT NULL);
CREATE TABLE audit(entry text);
CREATE FUNCTION audit_ins() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN INSERT INTO audit VALUES (NEW.name); RETURN NEW; END $$;
CREATE TRIGGER customers_audit AFTER INSERT ON customers FOR EACH ROW EXECUTE FUNCTION audit_ins();
INSERT INTO customers(name,balance) SELECT 'cust-'||g, g*1.5 FROM generate_series(1,5000) g;
CREATE INDEX customers_name_idx ON customers(name);
CREATE VIEW rich AS SELECT * FROM customers WHERE balance > 5000;
GRANT SELECT ON customers TO app_ro;
ALTER TABLE customers OWNER TO app_user;
SQL
    psqlp "lab odd;db" >/dev/null <<'SQL'
CREATE TABLE t(id int primary key, v text);
INSERT INTO t SELECT g, md5(g::text) FROM generate_series(1,300) g;
SQL
fi
cat > "$OUT/fp.sql" <<'SQL'
SELECT 'customers_rows', count(*) FROM customers;
SELECT 'customers_md5', md5(string_agg(c::text, ',' ORDER BY id)) FROM customers c;
SELECT 'audit_rows', count(*) FROM audit;
SELECT 'indexes', count(*) FROM pg_indexes WHERE schemaname='public';
SELECT 'triggers', count(*) FROM pg_trigger WHERE NOT tgisinternal;
SELECT 'views', count(*) FROM pg_views WHERE schemaname='public';
SELECT 'extensions', string_agg(extname, ',' ORDER BY extname) FROM pg_extension;
SELECT 'seq_last', last_value FROM customers_id_seq;
SELECT 'owner', tableowner FROM pg_tables WHERE tablename='customers';
SELECT 'grant_app_ro', has_table_privilege('app_ro','customers','SELECT');
SQL
chmod 644 "$OUT/fp.sql"
# The root shell opens the input and output files on purpose: postgres cannot read /root.
# shellcheck disable=SC2024
sudo -u postgres psql -X -At -F'|' -d lab_a < "$OUT/fp.sql" > "$OUT/fp-lab_a.txt" 2>/dev/null
# shellcheck disable=SC2024
sudo -u postgres psql -X -At -F'|' -d 'lab odd;db' -c "SELECT 't_rows', count(*) FROM t; SELECT 't_md5', md5(string_agg(x::text, ',' ORDER BY id)) FROM t x;" > "$OUT/fp-odd.txt" 2>/dev/null
lab_info "dump-time figures: $(tr '\n' ' ' < "$OUT/fp-lab_a.txt")"

find "$BK" -mindepth 1 -delete 2>/dev/null; rmdir "$BK" 2>/dev/null

echo; echo "=== P1 dry run"
run_script --dry-run >/root/p1.log; rc=$?
check "dry run exits 0" test $rc -eq 0
check "dry run created nothing" test ! -e "$BK"

echo; echo "=== P2 real run, all databases"
run_script >/root/p2.log; rc=$?
tail -n 6 /root/p2.log
check "real run exits 0" test $rc -eq 0
ls -la "$BK"
check "backup directory is mode 700" test "$(stat -c %a "$BK")" = 700
check "every file is mode 600" test -z "$(find "$BK" -maxdepth 1 -type f ! -perm 600)"
check "no staging directory or temp file remains" test -z "$(find "$BK" -maxdepth 1 -name '.pg-backup.*')"
check "one globals file and two dumps" test "$(ls "$BK"/globals_*.sql | wc -l)" -eq 1 -a "$(ls "$BK"/*.dump | wc -l)" -eq 2
check "the postgres maintenance database is not dumped" test -z "$(find "$BK" -maxdepth 1 -name 'postgres_*')"
globals=$(ls "$BK"/globals_*.sql)
check "globals hold the app_user role" grep -q 'CREATE ROLE app_user' "$globals"
check "globals hold a SCRAM hash, which is why mode 600 matters" grep -q 'SCRAM-SHA-256' "$globals"
for d in "$BK"/*.dump; do check "pg_restore --list reads $(basename "$d")" pg_restore --list "$d" >/dev/null; done
check "the awkward database name became a safe file name" bash -c "ls '$BK' | grep -q '^lab_odd_db_[0-9]*_[0-9]\{8\}-[0-9]\{6\}\.dump\$'"
noise=$(grep -c 'could not change directory' /root/p2.log)
check "no 'could not change directory' warning from the client calls (run from /root, as cron does)" test "$noise" -eq 0
mkdir -p "$OUT/set"; find "$OUT/set" -mindepth 1 -delete; cp -p "$BK"/* "$OUT/set/"

echo; echo "=== P3 repeated run and retention"
sleep 1.2; run_script >/root/p3.log; rc=$?
check "second run exits 0" test $rc -eq 0
check "second run adds a second complete set" test "$(ls "$BK"/globals_*.sql | wc -l)" -eq 2 -a "$(ls "$BK"/*.dump | wc -l)" -eq 4
first_ts=$(ls "$BK"/globals_*.sql | head -1 | sed 's/.*globals_\(.*\)\.sql/\1/')
touch -d '10 days ago' "$BK"/*_"${first_ts}".dump "$BK/globals_${first_ts}.sql"
echo precious > "$BK/notes.txt"; echo x > "$BK/manual.dump"; echo x > "$BK/other_20200101-000000.sql"
touch -d '30 days ago' "$BK/notes.txt" "$BK/manual.dump" "$BK/other_20200101-000000.sql"
sleep 1.2; run_script --retention 7 >/root/p3b.log; rc=$?
check "run with --retention 7 exits 0" test $rc -eq 0
check "the expired set is pruned" test -z "$(find "$BK" -maxdepth 1 -name "*${first_ts}*")"
check "the two newer sets are kept" test "$(ls "$BK"/globals_*.sql | wc -l)" -eq 2
check "unrelated old files are untouched" test -f "$BK/notes.txt" -a -f "$BK/manual.dump" -a -f "$BK/other_20200101-000000.sql"
check "every file the script wrote is still mode 600" test -z "$(find "$BK" -maxdepth 1 -type f \( -name 'lab*.dump' -o -name 'globals_*' \) ! -perm 600)"

echo; echo "=== P4 controlled failures"
run_script --db lab_missing >/root/f1.log; rc=$?
check "F1 a missing database: exit 1" test $rc -eq 1
check "F1 no staging left behind" test -z "$(find "$BK" -maxdepth 1 -name '.pg-backup.*')"

systemctl stop postgresql; sleep 2
before=$(snap)
run_script >/root/f2.log; rc=$?
check "F2 PostgreSQL stopped, --all: exit 1" test $rc -eq 1
check "F2 nothing written" test "$before" = "$(snap)"
run_script --db lab_a >/root/f2b.log; rc=$?
check "F2 PostgreSQL stopped, --db: exit 1" test $rc -eq 1
check "F2 nothing written, no staging" test "$before" = "$(snap)"
systemctl start postgresql; sleep 3

( cd /root && bash "$SCRIPT" --yes --backup-dir /etc/hostname/sub >/root/f3.log 2>&1 ); rc=$?
check "F3 an unwritable backup path (its parent is a file): exit 1" test $rc -eq 1

( ulimit -f 4; cd /root && bash "$SCRIPT" --yes --backup-dir "$BK" >/root/f4.log 2>&1 ); rc=$?
check "F4 a write failure (file-size limit standing in for a full disk): exit 1" test $rc -eq 1
check "F4 no staging left behind" test -z "$(find "$BK" -maxdepth 1 -name '.pg-backup.*')"
nocheck "F4 no unreadable dump published under a backup name" not_a_backup

cat > /usr/local/bin/pg_dump <<'WRAP'
#!/bin/sh
/usr/bin/pg_dump "$@" | head -c 200
WRAP
chmod 755 /usr/local/bin/pg_dump
run_script --db lab_a >/root/f5.log; rc=$?
rm -f /usr/local/bin/pg_dump
check "F5 a truncated dump: exit 1" test $rc -eq 1
nocheck "F5 no truncated dump published" not_a_backup

mkdir -p /etc/linux-skills; printf 'RETENTION_DAYS=1\n' > /etc/linux-skills/pg-backup.conf; chmod 666 /etc/linux-skills/pg-backup.conf
run_script >/root/f6.log; rc=$?
rm -f /etc/linux-skills/pg-backup.conf
check "F6 a world-writable configuration file is refused: exit 3" test $rc -eq 3
run_script --retention 0 >/root/f7.log; rc=$?
check "F7 retention 0 is refused: exit 2" test $rc -eq 2

lab_finish
