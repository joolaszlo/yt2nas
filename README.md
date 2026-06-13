<p align="center">
  <img src="/assets/logo.png" alt="YT2NAS logo">
</p>

# YT2NAS

YT2NAS lets you send YouTube links from a browser or Android phone to a NAS. The NAS queues the links, downloads them with `yt-dlp`, and stores the media in a folder such as `/mnt/NAS/Youtube`.

## Components

- **NAS/server side**: a Python stdlib HTTP server, queue scripts, `yt-dlp`, and systemd services.
- **Android app**: shares YouTube links to the NAS, browses downloaded channel folders, and can delete media through the server API.
- **Kodi or another media player**: reads the same downloaded files through the NAS network share, for example `smb://SERVER_IP/Youtube`.
- **Tampermonkey/browser button**: adds a button to YouTube pages that sends the current URL to the NAS.

Media deletion is available through the Android/server media API. Deleting a file or folder is permanent and affects the same files Kodi sees through SMB.

## Install

- [Simple Installation Guide](./docs/Simple_Installation_Guide.md)

## Documentation

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
5. The NAS shares that folder on the LAN with SMB/Samba.
6. Kodi reads the shared folder, while Android can browse or delete the same files through the YT2NAS server API.
