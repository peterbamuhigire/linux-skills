# New Repo Checklist for This Server

Every time a new Git repository is cloned or created on this server, it **must** be registered in the update script so it stays in sync.

## Script to Update

The main script is `/usr/local/bin/update-all-repos` (owned by root, requires `sudo` to edit).
`/usr/local/bin/update-repos` is a wrapper that calls `update-all-repos`.

### Adding a New Repo

Add a new entry to the `REPO_LIST` array at the top of the file:

```bash
REPO_LIST=(
    # ... existing entries ...
    "My New Repo|/path/to/repo|"
)
```

If the repo needs a post-update build step (like npm build), add it as the third field:

```bash
    "My New Repo|/path/to/repo|npm install && npm run build"
```

The new repo will automatically get the next number in the menu. No other changes are needed.

### Quick Edit Command

```bash
sudo nano /usr/local/bin/update-all-repos
```

## Current Repos in the Script

| # | Name                    | Path                              | Post-Update          |
|---|-------------------------|-----------------------------------|----------------------|
| 1 | Maduuka Demo            | /var/www/html/maduukademo         |                      |
| 2 | DMS_web                 | /var/www/html/DMS_web             |                      |
| 3 | Server Manager          | /var/www/html/server-manager      |                      |
| 4 | BIRDC ERP               | /var/www/html/birdcerp            |                      |
| 5 | Linux Skills            | /home/administrator/linux-skills  |                      |
| 6 | Maduuka Website (Astro) | /var/www/maduuka-website          | npm install && build |
