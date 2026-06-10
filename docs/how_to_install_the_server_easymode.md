# YT2NAS Simple Installation Guide

This guide explains the basic installation of the full YT2NAS system.

The system has four main parts:

1. a NAS/Linux server
2. a shared download folder
3. a browser button on the PC
4. an Android app

Basic workflow:

1. You send a YouTube link from the Android app or from the browser button.
2. The server adds the link to a download queue.
3. The server downloads the video into a NAS folder.
4. Kodi or another media player reads the downloaded files from the shared folder.
5. The Android app can also list and delete downloaded files through the server.

Important: deleting files from the Android app is permanent. If you delete a folder, all files inside that folder are also deleted.

---

# 1. Create and share the download folder

First, create a folder on the NAS or Linux server where the videos will be downloaded.

Example:

```bash
sudo mkdir -p /mnt/NAS/Youtube
```

This folder will contain the downloaded videos. Usually, each channel will have its own folder.

Example:

```text
/mnt/NAS/Youtube
```

## 1.1. Give the server user permission

The YT2NAS server should run as a normal Linux user, not as root.

Example user:

```text
nasuser
```

This user must be able to read, write, and delete files inside the download folder.

Example permission setup:

```bash
sudo setfacl -R -m u:nasuser:rwx /mnt/NAS/Youtube
sudo setfacl -R -m d:u:nasuser:rwx /mnt/NAS/Youtube
```

This gives `nasuser` permission for existing files and also sets default permissions for new files and folders.

## 1.2. Share the folder over the network

Kodi and other media players usually access the folder through SMB/Samba.

The Linux folder path may be:

```text
/mnt/NAS/Youtube
```

The same folder may appear on the network as:

```text
smb://192.168.0.157/Youtube
```

On Windows, it may look like:

```text
\\192.168.0.157\Youtube
```

The exact share name depends on your Samba/NAS configuration.

The important idea:

* YT2NAS downloads files into the Linux folder.
* Kodi reads the same files through the SMB share.
* The Android app can delete the same files through the YT2NAS server.

## 1.3. Add the folder in Kodi

In Kodi:

1. Open `Videos`.
2. Open `Files`.
3. Choose `Add videos`.
4. Choose `Browse` or `Add network location`.
5. Select `SMB`.
6. Enter the server IP address.
7. Enter or select the shared folder name.

Example:

```text
Protocol: SMB
Server address: 192.168.0.157
Shared folder: Youtube
```

Example Kodi path:

```text
smb://192.168.0.157/Youtube
```

Kodi does not connect to the YT2NAS API. Kodi only reads the shared video folder.

---

# 2. Install the YT2NAS server

Install the server on the Linux machine that can access the download folder.

Server repository:

```text
https://github.com/joolaszlo/yt2nas
```

## 2.1. Copy or clone the server files

Recommended method:

```bash
cd /mnt/NAS/NAS
git clone https://github.com/joolaszlo/yt2nas.git
cd yt2nas
```

If you do not use Git, copy the server repository files to your server.

At minimum, the installer needs these files:

```text
server/install.sh
server/yt2nas_server.py
server/yt2nas-server-setup.sh
```

## 2.2. Stop an old server first, if one already exists

If you already had an older YT2NAS or ytqueue server running, stop it before installing the new one.

Find old services:

```bash
systemctl list-units --type=service | grep -iE 'yt2nas|ytqueue|youtube|ytdlp'
```

Check whether port `9835` is already in use:

```bash
sudo ss -ltnp | grep ':9835'
```

If you see something like this:

```text
/usr/bin/python3 /usr/local/bin/ytqueue_server.py
```

then an old server is probably still running.

Find which service started it:

```bash
systemctl status PID
```

Replace `PID` with the process ID.

Example:

```bash
systemctl status 1509
```

If the old service is named `ytqueue-endpoint.service`, stop and disable it:

```bash
sudo systemctl stop ytqueue-endpoint.service
sudo systemctl disable ytqueue-endpoint.service
```

Check the port again:

```bash
sudo ss -ltnp | grep ':9835'
```

If there is no output, the port is free.

## 2.3. Run the installer

From the repository root:

```bash
chmod +x server/install.sh server/yt2nas-server-setup.sh
sudo ./server/install.sh install
```

The installer will ask for a few values.

## 2.4. Installer questions

### RUN_USER

The Linux user that will run the YT2NAS server.

Example:

```text
nasuser
```

This user must have read/write/delete permission inside the download folder.

### DOWNLOAD_DIR

The folder where videos will be downloaded.

Example:

```text
/mnt/NAS/Youtube
```

This is also the folder shared with Kodi.

### PORT

The HTTP port used by the YT2NAS server.

Recommended example:

```text
9835
```

The Android app and the browser button will use this port.

### TOKEN

The shared secret token used by clients.

Example:

```text
my-long-secret-token-123
```

The same token must be entered in:

* the Android app
* the Tampermonkey browser script
* manual API tests using the `X-Token` header

Important: this token is not an encrypted password. It is the actual shared secret. Do not publish it.

---

# 3. Install the PC browser button

The browser button is used to send the current YouTube video URL to the YT2NAS server.

It uses Tampermonkey.

## 3.1. Install Tampermonkey

Install the Tampermonkey extension in your browser.

Common browsers:

* Chrome
* Edge
* Firefox

## 3.2. Add the YT2NAS userscript

Open the Tampermonkey dashboard.

Choose:

```text
Create a new script
```

Paste the YT2NAS userscript content:

[script/script.js](./script/script.js)

## 3.3. Configure the script

Set the server URL in the script.

Example:

```text
http://192.168.0.157:9835
```

Set the same token that you used during server installation.

The script should send YouTube URLs to the server `/add` endpoint using the `X-Token` header.

---

# 4. Install the Android app

The Android app is provided as a release APK. 

## 4.1. Download the APK

Open the YT2NAS server repository release page:

```text
https://github.com/joolaszlo/yt2nas/releases
```

## 4.2. Copy the APK to the phone

You can copy the APK to the phone using:

* USB cable
* cloud storage
* network share
* messaging app
* `adb install`

ADB example:

```bash
adb install -r yt2nas-client.apk
```

If Android blocks the installation, allow installing apps from unknown sources for the app you used to open the APK.

## 4.3. Configure the Android app

Open the app and enter the server settings.

Example:

```text
Server URL: http://192.168.0.157:9835
Token: the same token used during server installation
```

## 4.4. Basic Android app usage

The Android app can:

* send YouTube links to the server
* list downloaded channel folders
* list downloaded files
* delete downloaded files
* delete downloaded folders

Important: deleting a folder is recursive and permanent.

Start with a test file before deleting real videos.

---

# 5. Troubleshooting and checks

Use this section after installation if something does not work.

## 5.1. Check whether the server is running

On the server:

```bash
sudo systemctl status yt2nas-server.service --no-pager
```

Local health check:

```bash
curl http://127.0.0.1:9835/health
```

Expected result should contain something like:

```json
{"ok": true}
```

## 5.2. Check whether the server is reachable from the LAN

Find the server IP:

```bash
hostname -I
```

Example:

```text
192.168.0.157
```

From another computer or from the phone browser, open:

```text
http://192.168.0.157:9835/health
```

If this does not work, check the firewall:

```bash
sudo ufw status
```

Allow the port on the local network if needed:

```bash
sudo ufw allow from 192.168.0.0/24 to any port 9835 proto tcp
```

## 5.3. Check token-protected endpoints

The server config is stored here:

```text
/etc/yt2nas-server.env
```

View it on the server:

```bash
sudo cat /etc/yt2nas-server.env
```

Use the token in a test request:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -H "X-Token: $TOKEN" http://127.0.0.1:9835/media/channels
```

LAN test:

```bash
TOKEN='YOUR_TOKEN'
curl -sS -H "X-Token: $TOKEN" http://192.168.0.157:9835/media/channels
```

If `/health` works but this does not, the token is probably wrong.

## 5.4. App cannot connect

Common causes:

* wrong server URL
* using `127.0.0.1` on the phone
* wrong token
* phone is not on the same network
* firewall blocks the port
* Android blocks cleartext HTTP traffic

Correct app URL example:

```text
http://192.168.0.157:9835
```

Wrong app URL example:

```text
http://127.0.0.1:9835
```

## 5.5. Port already in use

Check the port:

```bash
sudo ss -ltnp | grep ':9835'
```

Check the process:

```bash
ps -fp PID
systemctl status PID
```

If an old service is using the port, stop and disable it.

Example:

```bash
sudo systemctl stop ytqueue-endpoint.service
sudo systemctl disable ytqueue-endpoint.service
```

## 5.6. File delete works, but folder delete does not

Folder deletion needs permission on the folder and its contents.

Test as the server user:

```bash
sudo -u nasuser ls -la /mnt/NAS/Youtube
```

Test file delete:

```bash
sudo -u nasuser touch "/mnt/NAS/Youtube/Test Channel/_delete_test.txt"
sudo -u nasuser rm "/mnt/NAS/Youtube/Test Channel/_delete_test.txt"
```

Test folder delete:

```bash
sudo -u nasuser mkdir "/mnt/NAS/Youtube/Test Channel/_delete_test_dir"
sudo -u nasuser rmdir "/mnt/NAS/Youtube/Test Channel/_delete_test_dir"
```

If this fails, apply ACL permissions:

```bash
sudo setfacl -R -m u:nasuser:rwx /mnt/NAS/Youtube
sudo setfacl -R -m d:u:nasuser:rwx /mnt/NAS/Youtube
```

If `/mnt/NAS` is mounted through CIFS, NFS, NTFS, or another network filesystem, mount options may also affect permissions.

## 5.7. Kodi cannot see the downloaded files

Check whether the files exist on the server:

```bash
ls -la /mnt/NAS/Youtube
```

If files exist on the server but not in Kodi:

* check that Kodi uses the correct SMB share
* check the Samba share path
* check Samba permissions
* refresh the Kodi source
* restart Samba if the share configuration changed

Restart Samba:

```bash
sudo systemctl restart smbd
```

## 5.8. Useful logs

Server service log:

```bash
journalctl -u yt2nas-server.service -n 100 --no-pager
```

Queue service log:

```bash
journalctl -u yt2nas-queue.service -n 100 --no-pager
```

Endpoint log file:

```bash
tail -n 100 /mnt/NAS/Youtube/.queue/endpoint.log
```

yt-dlp log file:

```bash
tail -n 100 /mnt/NAS/Youtube/.queue/yt-dlp.log
```

---

# 6. Important paths and values

Server configuration:

```text
/etc/yt2nas-server.env
```

Installed server file:

```text
/opt/yt2nas-server/yt2nas_server.py
```

Server service:

```text
yt2nas-server.service
```

Example download folder:

```text
/mnt/NAS/Youtube
```

Queue/log folder:

```text
/mnt/NAS/Youtube/.queue
```

Example server URL:

```text
http://192.168.0.157:9835
```

Example Kodi SMB path:

```text
smb://192.168.0.157/Youtube
```

Server repository:

```text
https://github.com/joolaszlo/yt2nas
```

Android app repository:

```text
https://github.com/joolaszlo/yt2nas_client
```
