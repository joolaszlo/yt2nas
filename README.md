<p align="center">
  <img src="/assets/logo.png" alt="YT2NAS logo">
</p>

**YT2NAS** is a local network setup for sending YouTube links to a NAS, where downloads are handled **server-side** in a **queue**, with **password protection**.

The goal is simple: from a browser button or Android Share, send a YouTube URL to your NAS, let it download in order, and then play the resulting files from your NAS folder, for example in Kodi.

## Components

### 1) NAS-side downloader

The NAS runs the actual download with [yt-dlp](https://github.com/yt-dlp/yt-dlp). Both the browser script and the Android app call the same HTTP endpoint, where:

- submitted URLs are added to a queue
- processing happens sequentially
- the endpoint requires a password

The server endpoint is a versioned Python file in this repository: `server/yt2nas_server.py`. The installer copies it to `/opt/yt2nas-server/` and configures it with `/etc/yt2nas-server.env`.

The same protected API can also list channel folders, list files inside a channel, and delete media paths under the configured `DOWNLOAD_DIR`. Delete operations are recursive for folders and always require the `X-Token` header.

Quick install:

```bash
chmod +x server/install.sh server/yt2nas-server-setup.sh
sudo ./server/install.sh install
```

### 2) Browser button injected into YouTube (Tampermonkey)

A Tampermonkey userscript adds a download button directly to the YouTube UI. Clicking it sends the current video URL to the NAS endpoint.

<img src="/assets/yt2nas_t_script.png" alt="script screenshot" width="400">

### 3) Android app (Flutter)

A minimalist Flutter app that:

- shows a first-run configuration screen for NAS address and password
- appears in Android's Share sheet and forwards shared YouTube links to the NAS endpoint

<img src="/assets/yt2nas_client_android.jpg" alt="Android app screenshot" width="200">

## Typical Flow

1. Open a YouTube video.
2. Click the injected browser button or share the link to the Android app.
3. The URL is sent to the NAS HTTP endpoint.
4. The NAS downloads items in queue order.
5. Kodi or any player browses the NAS folder and plays the downloaded files.

Full setup and usage guide: **[Full guide](./docs/how_to_advanced_mode.md)**

Quick start server guide: **[Quick start](./docs/how_to_install_the_server_easymode.md)**

Build your own compatible server: **[How to create](./docs/how_to_create_your_own_server.md)**
