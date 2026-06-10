# Server API Contract

This document describes the HTTP API used by the YT2NAS Android app and browser integration. Use it if you want to test the server manually or build a compatible client/server.

Example base URL:

```text
http://192.168.0.123:9835
```

## Authentication

`GET /health` is public. All other endpoints require:

```text
X-Token: <your-token>
```

The token is the shared app/server secret from `/etc/yt2nas-server.env`. Do not paste real tokens into public issues, screenshots, or chat.

Responses are JSON:

```text
application/json; charset=utf-8
```

## GET /health

Checks whether the server is reachable.

```bash
BASE_URL="http://192.168.0.123:9835"
curl -sS "$BASE_URL/health"
```

Example response:

```json
{
  "ok": true,
  "queue_len": 2,
  "has_secret": true,
  "has_add_script": true
}
```

## POST /add

Adds a YouTube URL to the queue.

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN='paste-your-token-here'

curl -sS -X POST "$BASE_URL/add" \
  -H "Content-Type: application/json" \
  -H "X-Token: $TOKEN" \
  -d '{"url":"https://www.youtube.com/watch?v=bmBTMYKMSKk"}'
```

Success:

```json
{
  "ok": true,
  "queue_len": 3
}
```

Common errors:

```json
{"ok":false,"error":"unauthorized"}
```

```json
{"ok":false,"error":"invalid_json"}
```

```json
{"ok":false,"error":"invalid_or_non_youtube_url"}
```

## GET /queue-len

Returns the number of queued URLs.

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN='paste-your-token-here'

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/queue-len"
```

Example response:

```json
{
  "ok": true,
  "queue_len": 2
}
```

## GET /queue-tail

Returns the last lines of the queue file.

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN='paste-your-token-here'

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/queue-tail?lines=50"
```

Example response:

```json
{
  "ok": true,
  "lines": 50,
  "text": "https://youtu.be/..."
}
```

## GET /tail

Returns the last lines of a server log.

Query parameters:

- `log=yt` or `log=ytdlp`: `yt-dlp` processing log
- `log=endpoint`: endpoint log
- `lines=N`: number of lines to return

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN='paste-your-token-here'

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/tail?log=yt&lines=120"
curl -sS -H "X-Token: $TOKEN" "$BASE_URL/tail?log=endpoint&lines=120"
```

Example response:

```json
{
  "ok": true,
  "log": "yt",
  "lines": 120,
  "text": "==== 2026-03-03 ...\n[download] ...\n"
}
```

## GET /media/channels

Lists immediate channel folders under `DOWNLOAD_DIR`.

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN='paste-your-token-here'

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/media/channels"
```

Example response:

```json
{
  "ok": true,
  "channels": [
    {
      "name": "Channel Name",
      "relPath": "Channel Name",
      "modified": "2026-06-10T12:34:56Z",
      "itemCount": 42
    }
  ]
}
```

Notes:

- only immediate child folders are returned
- dot-prefixed folders such as `.queue`, `.trash`, and `.git` are hidden
- `itemCount` is a direct child count, not a recursive scan

## GET /media/list

Lists direct children of one channel folder.

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN='paste-your-token-here'

curl -sS -H "X-Token: $TOKEN" \
  "$BASE_URL/media/list?channel=Channel%20Name"
```

Example response:

```json
{
  "ok": true,
  "channel": "Channel Name",
  "relPath": "Channel Name",
  "items": [
    {
      "name": "video.mp4",
      "relPath": "Channel Name/video.mp4",
      "isDir": false,
      "size": 123456789,
      "modified": "2026-06-10T12:34:56Z"
    },
    {
      "name": "Subfolder",
      "relPath": "Channel Name/Subfolder",
      "isDir": true,
      "modified": "2026-06-10T12:34:56Z"
    }
  ]
}
```

Common errors:

```json
{"ok":false,"error":"missing_channel"}
```

```json
{"ok":false,"error":"invalid_channel","details":"channel_must_be_immediate_child"}
```

```json
{"ok":false,"error":"channel_not_found"}
```

## POST /media/delete

Deletes files or folders under `DOWNLOAD_DIR`.

Warning: deletion is permanent. Folder deletion is recursive.

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN='paste-your-token-here'

curl -sS -X POST "$BASE_URL/media/delete" \
  -H "Content-Type: application/json" \
  -H "X-Token: $TOKEN" \
  -d '{"paths":["Channel Name/video.mp4","Channel Name/subfolder"]}'
```

Request body:

```json
{
  "paths": [
    "Channel Name/video.mp4",
    "Channel Name/subfolder"
  ]
}
```

Example partial-success response:

```json
{
  "ok": false,
  "deleted": [
    "Channel Name/video.mp4"
  ],
  "failed": [
    {
      "path": "Channel Name/missing.mp4",
      "error": "not_found"
    }
  ]
}
```

Safety rules:

- paths must be relative to `DOWNLOAD_DIR`
- absolute paths are rejected
- path traversal with `.` or `..` is rejected
- empty paths are rejected
- dot-prefixed internal folders such as `.queue`, `.trash`, and `.git` are rejected
- symlink traversal outside the media root is rejected
- the media root itself cannot be deleted
- one failed path does not stop the rest of the request
