<p align="center">
  <img src="/assets/logo.png" alt="YT2NAS logo">
</p>

# YT2NAS

YT2NAS lets you send YouTube links from a browser or Android phone to a NAS. The NAS queues the links, downloads them with `yt-dlp`, and stores the media in a folder such as `/mnt/NAS/Youtube`.

## Components

- **NAS/server side**: a Python stdlib HTTP server, queue scripts, `yt-dlp`, and systemd services.
- **Android app**: shares YouTube links to the NAS, browses downloaded channel folders, and can delete media through the server API.
- **Tampermonkey/browser button**: adds a button to YouTube pages that sends the current URL to the NAS.

Media deletion is available through the Android/server media API. Deleting a folder is permanent and recursive.

## Server Install

Run the server installer from a checkout of this repo:

```bash
chmod +x server/install.sh server/yt2nas-server-setup.sh
sudo ./server/install.sh install
```

The installed server runs from `/opt/yt2nas-server/yt2nas_server.py`. Runtime configuration is stored in `/etc/yt2nas-server.env`.

## Documentation

- [Quick server install](./docs/how_to_install_the_server_easymode.md)
- [Existing server migration guide](./docs/server_migration_guide.md)
- [Troubleshooting](./docs/troubleshooting.md)
- [Server API contract](./docs/how_to_create_your_own_server.md)
- [Advanced server guide](./docs/how_to_advanced_mode.md)

## Security Notes

- The server is intended for trusted LAN use.
- Protected endpoints require the `X-Token` header.
- Do not post your real token in issues, screenshots, logs, or chat.
- If the Android app is connecting over plain `http://`, your Android build must allow cleartext HTTP for the server address.

## Typical Flow

1. Share or queue a YouTube link.
2. The NAS adds it to the queue.
3. The queue timer runs `yt-dlp`.
4. The downloaded files appear under the configured media root.
5. Android or any NAS media player can browse the result.
