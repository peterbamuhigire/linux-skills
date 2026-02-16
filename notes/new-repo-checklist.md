# New Repo Checklist for This Server

Every time a new Git repository is cloned or created on this server, it **must** be registered in the update scripts so it stays in sync.

## Scripts to Update

Both scripts live in `/usr/local/bin/` and are owned by root (require `sudo` to edit).

### 1. `update-all-repos` (batch/non-interactive)

Add a new entry to the `REPOS` associative array at the top of the file:

```bash
REPOS["My New Repo"]="/path/to/repo"
```

### 2. `update-repos` (interactive menu)

Three changes are needed:

1. **Add a menu entry** — add an `echo` line with the next number:
   ```bash
   echo "  7) My New Repo"
   ```

2. **Add a case entry** — add a matching case in the `case $choice in` block:
   ```bash
   7) update_repo "/path/to/repo" ;;
   ```

3. **Update the invalid-choice range** — change the `*) echo` message to reflect the new max number:
   ```bash
   *) echo "Invalid choice. Please enter 0-7." ;;
   ```

## Current Repos in the Scripts

| # | Name             | Path                              |
|---|------------------|-----------------------------------|
| 1 | Maduuka          | /var/www/html/Maduuka             |
| 2 | DMS_web          | /var/www/html/DMS_web             |
| 3 | Server Manager   | /var/www/html/server-manager      |
| 4 | BIRDC ERP        | /var/www/html/birdcerp            |
| 5 | Linux Skills     | /home/administrator/linux-skills  |

## Quick Command

To edit the scripts:

```bash
sudo nano /usr/local/bin/update-all-repos
sudo nano /usr/local/bin/update-repos
```
