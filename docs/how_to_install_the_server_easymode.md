# How to Install the YT2NAS Server (Ubuntu)

This section is NAS-side setup only. Client side (Android app, Tampermonkey script) is handled separately.

---

## Easy mode

Minimal description: run one installer script on your Ubuntu server. It installs dependencies, sets up the download queue, starts the endpoint service, schedules downloads, and configures the firewall for LAN-only access.

### Commands

```bash
chmod +x yt2nas-server-setup
sudo ./yt2nas-server-setup install
sudo ./yt2nas-server-setup status
sudo ./yt2nas-server-setup update
sudo ./yt2nas-server-setup uninstall
sudo ./yt2nas-server-setup uninstall --purge
```

Notes:
- `uninstall` keeps videos and the main download folder.
- `uninstall --purge` also deletes the queue folder: `<DOWNLOAD_DIR>/.queue` (videos remain).

---

## Advanced mode

## Requirements
- Ubuntu with systemd
- sudo access
- Your NAS share is already mounted on the server (example: `/mnt/NAS`)
- Choose a download folder inside the mounted NAS path (example: `/mnt/NAS/Youtube`)
- Optional: a second Linux user that accesses the NAS files over the network (common with Samba)

## What the installer sets up
- Installs packages: `ffmpeg`, `python3`, `curl`, `ufw`, `util-linux` (for `flock`)
- Installs `yt-dlp` into the service user home: `~/.local/bin/yt-dlp`
- Writes yt-dlp config into: `~/.config/yt-dlp/config`
- Creates queue folder: `<DOWNLOAD_DIR>/.queue`
- Creates scripts:
  - `/usr/local/bin/yt2nas-add.sh`
  - `/usr/local/bin/yt2nas-run.sh`
  - `/usr/local/bin/yt2nas_server.py`
- Creates systemd units:
  - `yt2nas-endpoint.service`
  - `yt2nas-queue.service`
  - `yt2nas-queue.timer`
- Stores config: `/etc/yt2nas/yt2nas.conf`
- Stores endpoint token in a secret file: `<DOWNLOAD_DIR>/.queue/endpoint.secret` (mode `600`)
- Configures UFW:
  - denies the endpoint port globally
  - allows only from your trusted LAN subnet

## Interactive install details
Run:
```bash
sudo ./yt2nas-server-setup install
```

The installer asks for:
- Service Linux user (runs endpoint and downloads)
- Optional second Linux user (network file access user)
- Shared group name (default: `yt2nas`)
- Download folder (must be inside your NAS mount)
- Endpoint port (default: `9835`)
- Trusted subnet CIDR for UFW (default: `192.168.0.0/24`)
- Queue runner interval in minutes (default: `5`)
- Max video height (default: `2160`, examples: `720`, `1080`, `2160`)
- Endpoint token/password (minimum 4 characters)

## Folder permissions model
- Download folder owner: `SERVICE_USER:GROUP`
- Folder has setgid bit so new files inherit the group
- Group members (service user and optional second user) can write and delete files

## Verify services, timer, logs
Check services:
```bash
systemctl status yt2nas-endpoint.service --no-pager
systemctl status yt2nas-queue.timer --no-pager
```

Check timers and recent runs:
```bash
systemctl list-timers --all | grep yt2nas || true
journalctl -u yt2nas-queue.service --no-pager -n 200
```

Queue and endpoint logs (file based):
```bash
tail -n 200 <DOWNLOAD_DIR>/.queue/endpoint.log
tail -n 200 <DOWNLOAD_DIR>/.queue/yt-dlp.log
```

## Firewall verification
```bash
sudo ufw status verbose
```

Expected behavior:
- allow from `<TRUSTED_SUBNET>` to port `<PORT>/tcp`
- deny `<PORT>/tcp` for other sources

## Health and connectivity tests
Local health check (on the server):
```bash
curl http://127.0.0.1:9835/health
```

LAN health check (from another device on the subnet):
```bash
curl http://YOUR_SERVER_IP:9835/health
```

If you changed the port during install, use that port instead of `9835`.

## Non-interactive install (optional)

With flags:
```bash
sudo ./yt2nas-server-setup install --yes \
  --service-user YOUR_SERVICE_USER \
  --nas-user YOUR_OPTIONAL_SECOND_USER \
  --group yt2nas \
  --download-dir /mnt/NAS/Youtube \
  --port 9835 \
  --subnet 192.168.0.0/24 \
  --interval 5 \
  --max-height 2160 \
  --token 'YOUR_TOKEN'
```

With environment variables (flags override env vars):
```bash
sudo YT2NAS_SERVICE_USER=YOUR_SERVICE_USER \
  YT2NAS_NAS_USER=YOUR_OPTIONAL_SECOND_USER \
  YT2NAS_GROUP=yt2nas \
  YT2NAS_DOWNLOAD_DIR=/mnt/NAS/Youtube \
  YT2NAS_PORT=9835 \
  YT2NAS_SUBNET=192.168.0.0/24 \
  YT2NAS_INTERVAL=5 \
  YT2NAS_MAX_HEIGHT=2160 \
  YT2NAS_TOKEN='YOUR_TOKEN' \
  ./yt2nas-server-setup install --yes
```

## Update
```bash
sudo ./yt2nas-server-setup update
```

What it does:
- Updates yt-dlp for the service user
- Rewrites scripts and systemd unit files from the saved config
- Restarts the endpoint service and queue timer
- Reapplies UFW rules from the saved config

## Uninstall
```bash
sudo ./yt2nas-server-setup uninstall
```

What it does:
- Stops and disables systemd units
- Removes unit files, scripts, and `/etc` config
- Does not delete your download folder or videos

Uninstall with purge:
```bash
sudo ./yt2nas-server-setup uninstall --purge
```

This also deletes `<DOWNLOAD_DIR>/.queue` (queue files and logs). Videos remain.

## Server endpoint summary

Base URL:
- `http://YOUR_SERVER_IP:9835`

Endpoints:
- `GET /health` (no auth)

Authenticated endpoints (header required):
- Header: `X-Token: <your_token>`

- `POST /add`
  - JSON body: `{"url":"https://www.youtube.com/watch?v=VIDEO_ID"}`

- `GET /queue-len`
- `GET /queue-tail?lines=50`
- `GET /tail?log=yt&lines=120`
  - `log=yt` for yt-dlp log
  - `log=endpoint` for endpoint log
