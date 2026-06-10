# Quick Server Install

This guide installs the NAS-side YT2NAS server on Ubuntu. The Android app and Tampermonkey script are configured separately.

## Requirements

- Ubuntu or another Linux system with systemd
- sudo access
- Python 3 installed
- a mounted NAS folder, for example `/mnt/NAS`
- a non-root Linux user that can read, write, and delete inside the media folder

The default media root is:

```text
/mnt/NAS/Youtube
```

Inside that folder, each channel is expected to be a direct child folder.

## Install Command

Run this from a checkout of the YT2NAS repo:

```bash
chmod +x server/install.sh server/yt2nas-server-setup.sh
sudo ./server/install.sh install
```

`server/yt2nas-server-setup.sh` is kept only as a deprecated compatibility wrapper. Use `server/install.sh` for new installs.

## Installer Prompts

The installer asks for these values:

- `RUN_USER`: the non-root Linux user that runs the server and queue.
- `DOWNLOAD_DIR`: the media root folder, usually `/mnt/NAS/Youtube`.
- `PORT`: the HTTP port, usually `9835`.
- `TOKEN`: the shared secret used by Android, Tampermonkey, and curl requests.

Recommended values:

```text
RUN_USER      your normal NAS/download user
DOWNLOAD_DIR  /mnt/NAS/Youtube
PORT          9835
TOKEN         leave empty to generate one, or paste your existing private token
```

Do not share your real token publicly. It is the password-like shared secret for protected server endpoints.

## What Gets Installed

- versioned server file copied to `/opt/yt2nas-server/yt2nas_server.py`
- runtime config written to `/etc/yt2nas-server.env`
- main server service: `yt2nas-server.service`
- queue service and timer: `yt2nas-queue.service` and `yt2nas-queue.timer`
- queue helper scripts in `/usr/local/bin`
- queue files and logs under `<DOWNLOAD_DIR>/.queue`

The installer also writes `/etc/yt2nas/yt2nas.conf` for compatibility with older scripts and documentation.

## Edit Configuration Safely

Show the config without printing the token:

```bash
sudo sed 's/^YT2NAS_TOKEN=.*/YT2NAS_TOKEN="<hidden>"/' /etc/yt2nas-server.env
```

Edit the config:

```bash
sudo nano /etc/yt2nas-server.env
```

Restart the server after changes:

```bash
sudo systemctl restart yt2nas-server.service
```

If you changed the port, update the Android app and browser script base URL too.

## Test the Server

Local health check on the NAS:

```bash
curl http://127.0.0.1:9835/health
```

LAN health check from another computer on the same network:

```bash
curl http://SERVER_LAN_IP:9835/health
```

Use the NAS LAN IP address, not `127.0.0.1`. On a phone, `127.0.0.1` means the phone itself.

Token-protected media endpoint test:

```bash
TOKEN='paste-your-token-here'
curl -sS -H "X-Token: $TOKEN" http://127.0.0.1:9835/media/channels
```

Avoid pasting real tokens into public logs or screenshots.

## Media Management Warning

The server exposes media browsing and deletion endpoints for Android support:

- `GET /media/channels`
- `GET /media/list?channel=<channel-folder-name>`
- `POST /media/delete`

Delete is permanent. Folder delete is recursive. The server rejects absolute paths, path traversal, and dot-prefixed internal folders such as `.queue`, `.trash`, and `.git`.

## Update

From a fresh checkout:

```bash
sudo ./server/install.sh update
```

This recopies `server/yt2nas_server.py` to `/opt/yt2nas-server/`, refreshes managed scripts and systemd units, updates `yt-dlp`, and restarts the services.

## Uninstall

Remove services, installed server files, helper scripts, and config files:

```bash
sudo ./server/install.sh uninstall
```

Remove queue files and logs too:

```bash
sudo ./server/install.sh uninstall --purge
```

Downloaded videos are not deleted by uninstall. `--purge` removes only `<DOWNLOAD_DIR>/.queue`.

## More Help

- [Existing server migration guide](./server_migration_guide.md)
- [Troubleshooting](./troubleshooting.md)
- [Server API contract](./how_to_create_your_own_server.md)
