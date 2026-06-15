# SELinux reference (RHEL family)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

SELinux is the mandatory access control (MAC) system enforced **by default** on
the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). It is the
RHEL-family counterpart to **AppArmor** on Debian/Ubuntu — but the model is
fundamentally different and it is the single biggest behavioral difference an
admin coming from Ubuntu will hit.

This reference is shared by `linux-server-hardening`, `linux-security-analysis`,
and `linux-intrusion-detection`.

> **Golden rule: never `setenforce 0` to "fix" a problem.** Disabling SELinux
> hides the issue and removes a security layer. Diagnose the denial and add the
> correct context, boolean, or policy instead.

---

## AppArmor vs SELinux at a glance

| Aspect | AppArmor (Debian/Ubuntu) | SELinux (RHEL family) |
|---|---|---|
| Model | Path-based profiles | Label/type enforcement (every file, port, process has a context) |
| Default state | Installed, per-profile | **Enforcing, system-wide** |
| Profiles/policy | `/etc/apparmor.d/` | policy modules + file contexts + booleans |
| Status | `aa-status` | `getenforce`, `sestatus` |
| Complain/permissive | `aa-complain <profile>` | `setenforce 0` (global) or per-domain `semanage permissive` |
| "Why denied?" | `dmesg` / `journalctl` | `ausearch -m AVC`, `audit2why` |
| Fix a path | edit profile | set the right **type context** (`semanage fcontext` + `restorecon`) |
| Fix a feature toggle | n/a | **boolean** (`setsebool -P`) |

---

## Modes and status

```bash
getenforce                    # Enforcing | Permissive | Disabled
sestatus                      # full status incl. policy + mount
sudo setenforce 0             # -> Permissive (TEMPORARY, until reboot; debugging only)
sudo setenforce 1             # -> Enforcing

# Persistent mode lives in /etc/selinux/config (SELINUX=enforcing|permissive|disabled)
# Prefer 'permissive' over 'disabled' if you must relax — it still logs AVCs.
```

**Permissive** logs what it *would* have blocked without blocking — the correct
way to collect denials while you build policy. **Disabled** turns off labeling
entirely; re-enabling later forces a full filesystem relabel.

---

## The three things you actually tune

Almost every real-world SELinux fix is one of: **a file context**, **a
boolean**, or **a port label**.

### 1. File contexts (types)

Files are labeled with a type; a service may only access files of types its
policy allows. Serving content from a non-default path is the classic failure.

```bash
ls -Z /var/www/html                      # show contexts
# httpd content must be httpd_sys_content_t; writable dirs httpd_sys_rw_content_t

# Add a persistent context rule for a custom docroot, then apply it:
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/web(/.*)?"
sudo restorecon -Rv /srv/web

# Reset a path to its policy-defined context (fixes "it broke after mv/cp"):
sudo restorecon -Rv /var/www/html
```

`cp` inherits the destination context (good); `mv` preserves the source context
(bad — a file moved into a docroot keeps its old label until `restorecon`).

### 2. Booleans (feature toggles)

Booleans flip optional permissions on/off without writing policy.

```bash
getsebool -a | grep httpd                 # list httpd booleans
# Let Apache/PHP make outbound network connections (DB, API, mail):
sudo setsebool -P httpd_can_network_connect on
# Let Apache connect to a database specifically:
sudo setsebool -P httpd_can_network_connect_db on
# Let Apache send mail:
sudo setsebool -P httpd_can_sendmail on
```

`-P` = persistent. Without it the change is lost on reboot.

### 3. Port labels

Binding a service to a non-standard port needs the port labeled for that
service's type.

```bash
sudo semanage port -l | grep http_port_t        # ports Apache may bind
sudo semanage port -a -t http_port_t -p tcp 8088   # allow httpd on 8088
sudo semanage port -m -t http_port_t -p tcp 8088   # modify if already defined
```

---

## Diagnosing a denial (the workflow)

```bash
# 1. Reproduce, then read the AVC denials
sudo ausearch -m AVC,USER_AVC -ts recent
# (or, if setroubleshoot is installed, plain-English advice:)
sudo sealert -a /var/log/audit/audit.log

# 2. Ask WHY and get suggested fixes
sudo ausearch -m AVC -ts recent | audit2why
sudo ausearch -m AVC -ts recent | audit2allow -w     # human-readable

# 3a. Preferred: apply the right context/boolean/port (above).
# 3b. Last resort: generate a local policy module for a denial with no
#     boolean/context fix. Review the .te first — never blindly allow.
sudo ausearch -m AVC -ts recent | audit2allow -M my_local_pol
sudo semodule -i my_local_pol.pp
```

If a whole service is misbehaving and you must keep moving, make *just that
domain* permissive instead of the whole system:

```bash
sudo semanage permissive -a httpd_t       # only httpd runs unconfined
sudo semanage permissive -d httpd_t       # undo
```

---

## Service-specific quick hits

| Service | Common SELinux need |
|---|---|
| **Apache/httpd** | `httpd_sys_content_t` on docroot; `httpd_sys_rw_content_t` on uploads/cache; `httpd_can_network_connect[_db]` for PHP→DB/API; label custom ports `http_port_t` |
| **Nginx** | uses the same `httpd_*` types and booleans |
| **BIND/named** | zone files `named_zone_t`; `restorecon -Rv /var/named` |
| **Postfix/Dovecot** | non-default spool/maildir paths need correct contexts; some integrations need booleans |
| **SSH on non-standard port** | `semanage port -a -t ssh_port_t -p tcp <port>` |
| **node_exporter / custom daemon** | label its port; may need a small policy module |

---

## Audit & monitoring tie-in (intrusion detection)

SELinux AVC denials are a **security signal**, not just a nuisance — a service
suddenly tripping denials can indicate compromise or misconfiguration. The
`auditd` daemon (present on both families) records them.

```bash
sudo systemctl status auditd
sudo ausearch -m AVC -ts today | audit2why          # triage today's denials
sudo aureport --avc                                  # summary report
# setroubleshoot-server adds desktop/email alerts on new denials
```

`auditd` and `aide` work on both families; on Debian/Ubuntu the equivalent MAC
denials come from AppArmor (`journalctl -k | grep apparmor`).

---

## Hardening checklist additions (RHEL family)

- SELinux is **Enforcing** (`getenforce`) — never shipped disabled.
- Targeted policy loaded (`sestatus` → policy `targeted`).
- No stray `permissive` domains left from debugging (`semanage permissive -l`).
- Custom service paths/ports carry correct contexts/labels (no `setenforce 0`).
- `auditd` enabled and AVC denials reviewed.

---

## References

- Man pages: `selinux(8)`, `semanage(8)`, `setsebool(8)`, `restorecon(8)`,
  `audit2allow(1)`, `ausearch(8)`, `sealert(8)`.
- Fedora docs: "SELinux User's and Administrator's Guide".
- `linux-server-hardening/references/hardening-checklist.md` — overall checklist.
- The Debian/Ubuntu counterpart is AppArmor (`aa-status`, `/etc/apparmor.d/`).
