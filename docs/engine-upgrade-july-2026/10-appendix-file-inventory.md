# Appendix: Full Content Inventory

This inventory was captured before the audit reports were written. It excludes VCS/cache/dependency internals: `.git`, `node_modules`, `.venv`, `venv`, `__pycache__`, and `.pytest_cache`.

## Empty Directories

None.

## Temp/Backup Artefacts

None.

## Duplicate Content Hash Groups (Sample)

None detected.

## Full Tree

```text
./
AGENTS.md (7422 bytes)
CLAUDE.md (9085 bytes)
README.md (17950 bytes)
.claude/
  settings.local.json (332 bytes)
01-provisioning-and-bootstrap/
  01-provisioning-and-bootstrap/linux-cloud-init/
    SKILL.md (14815 bytes)
    01-provisioning-and-bootstrap/linux-cloud-init/references/
      autoinstall-reference.md (21024 bytes)
      debugging.md (14682 bytes)
      kickstart-reference.md (6175 bytes)
      user-data-reference.md (22517 bytes)
  01-provisioning-and-bootstrap/linux-config-management/
    SKILL.md (15193 bytes)
    01-provisioning-and-bootstrap/linux-config-management/references/
      ansible-patterns.md (24146 bytes)
      drift-detection.md (14163 bytes)
      idempotency-guide.md (13181 bytes)
  01-provisioning-and-bootstrap/linux-package-management/
    SKILL.md (19340 bytes)
    01-provisioning-and-bootstrap/linux-package-management/references/
      apt-reference.md (16586 bytes)
      snap-reference.md (13339 bytes)
      unattended-upgrades-reference.md (12647 bytes)
  01-provisioning-and-bootstrap/linux-server-provisioning/
    SKILL.md (10357 bytes)
    01-provisioning-and-bootstrap/linux-server-provisioning/references/
      grub2-and-kernel-rollback.md (14163 bytes)
      post-install-verification.md (13103 bytes)
      provisioning-steps.md (21988 bytes)
02-users-access-and-secrets/
  02-users-access-and-secrets/linux-access-control/
    SKILL.md (7566 bytes)
    02-users-access-and-secrets/linux-access-control/references/
      permissions-reference.md (17229 bytes)
      users-sudoers-pam.md (23944 bytes)
  02-users-access-and-secrets/linux-secrets/
    SKILL.md (15122 bytes)
    02-users-access-and-secrets/linux-secrets/references/
      age-and-sops.md (19227 bytes)
      rotation-playbook.md (17619 bytes)
      secret-scanning.md (14211 bytes)
03-networking-and-dns/
  03-networking-and-dns/linux-dns-server/
    SKILL.md (12957 bytes)
    03-networking-and-dns/linux-dns-server/references/
      bind9-reference.md (22370 bytes)
      zone-file-syntax.md (19390 bytes)
  03-networking-and-dns/linux-network-admin/
    SKILL.md (15756 bytes)
    03-networking-and-dns/linux-network-admin/references/
      diagnostics-tree.md (15197 bytes)
      netplan-reference.md (15758 bytes)
      networkmanager-reference.md (5565 bytes)
04-web-and-mail-services/
  04-web-and-mail-services/linux-mail-server/
    SKILL.md (14342 bytes)
    04-web-and-mail-services/linux-mail-server/references/
      debugging-delivery.md (14692 bytes)
      email-authentication.md (18505 bytes)
      postfix-reference.md (21714 bytes)
  04-web-and-mail-services/linux-site-deployment/
    SKILL.md (9654 bytes)
    04-web-and-mail-services/linux-site-deployment/references/
      apache-backend.md (14846 bytes)
      deployment-checklist.md (12543 bytes)
      nginx-templates.md (15290 bytes)
  04-web-and-mail-services/linux-webstack/
    SKILL.md (8534 bytes)
    04-web-and-mail-services/linux-webstack/references/
      config-patterns.md (21973 bytes)
      httpd-reference.md (6089 bytes)
      nginx-directives.md (17290 bytes)
      php-fpm-tuning.md (15837 bytes)
05-services-and-virtualization/
  05-services-and-virtualization/linux-service-management/
    SKILL.md (11203 bytes)
    05-services-and-virtualization/linux-service-management/references/
      resource-control-and-targets.md (19172 bytes)
      service-reference.md (29107 bytes)
      timers-and-cron.md (21386 bytes)
  05-services-and-virtualization/linux-virtualization/
    SKILL.md (12337 bytes)
    05-services-and-virtualization/linux-virtualization/references/
      lxd-reference.md (22476 bytes)
06-storage-and-filesystems/
  06-storage-and-filesystems/linux-disk-storage/
    SKILL.md (10978 bytes)
    06-storage-and-filesystems/linux-disk-storage/references/
      cifs-and-network-mounts.md (15571 bytes)
      cleanup-patterns.md (17962 bytes)
      storage-reference.md (23913 bytes)
    06-storage-and-filesystems/linux-disk-storage/scripts/
      sk-cifs-mount.sh (11757 bytes)
07-security-and-hardening/
  07-security-and-hardening/linux-firewall-ssl/
    SKILL.md (10970 bytes)
    07-security-and-hardening/linux-firewall-ssl/references/
      certbot-reference.md (21680 bytes)
      firewalld-reference.md (6436 bytes)
      nftables-and-iptables.md (13365 bytes)
      ssl-config.md (24048 bytes)
      ufw-reference.md (21398 bytes)
    07-security-and-hardening/linux-firewall-ssl/scripts/
      sk-nft-apply.sh (10110 bytes)
      sk-nft-show.sh (5974 bytes)
  07-security-and-hardening/linux-intrusion-detection/
    SKILL.md (10384 bytes)
    07-security-and-hardening/linux-intrusion-detection/references/
      fail2ban-jails.md (18050 bytes)
      rootkit-scanning.md (18183 bytes)
  07-security-and-hardening/linux-security-analysis/
    SKILL.md (8243 bytes)
    07-security-and-hardening/linux-security-analysis/references/
      audit-layers.md (28938 bytes)
      threat-model.md (16443 bytes)
  07-security-and-hardening/linux-server-hardening/
    SKILL.md (8777 bytes)
    07-security-and-hardening/linux-server-hardening/references/
      hardening-checklist.md (20082 bytes)
      selinux-reference.md (15129 bytes)
      sysctl-reference.md (15251 bytes)
08-observability-and-logging/
  08-observability-and-logging/linux-log-management/
    SKILL.md (7816 bytes)
    08-observability-and-logging/linux-log-management/references/
      journalctl-reference.md (20792 bytes)
      log-analysis-patterns.md (19397 bytes)
      log-locations.md (21292 bytes)
  08-observability-and-logging/linux-observability/
    SKILL.md (16957 bytes)
    08-observability-and-logging/linux-observability/references/
      health-endpoint-pattern.md (12988 bytes)
      log-forwarding.md (17785 bytes)
      prometheus-setup.md (17083 bytes)
      telemetry-agents.md (14271 bytes)
  08-observability-and-logging/linux-system-monitoring/
    SKILL.md (6315 bytes)
    08-observability-and-logging/linux-system-monitoring/references/
      monitoring-commands.md (22779 bytes)
      warning-signs.md (18658 bytes)
09-troubleshooting-and-recovery/
  09-troubleshooting-and-recovery/linux-disaster-recovery/
    SKILL.md (9798 bytes)
    09-troubleshooting-and-recovery/linux-disaster-recovery/references/
      backup-strategy.md (18863 bytes)
      restore-procedures.md (18450 bytes)
  09-troubleshooting-and-recovery/linux-troubleshooting/
    SKILL.md (7941 bytes)
    09-troubleshooting-and-recovery/linux-troubleshooting/references/
      diagnosis-tree.md (30570 bytes)
      packet-capture-and-tracing.md (17015 bytes)
10-automation-and-scripting/
  10-automation-and-scripting/linux-bash-scripting/
    SKILL.md (15371 bytes)
    10-automation-and-scripting/linux-bash-scripting/references/
      common-sh-contract.md (10697 bytes)
      interactive-ux.md (5376 bytes)
      script-template.sh (5644 bytes)
  10-automation-and-scripting/linux-repo-sync/
    SKILL.md (8280 bytes)
    10-automation-and-scripting/linux-repo-sync/references/
      safe-update-pattern.md (3756 bytes)
11-databases-and-caching/
  11-databases-and-caching/linux-inmemory-stores/
    SKILL.md (10188 bytes)
    11-databases-and-caching/linux-inmemory-stores/references/
      memcached-reference.md (3966 bytes)
      redis-reference.md (5562 bytes)
    11-databases-and-caching/linux-inmemory-stores/scripts/
      sk-redis-status.sh (6360 bytes)
  11-databases-and-caching/linux-mysql-mariadb/
    SKILL.md (9672 bytes)
    11-databases-and-caching/linux-mysql-mariadb/references/
      binlog-and-pitr.md (3647 bytes)
      install-and-secure.md (2738 bytes)
      tuning-innodb.md (3240 bytes)
  11-databases-and-caching/linux-postgresql/
    SKILL.md (9901 bytes)
    11-databases-and-caching/linux-postgresql/references/
      backup-and-pitr.md (6106 bytes)
      install-and-auth.md (6035 bytes)
      tuning.md (5825 bytes)
12-containers-and-orchestration/
  12-containers-and-orchestration/linux-container-deployment/
    SKILL.md (11047 bytes)
    12-containers-and-orchestration/linux-container-deployment/references/
      compose-and-systemd-reference.md (8389 bytes)
    12-containers-and-orchestration/linux-container-deployment/scripts/
      sk-container-ps.sh (5921 bytes)
  12-containers-and-orchestration/linux-container-engine/
    SKILL.md (11498 bytes)
    12-containers-and-orchestration/linux-container-engine/references/
      container-engine-reference.md (15811 bytes)
    12-containers-and-orchestration/linux-container-engine/scripts/
      sk-engine-status.sh (7248 bytes)
  12-containers-and-orchestration/linux-image-hygiene/
    SKILL.md (8534 bytes)
    12-containers-and-orchestration/linux-image-hygiene/references/
      prune-and-scheduling.md (6085 bytes)
    12-containers-and-orchestration/linux-image-hygiene/scripts/
      sk-container-prune.sh (8440 bytes)
13-backup-and-archiving/
  13-backup-and-archiving/linux-archive-integrity/
    SKILL.md (11253 bytes)
    13-backup-and-archiving/linux-archive-integrity/references/
      incremental-and-verify.md (4861 bytes)
      tar-reference.md (5182 bytes)
  13-backup-and-archiving/linux-filesystem-snapshots/
    SKILL.md (11721 bytes)
    13-backup-and-archiving/linux-filesystem-snapshots/references/
      lvm-snapshots.md (4980 bytes)
      zfs-btrfs-snapshots.md (6113 bytes)
  13-backup-and-archiving/linux-rsync-sync/
    SKILL.md (11749 bytes)
    13-backup-and-archiving/linux-rsync-sync/references/
      incremental-snapshots.md (4486 bytes)
      rsync-reference.md (7211 bytes)
14-performance-and-kernel/
  14-performance-and-kernel/linux-kernel-modules/
    SKILL.md (10033 bytes)
    14-performance-and-kernel/linux-kernel-modules/references/
      module-management.md (8826 bytes)
    14-performance-and-kernel/linux-kernel-modules/scripts/
      sk-module-info.sh (6573 bytes)
  14-performance-and-kernel/linux-perf-profiling/
    SKILL.md (11857 bytes)
    14-performance-and-kernel/linux-perf-profiling/references/
      profiling-tools.md (8594 bytes)
  14-performance-and-kernel/linux-sysctl-tuning/
    SKILL.md (7781 bytes)
    14-performance-and-kernel/linux-sysctl-tuning/references/
      sysctl-tuning-reference.md (11311 bytes)
15-compliance-and-auditing/
  15-compliance-and-auditing/linux-auditd-rules/
    SKILL.md (10033 bytes)
    15-compliance-and-auditing/linux-auditd-rules/references/
      auditd-reference.md (14403 bytes)
  15-compliance-and-auditing/linux-benchmark-scanning/
    SKILL.md (9044 bytes)
    15-compliance-and-auditing/linux-benchmark-scanning/references/
      lynis-reference.md (5316 bytes)
      openscap-reference.md (7846 bytes)
  15-compliance-and-auditing/linux-file-integrity/
    SKILL.md (9974 bytes)
    15-compliance-and-auditing/linux-file-integrity/references/
      aide-reference.md (12060 bytes)
commands/
  .gitkeep (0 bytes)
  rclone.md (2853 bytes)
  redis.md (2977 bytes)
docs/
  docs/analysis/
    README.md (8370 bytes)
    build-order.md (16895 bytes)
    dual-compatibility-report.md (4658 bytes)
    gaps.md (15758 bytes)
    risks.md (16916 bytes)
    skills-coverage.md (7937 bytes)
    strengths.md (13389 bytes)
  docs/engine-design/
    README.md (2113 bytes)
    script-inventory.md (21195 bytes)
    spec.md (21261 bytes)
  docs/evaluation/
    docs/evaluation/2026-04-13/
      executive-summary.md (4123 bytes)
      gap-analysis.md (3695 bytes)
      recommendations.md (4305 bytes)
      scoring.md (3670 bytes)
      skill-domain-analysis.md (4527 bytes)
      suggested-reading.md (3416 bytes)
      system-reconstruction.md (4681 bytes)
      world-class-definition.md (3104 bytes)
  docs/multi-distro/
    plan.md (6448 bytes)
  docs/superpowers/
    docs/superpowers/plans/
      2026-04-09-linux-server-skills.md (93357 bytes)
      2026-06-15-engine-hardening-plan.md (10324 bytes)
    docs/superpowers/specs/
      2026-04-09-linux-server-skills-design.md (23852 bytes)
linux-sysadmin/
  SKILL.md (9577 bytes)
meta/
  meta/skill-safety-audit/
    SKILL.md (6107 bytes)
  meta/skill-writing/
    LICENSE.txt (11558 bytes)
    SKILL.md (11890 bytes)
    meta/skill-writing/references/
      generation-template.md (5207 bytes)
      output-patterns.md (1895 bytes)
      prompting-patterns-for-skills.md (12020 bytes)
      skill-authoring-best-practices.md (24343 bytes)
      workflows.md (845 bytes)
    meta/skill-writing/scripts/
      init_skill.py (11166 bytes)
      package_skill.py (3398 bytes)
      quick_validate.py (3617 bytes)
notes/
  .gitkeep (0 bytes)
  astro-site-setup.md (5634 bytes)
  mysql-backup-setup.md (4036 bytes)
  new-repo-checklist.md (2699 bytes)
  redis-setup.md (4483 bytes)
  server-security.md (18250 bytes)
  update-all-repos-setup.md (4327 bytes)
scripts/
  .gitkeep (0 bytes)
  install-skills-bin (15468 bytes)
  setup-claude-code.sh (9743 bytes)
  sk-audit-status.sh (7990 bytes)
  sk-audit.sh (22964 bytes)
  sk-benchmark-scan.sh (12633 bytes)
  sk-capture.sh (10468 bytes)
  sk-kernel-rollback.sh (9013 bytes)
  sk-lvm-snapshot.sh (7541 bytes)
  sk-mysql-backup.sh (10074 bytes)
  sk-mysql-health.sh (6395 bytes)
  sk-perf-snapshot.sh (7432 bytes)
  sk-pg-backup.sh (10512 bytes)
  sk-rootkit-scan.sh (10261 bytes)
  sk-rsync-backup.sh (8396 bytes)
  sk-selinux-denials.sh (8624 bytes)
  sk-service-priority.sh (9066 bytes)
  sk-sysctl-tune.sh (9883 bytes)
  sk-tar-verify.sh (7900 bytes)
  sk-telegraf-setup.sh (14305 bytes)
  sk-update-all-repos.sh (12978 bytes)
  scripts/lib/
    common.sh (25330 bytes)
  scripts/tests/
    check-distro-matrix.sh (2426 bytes)
    common-sh.test.sh (9449 bytes)
    install-skills-bin.test.sh (5306 bytes)
    run-test.sh (9659 bytes)
```
