# rclone - Cloud Storage Sync

rclone is a command-line tool for managing files on cloud storage (Google Drive, S3, Dropbox, etc.).

## Installation

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

# Delete remote files older than 3 days
rclone delete gdrive:backup-folder --min-age 3d

# Sync local dir to remote (mirror)
rclone sync /local/dir gdrive:remote-dir

# Check config
rclone config show
```

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
