# SELinux reference (RHEL family)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

SELinux is the mandatory access control (MAC) system enforced **by default** on
the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). It is the
RHEL-family counterpart to **AppArmor** on Debian/Ubuntu — but the model is
fundamentally different and it is the single biggest behavioral difference an
admin coming from Ubuntu will hit. On Debian/Ubuntu use AppArmor instead
(`aa-status`, `/etc/apparmor.d/`, `aa-enforce`/`aa-complain`/`aa-logprof`); the
hardening checklist covers the AppArmor side.

This reference is shared by `linux-server-hardening`, `linux-security-analysis`,
and `linux-intrusion-detection`.

> **Golden rule: never `setenforce 0` (or `SELINUX=disabled`) to "fix" a
> problem.** Disabling SELinux hides the issue and removes a security layer.
> Diagnose the denial and add the correct **context**, **boolean**, or **port
> label** instead. If you must relax while debugging, use **permissive** (it
> still logs) or make *one domain* permissive — never the whole system.

---

## AppArmor vs SELinux at a glance

| Aspect | AppArmor (Debian/Ubuntu) | SELinux (RHEL family) |
|---|---|---|
| Model | Path-based profiles | Label/type enforcement (every file, port, process has a context) |
| Default state | Installed, per-profile | **Enforcing, system-wide** |
| Profiles/policy | `/etc/apparmor.d/` | policy modules + file contexts + booleans |
| Status | `aa-status` | `getenforce`, `sestatus -v` |
| Modes | enforce / complain per profile | Enforcing / Permissive / Disabled (global) |
| Complain/permissive | `aa-complain <profile>` | `setenforce 0` (global) or `semanage permissive -a <domain>` (per-domain) |
| "Why denied?" | `dmesg` / `journalctl -k \| grep apparmor` | `ausearch -m AVC`, `sealert`, `audit2why` |
| Fix a path | edit profile | set the right **type context** (`semanage fcontext` + `restorecon`) |
| Fix a feature toggle | n/a | **boolean** (`setsebool -P`) |
| Promote learned rules | `aa-logprof` | `audit2allow -M` + `semodule -i` |

---

## 1. Modes and status

Three modes: **Enforcing** (blocks + logs), **Permissive** (logs only — nothing
blocked, ideal for collecting denials), **Disabled** (no labeling at all).

```bash
getenforce                    # one word: Enforcing | Permissive | Disabled
sestatus                      # status summary
sestatus -v                   # + loaded policy version and context of key files
id -Z                         # your own security context (e.g. unconfined_u:...)
```

### Temporary mode change (until reboot — debugging only)

```bash
sudo setenforce 0             # -> Permissive
sudo setenforce 1             # -> Enforcing
```

### Persistent mode

The boot-time default lives in **`/etc/selinux/config`** (the path
`/etc/sysconfig/selinux` is a symlink to it on RHEL). Edit `SELINUX=`:

```ini
# /etc/selinux/config
SELINUX=enforcing        # enforcing | permissive | disabled
SELINUXTYPE=targeted     # targeted policy is the default and what you want
```

- Prefer `permissive` over `disabled` if you must relax — permissive still
  labels files and logs AVCs, so you can build policy and switch back cleanly.
- Going to **`disabled`** stops labeling entirely; re-enabling later forces a
  **full filesystem relabel** (`touch /.autorelabel && reboot`, which can take a
  long time on large filesystems). Avoid it.

---

## 2. Contexts (labels) — the core concept

Every file, process, and port carries a **security context** of the form
`user:role:type:level`. For service troubleshooting you almost always care only
about the **type** (the third field, ending in `_t`). A confined service may
only touch objects whose type its policy allows.

```bash
ls -Z /var/www/html          # file contexts (e.g. system_u:object_r:httpd_sys_content_t:s0)
ls -dZ /var/www/html         # context of the directory itself
ps -eZ | grep httpd          # process (domain) contexts, e.g. ...:httpd_t:s0
ss -ltnpZ                     # listening sockets with their process context
```

A denial is fundamentally a **domain** (process type, e.g. `httpd_t`) being
refused access to a **target type** (file/port type, e.g. `default_t`).

### 2.1 Fixing a file context

The classic failure: serving content from a non-default path. Apache content
must be `httpd_sys_content_t`; writable dirs (uploads, cache) need
`httpd_sys_rw_content_t`.

```bash
# Add a PERSISTENT context rule for a custom docroot, then apply it to disk:
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/web(/.*)?"
sudo restorecon -Rv /srv/web

# Reset a path to its policy-defined context (fixes "it broke after mv/cp"):
sudo restorecon -Rv /var/www/html
```

- `semanage fcontext -a -t <type> "<path>(/.*)?"` writes the rule to the
  **policy** (survives a relabel). `restorecon` then applies the policy to the
  **filesystem**. You almost always need **both**.
- `-a` = add a new rule, `-m` = modify an existing one, `-d` = delete the local
  rule. List local rules with `semanage fcontext -l -C`.
- `cp` inherits the destination's context (good); `mv` **preserves the source**
  context (bad — a file moved into a docroot keeps its old label until
  `restorecon`). Most "it worked until I moved it" bugs are this.

> **Avoid `chcon`.** `chcon -t httpd_sys_content_t /srv/web` writes a label
> directly to the filesystem but **not to the policy**, so it is silently
> reverted by the next `restorecon -R` or any filesystem relabel. Use
> `semanage fcontext` + `restorecon` for anything permanent; treat `chcon` as a
> throwaway test only.

### 2.2 Booleans (feature toggles)

Booleans flip optional permissions on/off across many rules without writing
policy. This is how you grant common service capabilities.

```bash
getsebool -a                              # all booleans
getsebool -a | grep httpd                 # just httpd booleans
semanage boolean -l | grep httpd          # current + DEFAULT value + description
setsebool httpd_can_network_connect on    # runtime only (lost on reboot)
sudo setsebool -P httpd_can_network_connect on   # -P = persistent (recompiles policy)
```

`-P` is the one to remember — without it the change is lost on reboot. The
persistent form takes a little longer because part of the policy is recompiled.

Common high-value booleans:

| Boolean | Allows |
|---|---|
| `httpd_can_network_connect` | Apache/PHP/Nginx to make **any** outbound TCP (APIs, remote services) |
| `httpd_can_network_connect_db` | web → database over the network specifically |
| `httpd_can_sendmail` | web app to send mail |
| `httpd_unified` / `httpd_enable_homedirs` | broaden httpd file access (use sparingly) |
| `ftpd_anon_write` | anonymous FTP uploads |
| `nis_enabled`, `samba_enable_home_dirs` | NIS / Samba home-dir access |

### 2.3 Port labels

Binding a service to a **non-standard port** requires the port to be labeled for
that service's type, or SELinux blocks the `bind()`.

```bash
sudo semanage port -l | grep http_port_t        # ports Apache may bind
sudo semanage port -l | grep ssh_port_t          # ports sshd may bind

# Port NOT yet labeled -> add (-a):
sudo semanage port -a -t http_port_t -p tcp 8088
# Port already labeled for another service -> modify (-m), e.g. SSH on 443:
sudo semanage port -m -t ssh_port_t -p tcp 443
# Custom SSH port (the canonical RHCSA example):
sudo semanage port -a -t ssh_port_t -p tcp 2022
```

Rule of thumb: check with `-l` first; if the port has **no** label use `-a`, if
it is **already** assigned use `-m`.

---

## 3. Diagnosing a denial (the workflow)

A denied action is logged as an **AVC** (Access Vector Cache) record in
`/var/log/audit/audit.log`. A raw record looks like:

```
type=AVC msg=audit(...): avc:  denied  { map } for  pid=33214 comm="httpd"
  path="/web/index.html" scontext=system_u:system_r:httpd_t:s0
  tcontext=unconfined_u:object_r:default_t:s0 tclass=file permissive=0
```

Read it as: domain **`scontext`** (`httpd_t`) was denied `{ map }` on a target
of type **`tcontext`** (`default_t`). The fix is to give the target the type
the domain expects (here, `httpd_sys_content_t` via `semanage fcontext` +
`restorecon`).

```bash
# 1. Reproduce the failure, then read recent AVC denials:
sudo ausearch -m AVC,USER_AVC -ts recent          # last ~10 min
sudo ausearch -m AVC -ts today                     # since midnight
sudo ausearch -c httpd --raw                        # by command name

# 2. Get plain-English advice (needs setroubleshoot-server):
#    Each new denial also drops a "run sealert -l <UUID>" line in
#    /var/log/messages (or `journalctl`).
sudo dnf install -y setroubleshoot-server
sudo sealert -a /var/log/audit/audit.log
sudo sealert -l <UUID>                              # explain one specific denial

# 3. Ask WHY / get a human-readable rationale:
sudo ausearch -m AVC -ts recent | audit2why
sudo ausearch -m AVC -ts recent | audit2allow -w
```

### 3.1 Preferred fix order

1. **Wrong file label?** → `semanage fcontext -a -t <type> "<path>(/.*)?"` then
   `restorecon -Rv <path>`. (sealert's high-confidence plugin usually says
   exactly which type.)
2. **A capability that's just toggled off?** → the right **boolean**
   (`setsebool -P`).
3. **Non-standard port?** → `semanage port -a/-m`.

### 3.2 Last resort: a local policy module

When there is genuinely no boolean/context fix (a custom daemon doing something
the base policy never anticipated), generate a local module from the denials.
**Always review the generated `.te` first — never blind-allow.**

```bash
# Build a module from matching denials, review the rules, then install it:
sudo ausearch -m AVC -ts recent | audit2allow -M my_local_pol
#   (or, by command:)  sudo ausearch -c 'httpd' --raw | audit2allow -M my-httpd
cat my_local_pol.te                 # REVIEW: is every 'allow' line acceptable?
sudo semodule -i my_local_pol.pp    # install the compiled module
sudo semodule -l | grep my_local    # confirm it loaded
sudo semodule -r my_local_pol       # remove it if it was a mistake
```

> A `permissive=1` AVC means SELinux only *logged* the denial (system or domain
> is permissive). Collect those, build the right fix, then return to enforcing.

### 3.3 Per-domain permissive (instead of disabling everything)

If a whole service is misbehaving and you must keep moving, make **just that
domain** permissive — the rest of the system stays enforcing:

```bash
sudo semanage permissive -a httpd_t       # only httpd runs unconfined
sudo semanage permissive -l               # list permissive domains
sudo semanage permissive -d httpd_t       # undo when you've built the real fix
```

The fast-path helper **`sk-selinux-denials`** wraps steps 1–3: it summarizes
recent AVCs, runs `audit2why`, and — only after you confirm — builds and
installs a reviewed local policy module. See the **Scripts** manifest in
[`../SKILL.md`](../SKILL.md).

---

## 4. Common service scenarios

| Scenario | Symptom | Fix |
|---|---|---|
| Custom docroot (`/srv/web`) | 403 / "file not found", AVC `httpd_t` → `default_t` | `semanage fcontext -a -t httpd_sys_content_t "/srv/web(/.*)?"; restorecon -Rv /srv/web` |
| Upload/cache dir not writable | PHP can't write, AVC `write`/`create` | label it `httpd_sys_rw_content_t`, then `restorecon` |
| PHP → external API/DB connection refused | curl/DB connect fails only under enforcing | `setsebool -P httpd_can_network_connect on` (or `_db` for DB only) |
| Web app sending mail | mail send blocked | `setsebool -P httpd_can_sendmail on` |
| Apache/Nginx on `:8088` | service won't bind, AVC `name_bind` | `semanage port -a -t http_port_t -p tcp 8088` |
| SSH moved to `:2022` | sshd won't start on new port | `semanage port -a -t ssh_port_t -p tcp 2022` |
| File moved into docroot with `mv` | suddenly 403 after a deploy | `restorecon -Rv /var/www/html` (mv kept the old label) |
| Started server with SELinux disabled, then re-enabled | spontaneous slow boot | filesystem auto-relabel triggered — expected, let it finish |

| Service | Common SELinux need |
|---|---|
| **Apache/httpd** | `httpd_sys_content_t` docroot; `httpd_sys_rw_content_t` writable dirs; `httpd_can_network_connect[_db]`; custom ports `http_port_t` |
| **Nginx** | uses the same `httpd_*` types and booleans |
| **BIND/named** | zone files `named_zone_t`; `restorecon -Rv /var/named` |
| **Postfix/Dovecot** | non-default spool/maildir paths need correct contexts; some integrations need booleans |
| **Samba** | shares need `samba_share_t`; `samba_enable_home_dirs` boolean for home dirs |
| **node_exporter / custom daemon** | label its port (`semanage port`); may need a small reviewed policy module |

---

## 5. Audit & monitoring tie-in (intrusion detection)

SELinux AVC denials are a **security signal**, not just a nuisance — a service
suddenly tripping denials can indicate compromise or misconfiguration. The
`auditd` daemon (present on both families) records them.

```bash
sudo systemctl status auditd
sudo ausearch -m AVC -ts today | audit2why          # triage today's denials
sudo aureport --avc                                  # AVC summary report
sudo sealert -a /var/log/audit/audit.log             # setroubleshoot analysis
# setroubleshoot-server adds desktop/email alerts on new denials
```

`auditd` and `aide` work on both families; on Debian/Ubuntu the equivalent MAC
denials come from AppArmor (`journalctl -k | grep apparmor`, `dmesg | grep DENIED`).

---

## 6. Hardening checklist additions (RHEL family)

- SELinux is **Enforcing** (`getenforce`) — never shipped disabled.
- Targeted policy loaded (`sestatus` → policy `targeted`).
- `SELINUX=enforcing` set persistently in `/etc/selinux/config`.
- No stray `permissive` domains left from debugging (`semanage permissive -l`).
- No labels applied with `chcon` that a relabel will silently revert — custom
  service paths/ports carry correct contexts/labels via `semanage` (never
  `setenforce 0` as a "fix").
- Any local policy modules are reviewed and minimal (`semodule -l`).
- `auditd` enabled and AVC denials reviewed (`ausearch -m AVC`, `aureport --avc`).

---

## References

- Man pages: `selinux(8)`, `semanage(8)`, `semanage-fcontext(8)`,
  `semanage-port(8)`, `setsebool(8)`, `getsebool(8)`, `restorecon(8)`,
  `chcon(1)`, `audit2allow(1)`, `audit2why(8)`, `ausearch(8)`, `sealert(8)`,
  `semodule(8)`.
- Fedora docs: "SELinux User's and Administrator's Guide".
- Sander van Vugt, *RHCSA 8/10 Cert Guide (EX200)*, ch. "Managing SELinux".
- `linux-server-hardening/references/hardening-checklist.md` — overall checklist
  (AppArmor section for the Debian/Ubuntu counterpart).
- The Debian/Ubuntu counterpart is AppArmor (`aa-status`, `/etc/apparmor.d/`).
