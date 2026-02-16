# How to Set Up `update-all-repos` on Any Linux Server

A single command to pull the latest changes for all your Git repositories at once.

## Prerequisites

- Git installed (`sudo apt install git` or `sudo yum install git`)
- SSH keys or HTTPS credentials configured for your repositories
- Repositories already cloned on the server

## Step-by-Step Setup

### 1. Create the script

```bash
sudo nano /usr/local/bin/update-all-repos
```

Paste the template from `scripts/update-all-repos` in this repo, or copy it directly:

```bash
sudo cp /path/to/linux-skills/scripts/update-all-repos /usr/local/bin/update-all-repos
```

### 2. Edit the REPOS section

Open the script and update the `REPOS` array with your own repositories:

```bash
declare -A REPOS
REPOS["MyApp"]="/var/www/html/myapp"
REPOS["Backend API"]="/var/www/html/backend"
REPOS["Admin Panel"]="/var/www/html/admin"
```

- The key (e.g., `"MyApp"`) is a display name shown during updates.
- The value is the absolute path to the cloned repository on the server.

### 3. Make it executable

```bash
sudo chmod +x /usr/local/bin/update-all-repos
```

### 4. Run it

```bash
update-all-repos
```

No `.sh` extension needed — `/usr/local/bin` is in the system PATH, so it works like any other command.

## What It Does

For each repository listed in the `REPOS` array, the script:

1. Checks that the directory is a valid Git repo
2. Runs `git reset --hard HEAD` to discard local tracked changes
3. Runs `git pull --rebase` to fetch and apply the latest changes
4. Reports the current branch and latest commit

Untracked files (like user uploads in `/uploads/` directories) are **not** affected.

## Tips

- **Add or remove repos** by editing the `REPOS` array — no other changes needed.
- **SSH keys**: Make sure the user running the script has SSH access to the repos. Test with `ssh -T git@github.com`.
- **Cron job** (optional): Automate updates by adding to crontab:
  ```bash
  crontab -e
  # Run every day at 2 AM
  0 2 * * * /usr/local/bin/update-all-repos >> /var/log/repo-updates.log 2>&1
  ```
- **Production warning**: The script resets tracked changes. Any manual edits to tracked files on the server will be lost.
