#!/usr/bin/env bash
#: Title: PostgreSQL "Verify a logical backup" procedure, run on a scratch instance
#: Synopsis: SK_LAB_DISPOSABLE=1 pg_restore_lab.sh <blocks-dir>
#: Description: Expects /root/restore (the backup set from pg_backup_lab.sh, mode 600 files) and
#:              /root/src (its dump-time figures), plus <blocks-dir>/globals.sh and database.sh, the
#:              two documented restore commands. It substitutes the lab file names for the placeholders
#:              appdb and <timestamp> and changes nothing else, then reconciles with the source figures.
#: Author: Peter Bamuhigire <techguypeter.com>
#: Contact: +256784464178
set -u
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab_common.sh
source "$LAB_DIR/lab_common.sh"
BLOCKS=${1:?usage: pg_restore_lab.sh <blocks-dir>}
D=/root/restore
millis() { echo $(( $(date +%s%N) / 1000000 )); }
substitute() { sed -e "s/<timestamp>/$ts/g" -e "s/appdb/$1/g" "$2"; }

. /etc/os-release
lab_info "scratch instance: $PRETTY_NAME; $(sudo -u postgres psql -X -Atc 'select version()' 2>/dev/null | cut -c1-48)"
cd "$D" || exit 1
ts=$(ls globals_*.sql | sed 's/globals_\(.*\)\.sql/\1/')
odd=$(ls lab_odd_db_*_"${ts}".dump)
lab_info "backup set $ts: $(ls | tr '\n' ' ')"

echo; echo "=== step 1: readability, no server needed"
for f in "lab_a_$ts.dump" "$odd"; do check "pg_restore --list $f" pg_restore --list "$f" >/dev/null; done

echo; echo "=== step 2: roles first, then the database (documented commands, placeholders substituted)"
substitute lab_a "$BLOCKS/globals.sh" > /root/globals-cmd.sh
t0=$(millis); bash /root/globals-cmd.sh >/root/globals.out 2>&1; rc=$?; t1=$(millis)
lab_info "globals restore: exit $rc in $((t1 - t0)) ms"
check "globals restore exits 0 despite the expected bootstrap-role error" test $rc -eq 0
check "the documented harmless error appeared (role postgres already exists)" grep -q 'role "postgres" already exists' /root/globals.out
check "app_user exists on the scratch instance" test "$(sudo -u postgres psql -X -Atc "select count(*) from pg_roles where rolname='app_user'" 2>/dev/null)" = 1
substitute lab_a "$BLOCKS/database.sh" > /root/db-cmd.sh
t0=$(millis); bash /root/db-cmd.sh >/root/db.out 2>&1; rc=$?; t1=$(millis)
lab_info "lab_a restore: exit $rc in $((t1 - t0)) ms"
check "lab_a restore exits 0" test $rc -eq 0
sed "s#lab_a_$ts.dump#$odd#" /root/db-cmd.sh > /root/db-odd-cmd.sh
bash /root/db-odd-cmd.sh >/root/db-odd.out 2>&1; rc=$?
check "restore of the awkwardly named database exits 0" test $rc -eq 0

echo; echo "=== step 3: reconcile with the dump-time figures"
# The root shell opens the input and output files on purpose: postgres cannot read /root.
# shellcheck disable=SC2024
sudo -u postgres psql -X -At -F'|' -d lab_a < /root/src/fp.sql > /root/fp-restored.txt 2>/dev/null
# shellcheck disable=SC2024
sudo -u postgres psql -X -At -F'|' -d 'lab odd;db' -c "SELECT 't_rows', count(*) FROM t; SELECT 't_md5', md5(string_agg(x::text, ',' ORDER BY id)) FROM t x;" > /root/fp-odd-restored.txt 2>/dev/null
lab_info "restored figures: $(tr '\n' ' ' < /root/fp-restored.txt)"
check "lab_a: every reconciliation figure equals the dump-time figure" test "$(cat /root/fp-restored.txt)" = "$(cat /root/src/fp-lab_a.txt)"
check "awkwardly named database: row count and content md5 equal" test "$(cat /root/fp-odd-restored.txt)" = "$(cat /root/src/fp-odd.txt)"
check "ANALYZE, then a read-only application query" bash -c "sudo -u postgres psql -X -d lab_a -Atc 'ANALYZE; SELECT count(*) FROM rich' >/dev/null 2>&1"

echo; echo "=== controlled failures of the restore"
bash /root/db-cmd.sh >/root/db-again.out 2>&1; rc=$?
nocheck "a second --create restore into the same instance is refused (exit $rc)" test $rc -eq 0
check "the refusal names the existing database" grep -q 'already exists' /root/db-again.out
head -c 300 "lab_a_$ts.dump" > /root/trunc.dump
sed "s#lab_a_$ts.dump#/root/trunc.dump#" /root/db-cmd.sh > /root/db-trunc-cmd.sh
bash /root/db-trunc-cmd.sh >/root/db-trunc.out 2>&1; rc=$?
nocheck "a truncated dump fails loudly (exit $rc)" test $rc -eq 0
f="lab_a_$ts.dump"
nocheck "pg_restore -j from standard input is refused, as the procedure says" bash -c "sudo -u postgres pg_restore -j 2 --create --dbname=postgres < '$f' >/root/par.out 2>&1"
check "the parallel refusal message is the manual's" grep -q 'parallel restore from standard input is not supported' /root/par.out

lab_finish
