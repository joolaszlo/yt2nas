# YT2NAS

1.) [NAS] install ffmpeg
```
sudo apt install ffmpeg
```

2.) [NAS] install yt-dlp
```
mkdir -p ~/.local/bin
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ~/.local/bin/yt-dlp
chmod a+rx ~/.local/bin/yt-dlp
~/.local/bin/yt-dlp --version
```

then adding PATH:
```
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.profile
source ~/.bashrc
```

3.) [NAS] configuring yt-dlp

3/1.) create folder for config:
```
mkdir -p ~/.config/yt-dlp
nano ~/.config/yt-dlp/config
```
3/2.) then paste this to the opened file:
```
# here you can specify where to save your downloads.
-P /mnt/NAS/Youtube

# specifying the file name; for other options, see yt-dlp (channel / date - title [id].ext)
-o "%(uploader)s/%(upload_date>%Y-%m-%d)s - %(title)s [%(id)s].%(ext)s"

# it downloads in the best possible quality, but the maximum quality can be specified here; now it's 4k
-f bv*[height<=2160]+ba/b[height<=2160]
--merge-output-format mkv

# to avoid repeated downloads, an archive is necessary.
--download-archive /mnt/NAS/Youtube/.yt_archive.txt

# download settings
--retries 10
--fragment-retries 10
--concurrent-fragments 4

# error handling
--ignore-errors

# playlist enabling
--yes-playlist

3/3.) create the download folder:

mkdir -p /mnt/NAS/Youtube

3/4.) if you use another user to access your NAS, add them so that they can also manage this folder:

sudo chown -R your_username:your_username /mnt/NAS/Youtube
sudo chmod -R u+rwX /mnt/NAS/Youtube
```

4.) [NAS] install deno:
```
curl -fsSL https://deno.land/install.sh | sh
echo 'export DENO_INSTALL="$HOME/.deno"' >> ~/.bashrc
echo 'export PATH="$DENO_INSTALL/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
deno --version
```

5.) [NAS] make the queue:

5/1.) make files:
```
mkdir -p /mnt/NAS/Youtube/.queue
touch /mnt/NAS/Youtube/.queue/queue.txt
touch /mnt/NAS/Youtube/.queue/archive.txt
touch /mnt/NAS/Youtube/.queue/yt-dlp.log
```
5/2). create the queue script:
```
sudo nano /usr/local/bin/ytqueue-add.sh
```
paste this code in it:
```
#!/usr/bin/env bash
set -euo pipefail

QUEUE_DIR="/mnt/NAS/Youtube/.queue"
QUEUE_FILE="$QUEUE_DIR/queue.txt"
LOCK_FILE="$QUEUE_DIR/queue.lock"

URL="${1:-}"

# validation
if [[ -z "$URL" ]]; then
  echo "Missing URL" >&2
  exit 2
fi
if [[ ! "$URL" =~ ^https?:// ]]; then
  echo "Invalid URL" >&2
  exit 2
fi

mkdir -p "$QUEUE_DIR"
touch "$QUEUE_FILE"

(
  flock -x 200
  printf '%s\n' "$URL" >> "$QUEUE_FILE"
) 200>"$LOCK_FILE"

echo "OK"
```
5/3.) give permission:
```
sudo chmod +x /usr/local/bin/ytqueue-add.sh
```

6.) [NAS] queue automation:

6/1.) make the file:
```
sudo nano /usr/local/bin/ytqueue-run.sh
```
paste this code in it:
```
#!/usr/bin/env bash
set -euo pipefail

YTDLP="/home/your_username/.local/bin/yt-dlp"

QUEUE_DIR="/mnt/NAS/Youtube/.queue"
QUEUE_FILE="$QUEUE_DIR/queue.txt"
ARCHIVE_FILE="$QUEUE_DIR/archive.txt"
RUN_LOCK="$QUEUE_DIR/run.lock"
QUEUE_LOCK="$QUEUE_DIR/queue.lock"
LOG_FILE="$QUEUE_DIR/yt-dlp.log"

mkdir -p "$QUEUE_DIR"
touch "$QUEUE_FILE" "$ARCHIVE_FILE" "$LOG_FILE"

exec 201>"$RUN_LOCK"
flock -n 201 || exit 0

BATCH_FILE="$QUEUE_DIR/batch_$(date +%Y%m%d_%H%M%S).txt"

(
  flock -x 200
  if [[ ! -s "$QUEUE_FILE" ]]; then
    exit 0
  fi
  cp "$QUEUE_FILE" "$BATCH_FILE"
  : > "$QUEUE_FILE"
) 200>"$QUEUE_LOCK"

if [[ ! -s "$BATCH_FILE" ]]; then
  rm -f "$BATCH_FILE"
  exit 0
fi

{
  echo "==== $(date) START $BATCH_FILE ===="
  "$YTDLP" -a "$BATCH_FILE" --download-archive "$ARCHIVE_FILE"
  RC=$?
  echo "==== $(date) END rc=$RC ===="
  exit $RC
} >>"$LOG_FILE" 2>&1 || {

  (
    flock -x 200
    cat "$BATCH_FILE" >> "$QUEUE_FILE"
  ) 200>"$QUEUE_LOCK"
  exit 1
}

rm -f "$BATCH_FILE"

6/2.) give permission:

sudo chmod +x /usr/local/bin/ytqueue-run.sh

6/3.) create a cron job:

crontab -e

*/5 * * * * /usr/local/bin/ytqueue-run.sh (this runs every 5 minutes, but you can set it to whatever you like.)
```

7.) [NAS] create the endpoint:

7/1.) create password for the endpoint:
```
sudo mkdir -p /mnt/NAS/Youtube/.queue
echo "your_password" | sudo tee /mnt/NAS/Youtube/.queue/endpoint.secret >/dev/null
sudo chown your_username:your_username /mnt/NAS/Youtube/.queue/endpoint.secret
sudo chmod 600 /mnt/NAS/Youtube/.queue/endpoint.secret
```
7/2.) make the file:
```
sudo nano /usr/local/bin/ytqueue_server.py
```
paste this code in it:
```
#!/usr/bin/env python3
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

QUEUE_DIR = "/mnt/NAS/Youtube/.queue"
SECRET_FILE = os.path.join(QUEUE_DIR, "endpoint.secret")
QUEUE_FILE = os.path.join(QUEUE_DIR, "queue.txt")
ENDPOINT_LOG = os.path.join(QUEUE_DIR, "endpoint.log")
YTDLP_LOG = os.path.join(QUEUE_DIR, "yt-dlp.log")
ADD_SCRIPT = "/usr/local/bin/ytqueue-add.sh"

MAX_BODY_BYTES = 2048

ALLOWED_HOSTS = {
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be",
}

def read_secret() -> str:
    try:
        with open(SECRET_FILE, "r", encoding="utf-8") as f:
            return f.read().strip()
    except FileNotFoundError:
        return ""

def is_allowed_youtube_url(url: str) -> bool:
    try:
        u = urlparse(url.strip())
    except Exception:
        return False

    if u.scheme not in ("http", "https"):
        return False
    host = (u.hostname or "").lower()
    if host not in ALLOWED_HOSTS:
        return False

    # youtu.be/<id>
    if host == "youtu.be":
        return len(u.path.strip("/")) > 0

    # youtube.com/watch?v=..., /shorts/..., /playlist?list=...
    path = (u.path or "").lower()
    if path.startswith("/watch"):
        q = parse_qs(u.query)
        return "v" in q and len(q["v"]) > 0
    if path.startswith("/shorts/"):
        return len(path.split("/")) >= 3 and len(path.split("/")[2]) > 0
    if path.startswith("/playlist"):
        q = parse_qs(u.query)
        return "list" in q and len(q["list"]) > 0
    if path.startswith("/@") or path.startswith("/channel/") or path.startswith("/c/"):
        return True
    if path.startswith("/feed/") or path.startswith("/results"):
        return True

    return True

def tail_lines(path: str, n: int) -> str:
    if n < 1:
        n = 1
    if n > 500:
        n = 500
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            block = 4096
            data = b""
            pos = size
            while pos > 0 and data.count(b"\n") <= n:
                read_size = block if pos - block > 0 else pos
                pos -= read_size
                f.seek(pos)
                data = f.read(read_size) + data
            lines = data.splitlines()[-n:]
        return "\n".join(line.decode("utf-8", errors="replace") for line in lines)
    except FileNotFoundError:
        return ""
    except Exception as e:
        return f"ERROR reading log: {e}"

def count_queue_lines() -> int:
    try:
        with open(QUEUE_FILE, "r", encoding="utf-8") as f:
            return sum(1 for _ in f)
    except FileNotFoundError:
        return 0

def append_endpoint_log(msg: str) -> None:
    os.makedirs(QUEUE_DIR, exist_ok=True)
    with open(ENDPOINT_LOG, "a", encoding="utf-8") as f:
        f.write(msg + "\n")

class Handler(BaseHTTPRequestHandler):
    server_version = "ytqueue/1.0"

    def _json(self, code: int, obj: dict):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth_ok(self) -> bool:
        secret = read_secret()
        if not secret:
            return False
        token = self.headers.get("X-Token", "")
        return token == secret

    def _require_auth(self) -> bool:
        if self._auth_ok():
            return True
        self._json(401, {"ok": False, "error": "unauthorized"})
        return False

    def do_GET(self):
        if self.path.startswith("/health"):
            ok = bool(read_secret()) and os.path.exists(ADD_SCRIPT)
            self._json(200, {
                "ok": ok,
                "queue_len": count_queue_lines(),
                "has_secret": bool(read_secret()),
                "has_add_script": os.path.exists(ADD_SCRIPT),
            })
            return

        if not self._require_auth():
            return

        if self.path.startswith("/queue-len"):
            self._json(200, {"ok": True, "queue_len": count_queue_lines()})
            return

        if self.path.startswith("/queue-tail"):
            qs = parse_qs(urlparse(self.path).query)
            n = int(qs.get("lines", ["50"])[0])
            txt = tail_lines(QUEUE_FILE, n)
            self._json(200, {"ok": True, "lines": n, "text": txt})
            return

        if self.path.startswith("/tail"):
            qs = parse_qs(urlparse(self.path).query)
            n = int(qs.get("lines", ["120"])[0])
            which = qs.get("log", ["yt"])[0].lower()
            path = YTDLP_LOG if which in ("yt", "ytdlp") else ENDPOINT_LOG
            txt = tail_lines(path, n)
            self._json(200, {"ok": True, "log": which, "lines": n, "text": txt})
            return

        self._json(404, {"ok": False, "error": "not_found"})

    def do_POST(self):
        if self.path.startswith("/add"):
            if not self._require_auth():
                return

            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_BODY_BYTES:
                self._json(400, {"ok": False, "error": "invalid_body_size"})
                return

            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw.decode("utf-8"))
            except Exception:
                self._json(400, {"ok": False, "error": "invalid_json"})
                return

            url = (payload.get("url") or "").strip()
            if not url or not is_allowed_youtube_url(url):
                self._json(400, {"ok": False, "error": "invalid_or_non_youtube_url"})
                return

            try:
                r = subprocess.run([ADD_SCRIPT, url], capture_output=True, text=True)
                append_endpoint_log(f"ADD rc={r.returncode} url={url}")
                if r.returncode != 0:
                    self._json(500, {"ok": False, "error": "enqueue_failed", "details": r.stderr.strip()})
                    return
            except Exception as e:
                self._json(500, {"ok": False, "error": "enqueue_exception", "details": str(e)})
                return

            self._json(200, {"ok": True, "queue_len": count_queue_lines()})
            return

        self._json(404, {"ok": False, "error": "not_found"})

    def log_message(self, format, *args):
        return

def main():
    os.makedirs(QUEUE_DIR, exist_ok=True)
    server = ThreadingHTTPServer(("0.0.0.0", 9835), Handler)
    server.serve_forever()

if __name__ == "__main__":
    main()
```
7/3.) give permission:
```
sudo chmod 755 /usr/local/bin/ytqueue_server.py
```
7/4.) create the service:
```
sudo nano /etc/systemd/system/ytqueue-endpoint.service
```
paste this code in it:
```
[Unit]
Description=yt-dlp TXT queue endpoint
After=network-online.target
Wants=network-online.target
RequiresMountsFor=/mnt/NAS/Youtube

[Service]
Type=simple
User=gebana
Group=gebana
ExecStart=/usr/bin/python3 /usr/local/bin/ytqueue_server.py
Restart=always
RestartSec=2
WorkingDirectory=/mnt/NAS/Youtube/.queue

[Install]
WantedBy=multi-user.target

7/5.) activate the service:

sudo systemctl daemon-reload
sudo systemctl enable --now ytqueue-endpoint.service
sudo systemctl status ytqueue-endpoint.service --no-pager
```

8.) [NAS] enabling port:
```
sudo ufw allow from 192.168.0.0/24 to any port 9835 proto tcp
sudo ufw deny 9835/tcp

```

9.) [PC] Tampermonkey script:

9/1.) install the Tampermonkey browser extension.

9/2.) add this to the new script:
```
first change "YOUR_LOCAL_IP" to your local ip!!!

// ==UserScript==
// @name         YouTube -> NAS ytqueue
// @namespace    ytqueue
// @version      1.0
// @description  Queue YouTube URLs to NAS yt-dlp TXT queue endpoint
// @match        https://www.youtube.com/*
// @match        https://youtu.be/*
// @grant        GM_xmlhttpRequest
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_registerMenuCommand
// @connect      YOUR_LOCAL_IP
// ==/UserScript==

(function () {
  'use strict';

  const DEFAULT_ENDPOINT = 'http://YOUR_LOCAL_IP:9835';
  const KEY_ENDPOINT = 'ytqueue_endpoint';
  const KEY_TOKEN = 'ytqueue_token';

  function getEndpoint() {
    return GM_getValue(KEY_ENDPOINT, DEFAULT_ENDPOINT).replace(/\/+$/, '');
  }

  function getToken() {
    return GM_getValue(KEY_TOKEN, '');
  }

  function setEndpointInteractive() {
    const cur = getEndpoint();
    const next = prompt('Endpoint base URL (pl. http://YOUR_LOCAL_IP:9835):', cur);
    if (next && /^https?:\/\/[^ ]+$/.test(next.trim())) {
      GM_setValue(KEY_ENDPOINT, next.trim().replace(/\/+$/, ''));
      toast('Endpoint mentve.');
    } else if (next !== null) {
      toast('Érvénytelen endpoint.');
    }
  }

  function setTokenInteractive() {
    const cur = getToken();
    const next = prompt('password:', cur);
    if (next && next.trim().length >= 4) {
      GM_setValue(KEY_TOKEN, next.trim());
      toast('Jelszó mentve.');
    } else if (next !== null) {
      toast('wrong password');
    }
  }

  GM_registerMenuCommand('ytqueue: Set endpoint', setEndpointInteractive);
  GM_registerMenuCommand('ytqueue: Set token', setTokenInteractive);

  function toast(msg) {
    const id = 'ytqueue_toast';
    let el = document.getElementById(id);
    if (!el) {
      el = document.createElement('div');
      el.id = id;
      el.style.position = 'fixed';
      el.style.right = '16px';
      el.style.bottom = '16px';
      el.style.zIndex = '999999';
      el.style.padding = '10px 12px';
      el.style.borderRadius = '8px';
      el.style.background = 'rgba(0,0,0,0.85)';
      el.style.color = '#fff';
      el.style.fontSize = '13px';
      el.style.maxWidth = '320px';
      el.style.boxShadow = '0 6px 18px rgba(0,0,0,0.35)';
      document.documentElement.appendChild(el);
    }
    el.textContent = msg;
    el.style.opacity = '1';
    clearTimeout(el._t);
    el._t = setTimeout(() => { el.style.opacity = '0'; }, 2500);
  }

  function enqueueCurrentUrl() {
    const endpoint = getEndpoint();
    const token = getToken();

    if (!token) {
      toast('Please add your password. Tampermonkey: "ytqueue: Set password"');
      return;
    }

    const url = location.href;

    GM_xmlhttpRequest({
      method: 'POST',
      url: endpoint + '/add',
      headers: {
        'Content-Type': 'application/json',
        'X-Token': token
      },
      data: JSON.stringify({ url }),
      timeout: 15000,
      onload: (resp) => {
        let data = null;
        try { data = JSON.parse(resp.responseText || '{}'); } catch (_) {}
        if (resp.status >= 200 && resp.status < 300 && data && data.ok) {
          const ql = typeof data.queue_len === 'number' ? data.queue_len : '?';
          toast('Queue OK. queue_len=' + ql);
        } else if (resp.status === 401) {
          toast('401 unauthorized. Wrong password.');
        } else {
          const err = (data && (data.error || data.details)) ? (data.error + (data.details ? (': ' + data.details) : '')) : 'error';
          toast('Error: ' + resp.status + ' ' + err);
        }
      },
      ontimeout: () => toast('Timeout.'),
      onerror: () => toast('Network error')
    });
  }

  function makeButton(id, text) {
    const btn = document.createElement('button');
    btn.id = id;
    btn.type = 'button';
    btn.textContent = text;
    btn.style.cursor = 'pointer';
    btn.style.padding = '8px 10px';
    btn.style.borderRadius = '18px';
    btn.style.border = '1px solid rgba(255,255,255,0.2)';
    btn.style.background = 'rgba(255,255,255,0.08)';
    btn.style.color = 'var(--yt-spec-text-primary, #fff)';
    btn.style.fontSize = '12px';
    btn.style.marginLeft = '8px';
    btn.addEventListener('click', enqueueCurrentUrl);
    return btn;
  }

  function ensureWatchPageButton() {
    const id = 'ytqueue_btn_watch';
    if (document.getElementById(id)) return;

    // Watch page gombsor: #top-level-buttons-computed
    const container =
      document.querySelector('ytd-watch-metadata #top-level-buttons-computed') ||
      document.querySelector('ytd-video-primary-info-renderer #top-level-buttons-computed');

    if (!container) return;

    const btn = makeButton(id, 'QUEUE 💾 NAS');
    container.appendChild(btn);
  }

  function ensureFloatingButton() {
    const id = 'ytqueue_btn_float';
    if (document.getElementById(id)) return;

    const btn = makeButton(id, 'QUEUE');
    btn.style.position = 'fixed';
    btn.style.right = '16px';
    btn.style.bottom = '64px';
    btn.style.zIndex = '999999';
    btn.style.padding = '10px 12px';
    btn.style.borderRadius = '22px';
    btn.style.background = 'rgba(0,0,0,0.65)';
    btn.style.border = '1px solid rgba(255,255,255,0.25)';
    document.documentElement.appendChild(btn);
  }

  function refreshButtons() {
    ensureWatchPageButton();
    ensureFloatingButton();
  }

  setInterval(refreshButtons, 1500);

  const mo = new MutationObserver(() => refreshButtons());
  mo.observe(document.documentElement, { childList: true, subtree: true });

  toast('ytqueue ready.');
})();
```

10.) [Android] install YT2NAS app to your phone
