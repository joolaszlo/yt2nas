# Advanced Server Guide

This page is a reference for the installed server layout and common admin commands. Start with the [quick install guide](./how_to_install_the_server_easymode.md) if you are installing for the first time.

## Installed Layout

Source-controlled server file:

```text
server/yt2nas_server.py
```

Installed server file:

```text
/opt/yt2nas-server/yt2nas_server.py
```

Runtime configuration:

```text
/etc/yt2nas-server.env
```

Systemd units:

```text
/etc/systemd/system/yt2nas-server.service
/etc/systemd/system/yt2nas-queue.service
/etc/systemd/system/yt2nas-queue.timer
```

Queue helper scripts:

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

Show config without printing the token:

```bash
sudo sed 's/^YT2NAS_TOKEN=.*/YT2NAS_TOKEN="<hidden>"/' /etc/yt2nas-server.env
```

Important values:

- `YT2NAS_RUN_USER`: non-root user that runs the service
- `YT2NAS_DOWNLOAD_DIR`: media root, default `/mnt/NAS/Youtube`
- `YT2NAS_PORT`: endpoint port, default `9835`
- `YT2NAS_TOKEN`: shared secret sent as `X-Token`
- `YT2NAS_ADD_SCRIPT`: enqueue helper path
- `YT2NAS_SECRET_FILE`: compatibility token file under `.queue`

Edit and restart:

```bash
sudo nano /etc/yt2nas-server.env
sudo systemctl restart yt2nas-server.service
```

## Service Commands

```bash
sudo systemctl status yt2nas-server.service --no-pager
sudo systemctl status yt2nas-queue.timer --no-pager
sudo systemctl list-timers --all | grep yt2nas || true
```

Restart after server config changes:

```bash
sudo systemctl restart yt2nas-server.service
```

Reload systemd after unit changes:

```bash
sudo systemctl daemon-reload
sudo systemctl restart yt2nas-server.service
sudo systemctl restart yt2nas-queue.timer
```

## Logs

```bash
journalctl -u yt2nas-server.service --no-pager -n 200
journalctl -u yt2nas-queue.service --no-pager -n 200
tail -n 200 /mnt/NAS/Youtube/.queue/endpoint.log
tail -n 200 /mnt/NAS/Youtube/.queue/yt-dlp.log
```

## Non-Interactive Install

```bash
sudo ./server/install.sh install --yes \
  --run-user YOUR_SERVICE_USER \
  --download-dir /mnt/NAS/Youtube \
  --port 9835 \
  --token 'YOUR_PRIVATE_TOKEN'
```

Compatibility options:

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
  --token 'YOUR_PRIVATE_TOKEN'
```

If `--token` is omitted, the installer generates one and prints it at the end.

## Smoke Tests

```bash
curl http://127.0.0.1:9835/health
```

```bash
TOKEN='paste-your-token-here'
curl -sS -H "X-Token: $TOKEN" http://127.0.0.1:9835/queue-len
curl -sS -H "X-Token: $TOKEN" http://127.0.0.1:9835/media/channels
```

Add a URL:

```bash
TOKEN='paste-your-token-here'
curl -sS -X POST http://127.0.0.1:9835/add \
  -H "Content-Type: application/json" \
  -H "X-Token: $TOKEN" \
  -d '{"url":"https://www.youtube.com/watch?v=bmBTMYKMSKk"}'
```

## Media Management

Media paths are restricted to `YT2NAS_DOWNLOAD_DIR`. Dot-prefixed internal folders such as `.queue`, `.trash`, and `.git` are hidden and cannot be targeted.

Deletion is permanent. Folder deletion is recursive.

See the [server API contract](./how_to_create_your_own_server.md) for request and response examples.

## Firewall

The installer preserves the LAN-focused UFW behavior:

- deny `<PORT>/tcp` globally
- allow `<TRUSTED_SUBNET>` to `<PORT>/tcp`

Check firewall status:

```bash
sudo ufw status verbose
```

This setup is intended for trusted LAN use. Do not expose the server directly to the public internet.

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

## Related Docs

- [Existing server migration guide](./server_migration_guide.md)
- [Troubleshooting](./troubleshooting.md)
- [Server API contract](./how_to_create_your_own_server.md)
