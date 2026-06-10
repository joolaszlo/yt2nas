# How to Install the YT2NAS Server (Ubuntu)

This is the NAS-side setup. Client setup for Android and Tampermonkey is handled separately.

## Requirements

- Ubuntu with systemd
- sudo access
- Python 3 already installed
- Your NAS share already mounted, for example `/mnt/NAS`
- A non-root Linux user that will run the server and downloads

The default media root is `/mnt/NAS/Youtube`. The server only uses files under this root, with queue state in `<DOWNLOAD_DIR>/.queue`.

## Install

Clone or download this repository on the server, then run:

```bash
chmod +x server/install.sh server/yt2nas-server-setup.sh
sudo ./server/install.sh install
```

The installer prompts for:

- `RUN_USER`: non-root Linux user for the systemd service
- `DOWNLOAD_DIR`: media root folder, default `/mnt/NAS/Youtube`
- `PORT`: endpoint port, default `9835`
- `TOKEN`: shared secret; leave empty to generate one

The old entrypoint still works as a compatibility wrapper:

```bash
sudo ./server/yt2nas-server-setup.sh install
```

## What Gets Installed

- Server module copied from `server/yt2nas_server.py` to `/opt/yt2nas-server/yt2nas_server.py`
- Environment file: `/etc/yt2nas-server.env`
- Endpoint service: `/etc/systemd/system/yt2nas-server.service`
- Queue runner service and timer:
  - `/etc/systemd/system/yt2nas-queue.service`
  - `/etc/systemd/system/yt2nas-queue.timer`
- Queue helper scripts:
  - `/usr/local/bin/yt2nas-add.sh`
  - `/usr/local/bin/yt2nas-run.sh`
- Queue files and logs under `<DOWNLOAD_DIR>/.queue`

The installer also keeps the legacy config file `/etc/yt2nas/yt2nas.conf` for compatibility with older documentation and scripts.

## Configuration

Runtime configuration lives in:

```bash
sudo sed 's/^YT2NAS_TOKEN=.*/YT2NAS_TOKEN="<hidden>"/' /etc/yt2nas-server.env
```

Important values:

- `YT2NAS_RUN_USER`: non-root user running the service
- `YT2NAS_DOWNLOAD_DIR`: media root folder
- `YT2NAS_PORT`: HTTP endpoint port
- `YT2NAS_TOKEN`: shared secret sent as `X-Token`
- `YT2NAS_ADD_SCRIPT`: queue helper script path

After editing `/etc/yt2nas-server.env`, restart the service:

```bash
sudo systemctl restart yt2nas-server.service
```

## Verify

```bash
sudo systemctl status yt2nas-server.service --no-pager
sudo systemctl status yt2nas-queue.timer --no-pager
curl http://127.0.0.1:9835/health
```

If you changed the port, use that port instead of `9835`.

Authenticated smoke test:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -H "X-Token: $TOKEN" http://127.0.0.1:9835/queue-len
```

## Update

Run from a fresh checkout of the repository:

```bash
sudo ./server/install.sh update
```

This updates `yt-dlp`, recopies `server/yt2nas_server.py` into `/opt/yt2nas-server/`, rewrites managed scripts and units, and restarts services.

## Uninstall

```bash
sudo ./server/install.sh uninstall
```

This stops services and removes installed units, helper scripts, `/opt/yt2nas-server/yt2nas_server.py`, and config files. Downloaded videos remain.

To also remove queue files and logs:

```bash
sudo ./server/install.sh uninstall --purge
```

`--purge` removes `<DOWNLOAD_DIR>/.queue`. It does not delete downloaded videos.

## Endpoint Summary

Base URL:

```text
http://YOUR_SERVER_IP:9835
```

Public endpoint:

- `GET /health`

Authenticated endpoints require this header:

```text
X-Token: <your_token>
```

- `POST /add` with JSON body `{"url":"https://www.youtube.com/watch?v=VIDEO_ID"}`
- `GET /queue-len`
- `GET /queue-tail?lines=50`
- `GET /tail?log=yt&lines=120`
- `GET /tail?log=endpoint&lines=120`
- `GET /media/channels`
- `GET /media/list?channel=<channel-folder-name>`
- `POST /media/delete`

## Media Management API

All media paths are restricted to `YT2NAS_DOWNLOAD_DIR`, usually `/mnt/NAS/Youtube`. The server rejects absolute paths, path traversal, empty paths, and dot-prefixed internal folders such as `.queue`, `.trash`, or `.git`.

Folder deletion is recursive. Use it carefully.

List channel folders:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -H "X-Token: $TOKEN" \
  http://127.0.0.1:9835/media/channels
```

List direct children of one channel folder:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -H "X-Token: $TOKEN" \
  'http://127.0.0.1:9835/media/list?channel=Channel%20Name'
```

Delete files or folders under `DOWNLOAD_DIR`:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -X POST http://127.0.0.1:9835/media/delete \
  -H "Content-Type: application/json" \
  -H "X-Token: $TOKEN" \
  -d '{"paths":["Channel Name/video.mp4","Channel Name/subfolder"]}'
```

The delete response contains both `deleted` and `failed` arrays so one bad path does not stop the rest of the request.

## Manual Test Checklist

```bash
curl http://127.0.0.1:9835/health

TOKEN='YOUR_TOKEN'
curl -sS -H "X-Token: $TOKEN" http://127.0.0.1:9835/media/channels
curl -sS -H "X-Token: $TOKEN" 'http://127.0.0.1:9835/media/list?channel=Channel%20Name'
curl -sS -X POST http://127.0.0.1:9835/media/delete \
  -H "Content-Type: application/json" \
  -H "X-Token: $TOKEN" \
  -d '{"paths":["Channel Name/test-file-to-delete.txt"]}'
```
