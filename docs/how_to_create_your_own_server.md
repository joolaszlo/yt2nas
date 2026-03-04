This document describes the HTTP contract used by the YT2NAS Client (Flutter app and Tampermonkey userscript).
If you want to build your own compatible server, implement the endpoints below exactly.
The IP address, port number, and password can be configured, these are only example values.

BASE URL

The client stores a base URL configured by the user:

BASE_URL = [http://192.168.0.123:9835](http://192.168.123.x:9835)

All endpoints below are relative to BASE_URL.

AUTHENTICATION

The client uses a simple shared secret (password-like token) sent in an HTTP header.

Header name: X-Token
Header value: the configured token (example: Password123)

Example header:

X-Token: Password123

Notes:

* GET /health does not require authentication.
* All other endpoints listed here require the X-Token header.
* Responses are JSON (application/json; charset=utf-8).

ENDPOINTS

1. Enqueue a new YouTube URL

Request:
POST /add
Content-Type: application/json
X-Token: <token>

Body (JSON):
{"url":"[https://www.youtube.com/watch?v=bmBTMYKMSKk"}](https://www.youtube.com/watch?v=bmBTMYKMSKk%22})

curl example:
BASE_URL="[http://192.168.0.123:9835](http://192.168.0.123:9835)"
TOKEN="Password123"

curl -sS -X POST "$BASE_URL/add" 
-H "Content-Type: application/json" 
-H "X-Token: $TOKEN" 
-d '{"url":"[https://www.youtube.com/watch?v=bmBTMYKMSKk"}](https://www.youtube.com/watch?v=bmBTMYKMSKk%22})'

Success response (example):
{"ok":true,"queue_len":3}

Common error responses (examples):
Unauthorized (missing/invalid token):
{"ok":false,"error":"unauthorized"}

Invalid JSON:
{"ok":false,"error":"invalid_json"}

Invalid or non-YouTube URL:
{"ok":false,"error":"invalid_or_non_youtube_url"}

2. Health check

Used by the client to decide whether the server is reachable and operational.

Request:
GET /health

curl example:
BASE_URL="[http://192.168.0.123:9835](http://192.168.0.123:9835)"
curl -sS "$BASE_URL/health"

Response (example):
{"ok":true,"queue_len":2,"has_secret":true,"has_add_script":true}

Meaning:

* ok: basic server health flag
* queue_len: number of pending items in the queue.txt file
* has_secret: whether the server-side secret file exists
* has_add_script: whether the server-side enqueue script exists

3. Queue length

Request:
GET /queue-len
X-Token: <token>

curl example:
BASE_URL="[http://192.168.0.123:9835](http://192.168.0.123:9835)"
TOKEN="Password123"

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/queue-len"

Response (example):
{"ok":true,"queue_len":2}

4. Queue tail (peek into queued URLs)

Request:
GET /queue-tail?lines=N
X-Token: <token>

Query params:

* lines: number of lines to return (example: 50). Server may clamp the value (for example max 500).

curl example:
BASE_URL="[http://192.168.0.123:9835](http://192.168.0.123:9835)"
TOKEN="Password123"

curl -sS -H "X-Token: $TOKEN" "$BASE_URL/queue-tail?lines=50"

Response (example):
{"ok":true,"lines":50,"text":"[https://youtu.be/..."}](https://youtu.be/...})

5. Log tail (read server logs)

Request:
GET /tail?log=yt|endpoint&lines=N
X-Token: <token>

Query params:

* log:

  * yt: yt-dlp processing log
  * endpoint: enqueue endpoint log
* lines: number of lines to return (example: 120). Server may clamp the value (for example max 500).

curl examples:
BASE_URL="[http://192.168.0.123:9835](http://192.168.0.123:9835)"
TOKEN="Password123"

yt-dlp log:
curl -sS -H "X-Token: $TOKEN" "$BASE_URL/tail?log=yt&lines=120"

endpoint log:
curl -sS -H "X-Token: $TOKEN" "$BASE_URL/tail?log=endpoint&lines=120"

Response (example):
{"ok":true,"log":"yt","lines":120,"text":"==== 2026-03-03 ...\n[download] ...\n"}

SUMMARY

Implemented endpoints:

* POST /add (auth required)
* GET /health (no auth)
* GET /queue-len (auth required)
* GET /queue-tail?lines=N (auth required)
* GET /tail?log=yt|endpoint&lines=N (auth required)

Auth mechanism:

* Header-based token: X-Token: <token>
