# How to Create Your Own Compatible Server

This document describes the HTTP contract used by the YT2NAS clients. If you build your own server, implement these endpoints and response shapes.

Example base URL:

```text
http://192.168.0.123:9835
```

## Authentication

The client sends a shared secret in this header:

```text
X-Token: Password123
```

Notes:

- `GET /health` does not require authentication.
- All other endpoints listed here require `X-Token`.
- Responses are JSON with `application/json; charset=utf-8`.

## Endpoints

### POST /add

Enqueue a YouTube URL.

Request:

```http
POST /add
Content-Type: application/json
X-Token: <token>
```

Body:

```json
{"url":"https://www.youtube.com/watch?v=bmBTMYKMSKk"}
```

curl example:

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN="Password123"

curl -sS -X POST "$BASE_URL/add" \
  -H "Content-Type: application/json" \
  -H "X-Token: $TOKEN" \
  -d '{"url":"https://www.youtube.com/watch?v=bmBTMYKMSKk"}'
```

Success response:

```json
{"ok":true,"queue_len":3}
```

Common error responses:

```json
{"ok":false,"error":"unauthorized"}
```

```json
{"ok":false,"error":"invalid_json"}
```

```json
{"ok":false,"error":"invalid_or_non_youtube_url"}
```

### GET /health

Used by clients to check whether the server is reachable.

```bash
BASE_URL="http://192.168.0.123:9835"
curl -sS "$BASE_URL/health"
```

Response:

```json
{"ok":true,"queue_len":2,"has_secret":true,"has_add_script":true}
```

Fields:

- `ok`: basic server health flag
- `queue_len`: number of pending queue entries
- `has_secret`: whether the server has a configured token
- `has_add_script`: whether the enqueue helper exists

### GET /queue-len

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN="Password123"

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/queue-len"
```

Response:

```json
{"ok":true,"queue_len":2}
```

### GET /queue-tail

Peek into queued URLs.

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN="Password123"

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/queue-tail?lines=50"
```

Response:

```json
{"ok":true,"lines":50,"text":"https://youtu.be/..."}
```

### GET /tail

Read a log tail.

Query parameters:

- `log=yt` or `log=ytdlp`: yt-dlp processing log
- `log=endpoint`: endpoint log
- `lines=N`: number of lines to return; the reference server clamps this to 1-500

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN="Password123"

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/tail?log=yt&lines=120"
curl -sS -H "X-Token: $TOKEN" "$BASE_URL/tail?log=endpoint&lines=120"
```

Response:

```json
{"ok":true,"log":"yt","lines":120,"text":"==== 2026-03-03 ...\n[download] ...\n"}
```

### GET /media/channels

List immediate channel folders under the configured media root.

Authentication is required.

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN="Password123"

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/media/channels"
```

Response:

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

Rules:

- Only immediate child directories of `DOWNLOAD_DIR` are returned.
- Dot-prefixed entries such as `.queue`, `.trash`, and `.git` are excluded.
- `itemCount` is a direct child count only, not a recursive scan.

### GET /media/list

List direct children of one channel folder.

Authentication is required.

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN="Password123"

curl -sS -H "X-Token: $TOKEN" \
  "$BASE_URL/media/list?channel=Channel%20Name"
```

Response:

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

### POST /media/delete

Delete files or folders under `DOWNLOAD_DIR`. Folder deletion is recursive.

Authentication is required.

Request:

```http
POST /media/delete
Content-Type: application/json
X-Token: <token>
```

Body:

```json
{
  "paths": [
    "Channel Name/video.mp4",
    "Channel Name/subfolder"
  ]
}
```

curl example:

```bash
BASE_URL="http://192.168.0.123:9835"
TOKEN="Password123"

curl -sS -X POST "$BASE_URL/media/delete" \
  -H "Content-Type: application/json" \
  -H "X-Token: $TOKEN" \
  -d '{"paths":["Channel Name/video.mp4","Channel Name/subfolder"]}'
```

Response with partial results:

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

- Every path must be relative to `DOWNLOAD_DIR`.
- Absolute paths, empty paths, `.`, `..`, path traversal, and backslash paths are rejected.
- Dot-prefixed path segments such as `.queue`, `.trash`, and `.git` are rejected.
- The media root itself cannot be targeted.
- Symlinks are not followed outside `DOWNLOAD_DIR`.
- One failed path does not stop other delete attempts.
