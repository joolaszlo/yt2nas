# Existing Server Migration Guide

Use this guide if you already have an older YT2NAS, `ytqueue`, or hand-written server running on the NAS.

The goal is to stop the old endpoint, free the port, and install the current server from `server/install.sh`.

## 1. Find Old Services

List likely old services:

```bash
systemctl list-units --type=service | grep -iE 'yt2nas|ytqueue|youtube|ytdlp'
```

Common old service names include:

```text
ytqueue-endpoint.service
yt2nas-endpoint.service
```

Inspect a service:

```bash
systemctl status <service>
```

If the status output shows a process ID, inspect it:

```bash
ps -fp <PID>
```

## 2. Check Who Uses Port 9835

```bash
sudo ss -ltnp | grep ':9835'
```

If the command prints a process, port `9835` is already in use. Inspect the process:

```bash
ps -fp <PID>
```

If it belongs to an old systemd service, inspect that service:

```bash
systemctl status <service>
```

## 3. Stop and Disable the Old Service

Replace `<service>` with the real service name:

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

No output usually means nothing is listening on that port.

## 4. Keep the Old Token If Needed

If you do not want to update the Android app token, reuse the old token during the new install.

Common old token locations:

```text
/mnt/NAS/Youtube/.queue/endpoint.secret
/etc/yt2nas/yt2nas.conf
```

Show the old secret file if it exists:

```bash
sudo cat /mnt/NAS/Youtube/.queue/endpoint.secret
```

Keep this token private. During `sudo ./server/install.sh install`, paste the same value when the installer asks for `TOKEN`.

## 5. Install the New Server

From a checkout of the current repo:

```bash
chmod +x server/install.sh server/yt2nas-server-setup.sh
sudo ./server/install.sh install
```

The new endpoint service is:

```text
yt2nas-server.service
```

Runtime config is:

```text
/etc/yt2nas-server.env
```

## 6. Test After Migration

On the NAS:

```bash
curl http://127.0.0.1:9835/health
```

From another device on the LAN:

```bash
curl http://SERVER_LAN_IP:9835/health
```

Protected endpoint:

```bash
TOKEN='paste-your-token-here'
curl -sS -H "X-Token: $TOKEN" http://127.0.0.1:9835/media/channels
```

## Android Base URL Reminder

In the Android app, use the NAS LAN IP address:

```text
http://SERVER_LAN_IP:9835
```

Do not use this on the phone:

```text
http://127.0.0.1:9835
```

On a phone, `127.0.0.1` means the phone itself, not the NAS.
