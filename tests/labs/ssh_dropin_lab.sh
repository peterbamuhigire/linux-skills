#!/usr/bin/env bash
#: Title: SSH hardening drop-in lab (precedence, rollback, controlled failure) in a disposable systemd container
#: Synopsis: SK_LAB_DISPOSABLE=1 ssh_dropin_lab.sh <blocks-dir>
#: Description: Runs the documented SSH procedure blocks verbatim beside a cloud-init style
#:              50-cloud-init.conf that enables passwords, then proves the effect with real logins.
#:              <blocks-dir> holds list.sh, apply.sh, reload.sh, rollback.sh and verify.sh, each the
#:              documented fenced block, written by tests/test_distro_labs.py.
#: Author: Peter Bamuhigire <techguypeter.com>
#: Contact: +256784464178
set -u
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/labs/lab_common.sh
source "$LAB_DIR/lab_common.sh"
BLOCKS=${1:?usage: ssh_dropin_lab.sh <blocks-dir>}

PW="Lab-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR)
pw_login()  { sshpass -p "$PW" ssh "${SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no "$1@127.0.0.1" true 2>/dev/null; }
key_login() { ssh "${SSH_OPTS[@]}" -i /root/lab_key -o IdentitiesOnly=yes -o BatchMode=yes "$1@127.0.0.1" true 2>/dev/null; }

. /etc/os-release
lab_info "$PRETTY_NAME; $(sshd -V 2>&1 | head -1)"
if systemctl cat ssh >/dev/null 2>&1; then UNIT=ssh; else UNIT=sshd; fi
lab_info "service unit on this distro: $UNIT"

# A logging systemctl in front of the real one (sudo's secure_path includes /usr/local/bin) so the
# controlled-failure step can prove that no reload was attempted.
cat >/usr/local/bin/systemctl <<'WRAP'
#!/bin/sh
echo "$*" >> /var/log/lab-systemctl.log
exec /usr/bin/systemctl "$@"
WRAP
chmod 755 /usr/local/bin/systemctl
: >/var/log/lab-systemctl.log
reloads() { grep -c '^reload' /var/log/lab-systemctl.log; }

for u in administrator intruder; do
    id "$u" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$u"
    echo "$u:$PW" | chpasswd
done
[[ -f /root/lab_key ]] || ssh-keygen -q -t ed25519 -N '' -f /root/lab_key
for u in administrator intruder root; do
    home=$(getent passwd "$u" | cut -d: -f6)
    install -d -m 700 -o "$u" "$home/.ssh"
    install -m 600 -o "$u" /root/lab_key.pub "$home/.ssh/authorized_keys"
done
printf '# Created by cloud-init (lab imitation)\nPasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/50-cloud-init.conf
chmod 644 /etc/ssh/sshd_config.d/50-cloud-init.conf
systemctl reload "$UNIT"; sleep 1
check "before: password login works, so the lab can see a failure" pw_login administrator
check "before: key login works" key_login administrator

echo; echo "=== A. documented procedure, blocks run verbatim"
bash "$BLOCKS/list.sh"
bash "$BLOCKS/apply.sh"; rc=$?
check "apply block (writes the drop-in, ends with sshd -t) exits 0" test $rc -eq 0
bash "$BLOCKS/reload.sh"; rc=$?
RELOAD_AS_WRITTEN_RC=$rc
if [[ $rc -ne 0 ]]; then
    lab_info "reload block failed as written on this distro (exit $rc); retrying with the unit named sshd"
    sed 's/systemctl reload ssh\b/systemctl reload sshd/' "$BLOCKS/reload.sh" > /root/reload-sshd.sh
    bash /root/reload-sshd.sh; rc=$?
fi
check "reload block exits 0 (after naming the unit sshd where it failed as written)" test $rc -eq 0
lab_info "reload block exit status as written: $RELOAD_AS_WRITTEN_RC"
sleep 1
out=$(bash "$BLOCKS/verify.sh" | grep -v '^#')
for want in "permitrootlogin no" "passwordauthentication no" "pubkeyauthentication yes" "allowusers administrator"; do
    check "sshd -T reports: $want" grep -qx "$want" <<<"$out"
done
nocheck "a real password login is refused" pw_login administrator
check   "a real key login still works for the allowed user" key_login administrator
nocheck "a real key login is refused for a user outside AllowUsers" key_login intruder
nocheck "a real root login is refused (PermitRootLogin no)" key_login root

echo; echo "=== B. rollback block, verbatim"
bash "$BLOCKS/rollback.sh"; rc=$?
ROLLBACK_AS_WRITTEN_RC=$rc
if [[ $rc -ne 0 ]]; then
    lab_info "rollback block failed as written on this distro (exit $rc); applying the same steps with sshd"
    rm -f /etc/ssh/sshd_config.d/00-linux-skills-ssh.conf; systemctl reload sshd
fi
lab_info "rollback block exit status as written: $ROLLBACK_AS_WRITTEN_RC"
sleep 1
check "after rollback the cloud-init default is back: password login works" pw_login administrator

echo; echo "=== C. the old drop-in name loses to cloud-init"
sed 's/00-linux-skills-ssh.conf/99-hardening.conf/g' "$BLOCKS/apply.sh" > /root/apply-old-name.sh
bash /root/apply-old-name.sh >/dev/null 2>&1
systemctl reload "$UNIT"; sleep 1
check "old name: sshd -T still says passwordauthentication yes" test "$(sshd -T | grep -i '^passwordauthentication')" = "passwordauthentication yes"
check "old name: a real password login still succeeds" pw_login administrator
rm -f /etc/ssh/sshd_config.d/99-hardening.conf; systemctl reload "$UNIT"; sleep 1

echo; echo "=== D. controlled failure: a syntax error in the drop-in"
bash "$BLOCKS/apply.sh" >/dev/null 2>&1; systemctl reload "$UNIT"; sleep 1
nocheck "D0: hardened state refuses password login" pw_login administrator
sed 's/^PasswordAuthentication no$/PasswordAuthentication maybe/' "$BLOCKS/apply.sh" > /root/apply-broken.sh
check "D1: the broken apply block really contains the error" grep -q 'PasswordAuthentication maybe' /root/apply-broken.sh
before=$(reloads)
bash /root/apply-broken.sh >/root/d-apply.log 2>&1; rc=$?
tail -n 2 /root/d-apply.log
nocheck "D2: the block's own sshd -t step reports the error (exit $rc)" test $rc -eq 0
chain=0; ( sudo sshd -t && sudo systemctl reload "$UNIT" ) >/dev/null 2>&1 || chain=$?
nocheck "D3: 'sshd -t && systemctl reload' stops before the reload (exit $chain)" test $chain -eq 0
check   "D4: no reload reached systemctl during the failure" test "$(reloads)" -eq "$before"
check   "D5: the running daemon still accepts the allowed key" key_login administrator
nocheck "D6: the running daemon still refuses passwords" pw_login administrator
bash "$BLOCKS/apply.sh" >/dev/null 2>&1; systemctl reload "$UNIT"; sleep 1
nocheck "D7: after the repair, passwords are refused again" pw_login administrator

lab_finish
