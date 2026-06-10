# Troubleshooting

This guide assumes the server was installed with `server/install.sh`.

## A. App Cannot Connect to Server

Check the service on the NAS:

```bash
sudo systemctl status yt2nas-server.service --no-pager
```

Check local health on the NAS:

```bash
curl http://127.0.0.1:9835/health
```

Check whether the server is listening on the port:

```bash
sudo ss -ltnp | grep ':9835'
```

From another machine on the same LAN:

```bash
curl http://SERVER_LAN_IP:9835/health
```

Check the firewall:

```bash
sudo ufw status
```

In the Android app, the base URL must use the NAS LAN IP:

```text
http://SERVER_LAN_IP:9835
```

Do not use this in the Android app:

```text
http://127.0.0.1:9835
```

On a phone, `127.0.0.1` means the phone itself, not the NAS.

If a browser can reach the server but the Android app cannot, the Android build may be blocking cleartext HTTP. The server examples use `http://`, so the Android app must allow cleartext HTTP for the NAS address or the server must be put behind HTTPS.

## B. Health Works, But Protected Endpoints Fail

`GET /health` does not require a token. Protected endpoints require:

```text
X-Token: <your-token>
```

The token is not encrypted. It is the shared secret between the app and server.

Check the configured token without printing it:

```bash
sudo sed 's/^YT2NAS_TOKEN=.*/YT2NAS_TOKEN="<hidden>"/' /etc/yt2nas-server.env
```

Test a protected endpoint:

```bash
TOKEN='paste-your-token-here'
curl -sS -H "X-Token: $TOKEN" http://127.0.0.1:9835/media/channels
```

To change the token:

```bash
sudo nano /etc/yt2nas-server.env
sudo systemctl restart yt2nas-server.service
```

Then update the Android app and Tampermonkey script with the same token. Do not paste real tokens into public places.

## C. Port Already in Use

Check who is listening on port `9835`:

```bash
sudo ss -ltnp | grep ':9835'
```

Inspect the process:

```bash
ps -fp <PID>
```

Ask systemd whether it knows the PID:

```bash
systemctl status <PID>
```

If it is a systemd service, inspect that service:

```bash
systemctl status <service>
```

If it is an old `ytqueue` or `yt2nas` endpoint, stop and disable it:

```bash
sudo systemctl stop <service>
sudo systemctl disable <service>
```

Examples:

```bash
sudo systemctl stop ytqueue-endpoint.service
sudo systemctl disable ytqueue-endpoint.service
```

```bash
sudo systemctl stop yt2nas-endpoint.service
sudo systemctl disable yt2nas-endpoint.service
```

Verify the port is free:

```bash
sudo ss -ltnp | grep ':9835'
```

## D. Permission Problems

The server runs as the configured `RUN_USER`. That user must be able to read, write, and delete inside `DOWNLOAD_DIR`.

Deletion requires write and execute permission on parent directories. It is possible for files to be deletable while folders fail if existing subfolders have stricter permissions.

Replace `RUN_USER` with the real service user:

```bash
sudo -u RUN_USER ls -la /mnt/NAS/Youtube
sudo -u RUN_USER touch "/mnt/NAS/Youtube/Test Channel/_delete_test.txt"
sudo -u RUN_USER rm "/mnt/NAS/Youtube/Test Channel/_delete_test.txt"
sudo -u RUN_USER mkdir "/mnt/NAS/Youtube/Test Channel/_delete_test_dir"
sudo -u RUN_USER rmdir "/mnt/NAS/Youtube/Test Channel/_delete_test_dir"
```

If ACLs are available, this can grant the service user access to existing and future files:

```bash
sudo setfacl -R -m u:RUN_USER:rwx /mnt/NAS/Youtube
sudo setfacl -R -m d:u:RUN_USER:rwx /mnt/NAS/Youtube
```

If `/mnt/NAS` is mounted with CIFS, NTFS, or NFS, mount options may override normal Linux permissions. Check your mount configuration if permissions look correct but deletes still fail.

## E. Media List Works But Delete Fails

Check which user the service should run as:

```bash
sudo sed 's/^YT2NAS_TOKEN=.*/YT2NAS_TOKEN="<hidden>"/' /etc/yt2nas-server.env
```

Check the systemd unit:

```bash
systemctl cat yt2nas-server.service
```

Look for:

```text
User=<RUN_USER>
```

Check logs:

```bash
journalctl -u yt2nas-server.service -n 100 --no-pager
tail -n 100 /mnt/NAS/Youtube/.queue/endpoint.log
```

Remember that folder deletion is recursive and permanent. A folder delete can fail if any nested file or folder is not deletable by the service user.

## F. Queue or Download Issues

Check the timer:

```bash
systemctl status yt2nas-queue.timer --no-pager
systemctl list-timers --all | grep yt2nas || true
```

Check the queue runner:

```bash
journalctl -u yt2nas-queue.service -n 100 --no-pager
```

Check queue and download logs:

```bash
tail -n 100 /mnt/NAS/Youtube/.queue/yt-dlp.log
tail -n 100 /mnt/NAS/Youtube/.queue/endpoint.log
```

Check the queued URLs:

```bash
tail -n 100 /mnt/NAS/Youtube/.queue/queue.txt
```

If downloads never start, make sure `yt2nas-queue.timer` is enabled and running.
