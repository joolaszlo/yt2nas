<p align="center">
  <img src="/assets/logo.png" alt="YT2NAS logo">
</p>

**YT2NAS** is a local network setup for sending YouTube links to a NAS, where downloads are handled **server-side** in a **queue**, with **password-protection**.

The goal is simple: from a browser (via a YouTube page button) or from Android (via Share), send a video URL to your NAS, let it download in order, and then play the resulting files from your NAS folder (for example in Kodi).

## Components

### 1) NAS-side downloader
The NAS runs the actual download ( [yt-dlp](https://github.com/yt-dlp/yt-dlp)).  
Both the browser script and the Android app call the **same HTTP endpoint**, where:
- submitted URLs are added to a **queue**
- processing happens **sequentially**
- the endpoint is require a **password**

### 2) Browser button injected into YouTube (Tampermonkey)
A Tampermonkey userscript adds a download button directly to the YouTube UI.  
Clicking it sends the current video URL to the NAS endpoint.


<img src="/assets/yt2nas_t_script.png" alt="script screenshot" width="400">

### 3) Android app (Flutter)
A minimalist Flutter app that:
- shows a first-run configuration screen (NAS address + password)
- can appear in Android’s Share sheet and automatically forwards the shared YouTube link to the NAS endpoint

<img src="/assets/yt2nas_client_android.jpg" alt="Android app screenshot" width="200">

## Typical flow

1. Open a YouTube video
2. Click the injected browser button OR share the link to the Android app
3. The URL is sent to the NAS HTTP endpoint
4. The NAS downloads items **in queue order**
5. Kodi (or any player) browses the NAS folder and plays the downloaded files

Detailed usage guide: **[How to use](./howto.md)**
