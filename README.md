# Linux Skills

A knowledge base of Linux commands, scripts, and setup guides for server administration.

## Structure

```
commands/   Command references by topic
scripts/    Reusable shell scripts
notes/      Setup guides and troubleshooting
```

## Contents

### Commands
- [rclone](commands/rclone.md) — Cloud storage sync (Google Drive, S3, etc.)
- [redis](commands/redis.md) — In-memory data store CLI reference

### Scripts
- [update-all-repos](scripts/update-all-repos) — **Mandatory on all servers.** One command to pull all repos
- [mysql-backup.sh](scripts/mysql-backup.sh) — Automated MySQL backup script
- [server-audit.sh](scripts/server-audit.sh) — Server security audit script

### Notes
- [update-all-repos Setup](notes/update-all-repos-setup.md) — How to set up the repo update script on any server
- [MySQL Backup Setup](notes/mysql-backup-setup.md) — Automated backups with Google Drive upload
- [Redis Setup](notes/redis-setup.md) — Redis for PHP sessions and application caching
- [Server Security](notes/server-security.md) — Server hardening and security audit guide
- [New Repo Checklist](notes/new-repo-checklist.md) — Steps for adding a new repo to the server
