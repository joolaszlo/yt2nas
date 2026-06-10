# YT2NAS Advanced Server Guide

YT2NAS queues YouTube links from browser and Android clients to a NAS folder. The server is a small Python stdlib HTTP endpoint plus shell scripts for queueing and running `yt-dlp`.

## Recommended Install

Use the repo installer from an Ubuntu host with systemd:

```bash
chmod +x server/install.sh server/yt2nas-server-setup.sh
sudo ./server/install.sh install
```

The installer checks for Python before doing any setup. If Python is missing, install it manually:

```bash
sudo apt update
sudo apt install python3
```

The endpoint runs as the non-root `RUN_USER` chosen during install. Do not use `root`.

## Installed Layout

Source-controlled server file:

```text
server/yt2nas_server.py
```

Installed server file:

```text
/opt/yt2nas-server/yt2nas_server.py
```

Runtime config:

```text
/etc/yt2nas-server.env
```

Systemd units:

```text
/etc/systemd/system/yt2nas-server.service
/etc/systemd/system/yt2nas-queue.service
/etc/systemd/system/yt2nas-queue.timer
```

Queue scripts:

```text
/usr/local/bin/yt2nas-add.sh
/usr/local/bin/yt2nas-run.sh
```

Queue files and logs:

```text
<DOWNLOAD_DIR>/.queue/queue.txt
<DOWNLOAD_DIR>/.queue/archive.txt
<DOWNLOAD_DIR>/.queue/endpoint.log
<DOWNLOAD_DIR>/.queue/yt-dlp.log
```

Default media root:

```text
/mnt/NAS/Youtube
```

## Configuration

Show configuration without printing the token:

```bash
sudo sed 's/^YT2NAS_TOKEN=.*/YT2NAS_TOKEN="<hidden>"/' /etc/yt2nas-server.env
```

Main values:

- `YT2NAS_RUN_USER`: non-root user for systemd
- `YT2NAS_DOWNLOAD_DIR`: media root; default `/mnt/NAS/Youtube`
- `YT2NAS_PORT`: endpoint port; default `9835`
- `YT2NAS_TOKEN`: shared secret sent by clients as `X-Token`
- `YT2NAS_ADD_SCRIPT`: enqueue helper
- `YT2NAS_SECRET_FILE`: compatibility token file under `.queue`

After editing config:

```bash
sudo systemctl restart yt2nas-server.service
```

After changing unit files:

```bash
sudo systemctl daemon-reload
sudo systemctl restart yt2nas-server.service
sudo systemctl restart yt2nas-queue.timer
```

## Non-Interactive Install

```bash
sudo ./server/install.sh install --yes \
  --run-user YOUR_SERVICE_USER \
  --download-dir /mnt/NAS/Youtube \
  --port 9835 \
  --token 'YOUR_TOKEN'
```

Compatibility options are also available:

```bash
sudo ./server/install.sh install --yes \
  --run-user YOUR_SERVICE_USER \
  --nas-user YOUR_OPTIONAL_SECOND_USER \
  --group yt2nas \
  --download-dir /mnt/NAS/Youtube \
  --port 9835 \
  --subnet 192.168.0.0/24 \
  --interval 5 \
  --max-height 2160 \
  --token 'YOUR_TOKEN'
```

If `--token` is omitted in non-interactive mode, the installer generates one and prints it at the end.

## Service Operations

```bash
sudo ./server/install.sh status
sudo systemctl status yt2nas-server.service --no-pager
sudo systemctl status yt2nas-queue.timer --no-pager
sudo systemctl list-timers --all | grep yt2nas || true
```

Logs:

```bash
journalctl -u yt2nas-server.service --no-pager -n 200
journalctl -u yt2nas-queue.service --no-pager -n 200
tail -n 200 /mnt/NAS/Youtube/.queue/endpoint.log
tail -n 200 /mnt/NAS/Youtube/.queue/yt-dlp.log
```

## Smoke Tests

```bash
curl http://127.0.0.1:9835/health
```

```bash
TOKEN='YOUR_TOKEN'
curl -sS -H "X-Token: $TOKEN" http://127.0.0.1:9835/queue-len
```

Add a URL:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -X POST http://127.0.0.1:9835/add \
  -H "Content-Type: application/json" \
  -H "X-Token: $TOKEN" \
  -d '{"url":"https://www.youtube.com/watch?v=bmBTMYKMSKk"}'
```

## Media Management API

The media API is server-side only. It is intended for clients such as the Android app to browse and delete downloaded media later.

All media operations are restricted to `YT2NAS_DOWNLOAD_DIR`, usually `/mnt/NAS/Youtube`. Paths are relative to that folder. The server rejects absolute paths, path traversal, empty paths, and dot-prefixed internal folders such as `.queue`, `.trash`, and `.git`.

All media endpoints require:

```text
X-Token: <your_token>
```

List channel folders:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -H "X-Token: $TOKEN" \
  http://127.0.0.1:9835/media/channels
```

List direct children of one channel:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -H "X-Token: $TOKEN" \
  'http://127.0.0.1:9835/media/list?channel=Channel%20Name'
```

Delete files or folders:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -X POST http://127.0.0.1:9835/media/delete \
  -H "Content-Type: application/json" \
  -H "X-Token: $TOKEN" \
  -d '{"paths":["Channel Name/video.mp4","Channel Name/subfolder"]}'
```

Folder deletion is recursive. The delete response includes `deleted` and `failed` arrays, so a bad path does not stop the rest of the request.

## Firewall

The installer preserves the legacy UFW behavior:

- deny `<PORT>/tcp` globally
- allow `<TRUSTED_SUBNET>` to `<PORT>/tcp`

Check it with:

```bash
sudo ufw status verbose
```

## Update

From a fresh checkout:

```bash
sudo ./server/install.sh update
```

This recopies the versioned Python server into `/opt/yt2nas-server/`, refreshes queue scripts and units, updates `yt-dlp`, and restarts services.

## Uninstall

```bash
sudo ./server/install.sh uninstall
```

This removes services, helper scripts, installed server files, and config files. Downloaded videos remain.

To remove queue files and logs too:

```bash
sudo ./server/install.sh uninstall --purge
```

`--purge` removes `<DOWNLOAD_DIR>/.queue`. It does not delete videos in the media root.
