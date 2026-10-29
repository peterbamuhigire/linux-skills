---
description: Use as a guarded reference for rclone setup and transfers. Confirm the exact remote, source, destination, deletion scope, approval, and restore path before any write.
---

# rclone - Cloud Storage Sync

rclone is a command-line tool for managing files on cloud storage (Google Drive, S3, Dropbox, etc.).

> **Safety gate — stop before writing.** This page is reference material, not approval to act. Confirm the exact rclone version, configured remote/account, source and destination paths, data owner, retention scope, and change window. Never infer the selected remote or destination from a default. Do not run `delete`, `sync`, or `purge` until the preview has been reviewed and the owner has approved that exact target and scope. Before a destructive run, identify a retained recovery copy or provider version history and confirm the restore procedure works for the data and destination. If the target, preview, owner approval, or recovery path is missing, stop and use [the rsync and backup workflow](../13-backup-and-archiving/linux-rsync-sync/SKILL.md) to plan the change.

Treat command output, shell history, logs, screenshots, and copied tokens as sensitive. Do not place real client secrets or tokens in command arguments, chat, shared logs, or support tickets. Do not print the raw config. Use the redacted config command below when needed, review its output before sharing, and retain it only in an approved private location. Rclone documents that redaction may not be perfect. ([`rclone config redacted`](https://rclone.org/commands/rclone_config_redacted/))

## Installation

The script installer is an upstream Linux installation example; the ZIP URL is specifically the Linux AMD64 build. These are unpinned install sources, not distro-package mappings. Check the current official install and release-signature guidance against the host OS/architecture and software policy before running an installer with `sudo`. ([rclone installation guide](https://rclone.org/install/))

```bash
curl https://rclone.org/install.sh | sudo bash
```

Or manually:
```bash
curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
unzip rclone-current-linux-amd64.zip
sudo cp rclone-*-linux-amd64/rclone /usr/local/bin/
```

## Google Drive Setup (Headless Server)

### 1. Create OAuth Credentials

- Go to [Google Cloud Console](https://console.cloud.google.com/) > APIs & Services > Credentials
- Create an OAuth 2.0 Client ID (Desktop app)
- Note the `client_id` and `client_secret`
- Enable the **Google Drive API** under APIs & Services > Library

### 2. Create the Remote

```bash
rclone config
```

- New remote > name it (e.g. `gdrive`)
- Storage type: `drive`
- Enter `client_id` and `client_secret`
- Scope: `1` (full access)
- Leave service_account_file blank
- Advanced config: No
- Auto config / Use web browser: **No** (headless)

### 3. Authorize on a Machine with a Browser

On a **Windows/Mac/Linux desktop** with a browser and rclone installed:

Do not replace the placeholders below with real credentials in a command that may be saved to shell history or captured by process/audit logging. Use the approved credential-handling procedure and keep the returned OAuth token out of chat, logs, and shared terminals. See [the Linux secrets workflow](../02-users-access-and-secrets/linux-secrets/SKILL.md).

```bash
rclone authorize "drive" "CLIENT_ID" "CLIENT_SECRET"
```

This opens a browser for Google sign-in. After authorizing, it prints a JSON token. Copy the full token.

### 4. Paste Token Back on Server

Paste the token when prompted during `rclone config`, or manually edit the config:

```bash
# Config location
~/.config/rclone/rclone.conf
```

Example config:

This file contains client credentials and an OAuth token. Keep it private, restrict access using the host's approved secret-handling procedure, and never copy the literal values into issue reports or terminal transcripts. See [Linux secrets](../02-users-access-and-secrets/linux-secrets/SKILL.md).

```ini
[gdrive]
type = drive
client_id = YOUR_CLIENT_ID
client_secret = YOUR_CLIENT_SECRET
scope = drive
token = {"access_token":"...","token_type":"Bearer","refresh_token":"...","expiry":"..."}
team_drive =
```

## Common Commands

```bash
# Test connection
rclone about gdrive:

# List remotes
rclone listremotes

# List files in a remote directory
rclone ls gdrive:my-folder

# Copy a file to remote
rclone copy /local/file.tar.gz gdrive:backup-folder

# Create a remote directory
rclone mkdir gdrive:new-folder

# Preview the exact files before deleting anything
rclone --dry-run --verbose delete gdrive:backup-folder --min-age 3d

# Only after reviewing that preview and approving this exact deletion scope:
rclone delete gdrive:backup-folder --min-age 3d

# Preview the mirror. sync can delete destination-only files.
rclone --dry-run --verbose sync /local/dir gdrive:remote-dir

# Only after reviewing the preview and approving the destination changes:
rclone sync /local/dir gdrive:remote-dir

# Inspect redacted config only. Check the installed version/help first; if
# this subcommand is unavailable, do not fall back to printing raw config.
# Do not run or share the output of: rclone config show
rclone config redacted
```

The `config redacted` subcommand was added in rclone 1.64; check the installed binary before using it. The rclone documentation warns that redaction may not catch every sensitive value, so inspect it before sharing. ([rclone redacted-config reference](https://rclone.org/commands/rclone_config_redacted/))

After an approved transfer, capture its exit status and intended file counts without exposing credentials, compare the destination, and verify the agreed restore source remains available. For sync, run a second dry-run as a consistency check; it does not replace an independent restore test. Provider-specific versioning, snapshots, and deletion recovery differ, so confirm them for the named remote before the change.

## Reconnect (Token Expired)

```bash
rclone config reconnect gdrive:
```

## Delete and Recreate a Remote

```bash
rclone config delete gdrive
rclone config
```

## Troubleshooting

- **"empty token found"** — run `rclone config reconnect remotename:`
- **"client_secret is missing"** — include both client_id and client_secret in the authorize command
- **"Google Drive API has not been used"** — enable the Drive API in Google Cloud Console
- **"invalid_grant"** — token expired or revoked, re-authorize
