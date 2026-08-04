# Two-family validation and recovery

Author: Peter Bamuhigire | techguypeter.com | +256 784 464 178

Every specialist skill promises Debian/Ubuntu and RHEL-family support. When a live second family is unavailable, represent it as an explicit unassessed branch, not a pass.

## Matrix

| Check | Debian family | RHEL family | Acceptance |
|---|---|---|---|
| Detection | `detect_distro`, `SK_DISTRO_FAMILY=debian` | `detect_distro`, `SK_DISTRO_FAMILY=rhel` | Correct family and version are recorded |
| Package/service mapping | `pkg_install`, `svc_name`, `web_conf_dir` | Same primitives resolve `dnf`, `systemd`, `httpd`/family names | No hardcoded family-only command in shared path |
| Security context | AppArmor or relevant Debian controls | SELinux context/AVC and firewalld where applicable | Security controls stay enabled |
| No-op/idempotence | Run the same check twice | Run the same check twice | Second run makes no unintended change |
| Failure path | Invalid precondition or unavailable package | Same failure class | Refuses safely and returns useful evidence |
| Rollback/recovery | Restore config/service/data using family path | Restore using family/filesystem path | Known-good state verified |

## Recovery evidence

If a branch cannot be executed, record the missing host/tool/fixture, the exact checks attempted, and the narrowest claim supported. Do not infer RHEL success from Debian output. For restore work, qualify the backup, test the smallest isolated restore, preserve the current target, and validate application/service/access outcomes after recovery.

