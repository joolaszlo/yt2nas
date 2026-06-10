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

## Share Downloads with Kodi over SMB

YT2NAS and Kodi use the same downloaded files in two different ways:

1. YT2NAS downloads videos into `DOWNLOAD_DIR`, usually `/mnt/NAS/Youtube`.
2. Your NAS shares that folder on the local network with SMB/Samba.
3. Kodi reads the shared folder over the network and plays the videos.
4. The Android app talks to the YT2NAS server API. It can list files and delete files from the same folder that Kodi sees.

The Linux path and the Kodi path are different views of the same folder.

Example Linux/server path:

```text
/mnt/NAS/Youtube
```

Example Kodi/SMB path:

```text
smb://192.168.0.157/Youtube
```

Example Windows network path for the same share:

```text
\\192.168.0.157\Youtube
```

`Youtube` is only an example share name. Use the share name from your Samba/NAS configuration.

### Add the Folder in Kodi

On the device running Kodi:

1. Open **Videos**.
2. Open **Files**.
3. Choose **Add videos...**.
4. Choose **Browse**.
5. Choose **Add network location...** if the share is not already listed.
6. Set **Protocol** to **Windows network (SMB)**.
7. Enter the server IP address, for example `192.168.0.157`.
8. Enter the shared folder name, for example `Youtube`.
9. Save the location and add it as a video source.

If your SMB share needs a username and password, enter the Samba/NAS account that can read the shared folder.

### Kodi and SMB Troubleshooting

If files are visible on the server but not in Kodi, check these items.

Confirm that the files exist in the Linux folder:

```bash
ls -la /mnt/NAS/Youtube
```

Check that Samba is running:

```bash
sudo systemctl status smbd
```

Check the Samba configuration:

```bash
sudo testparm -s
```

Look for a share that points to the same folder as `DOWNLOAD_DIR`, for example `/mnt/NAS/Youtube`.

In Kodi, open the video source and refresh it. If the share name or server IP changed, remove the old Kodi source and add it again.

Permissions are checked in two places:

- YT2NAS needs read, write, and delete permission inside `DOWNLOAD_DIR`.
- Kodi usually only needs read permission through the SMB share.

Deleting from the Android app is permanent. Deleted files disappear from the same folder Kodi reads, so Kodi will no longer be able to play them.

## Media Management Warning

The server exposes media browsing and deletion endpoints for Android support:

- `GET /media/channels`
- `GET /media/list?channel=<channel-folder-name>`
- `POST /media/delete`

Delete is permanent. Folder delete is recursive. Deleting from Android removes the same files that Kodi sees through SMB. The server rejects absolute paths, path traversal, and dot-prefixed internal folders such as `.queue`, `.trash`, and `.git`.

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
