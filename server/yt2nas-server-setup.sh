#!/usr/bin/env bash
set -euo pipefail

APP_NAME="yt2nas-server-setup"
CONFIG_FILE="/etc/yt2nas/yt2nas.conf"

BIN_DIR="/usr/local/bin"
ADD_SH="$BIN_DIR/yt2nas-add.sh"
RUN_SH="$BIN_DIR/yt2nas-run.sh"
SERVER_PY="$BIN_DIR/yt2nas_server.py"

SYSTEMD_DIR="/etc/systemd/system"
ENDPOINT_SERVICE="$SYSTEMD_DIR/yt2nas-endpoint.service"
QUEUE_SERVICE="$SYSTEMD_DIR/yt2nas-queue.service"
QUEUE_TIMER="$SYSTEMD_DIR/yt2nas-queue.timer"

now_ts() { date +"%Y%m%d_%H%M%S"; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run as root (use sudo)."
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

backup_if_exists() {
  local p="$1"
  if [[ -f "$p" ]]; then
    cp -a "$p" "${p}.bak_$(now_ts)"
  fi
}

get_default_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    echo "$SUDO_USER"
  else
    echo "${USER:-root}"
  fi
}

prompt() {
  local var_name="$1"
  local question="$2"
  local def="${3:-}"
  local val=""
  if [[ -n "$def" ]]; then
    read -r -p "${question} [default: ${def}]: " val
    val="${val:-$def}"
  else
    read -r -p "${question}: " val
  fi
  printf -v "$var_name" "%s" "$val"
}

prompt_hidden() {
  local var_name="$1"
  local question="$2"
  local val=""
  read -r -s -p "${question}: " val
  echo
  printf -v "$var_name" "%s" "$val"
}

is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }

validate_port() {
  local p="$1"
  is_number "$p" || return 1
  [[ "$p" -ge 1 && "$p" -le 65535 ]]
}

validate_cidr() {
  local c="$1"
  [[ "$c" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]
}

user_exists() { id "$1" >/dev/null 2>&1; }

user_home() {
  local u="$1"
  local h
  h="$(getent passwd "$u" | cut -d: -f6)"
  [[ -n "$h" ]] || die "Cannot determine home dir for user: $u"
  echo "$h"
}

ensure_packages() {
  apt-get update -y
  apt-get install -y --no-install-recommends \
    ffmpeg curl python3 ca-certificates ufw util-linux
}

install_ytdlp_for_user() {
  local u="$1"
  local h; h="$(user_home "$u")"
  local target="$h/.local/bin/yt-dlp"

  su - "$u" -c "mkdir -p \"$h/.local/bin\""
  su - "$u" -c "curl -L \"https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp\" -o \"$target\""
  chmod a+rx "$target"

  local bashrc="$h/.bashrc"
  local profile="$h/.profile"
  grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "$bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$bashrc"
  grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "$profile" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$profile"

  su - "$u" -c "\"$target\" --version" >/dev/null
}

write_ytdlp_config_for_user() {
  local u="$1"
  local download_dir="$2"
  local max_height="$3"
  local h; h="$(user_home "$u")"
  local cfg_dir="$h/.config/yt-dlp"
  local cfg_file="$cfg_dir/config"
  su - "$u" -c "mkdir -p \"$cfg_dir\""

  backup_if_exists "$cfg_file"
  cat >"$cfg_file" <<EOF
# yt2nas managed config

-P ${download_dir}
-o "%(uploader)s/%(upload_date>%Y-%m-%d)s - %(title)s [%(id)s].%(ext)s"
-f bv*[height<=${max_height}]+ba/b[height<=${max_height}]
--merge-output-format mkv
--download-archive ${download_dir}/.yt_archive.txt

--retries 10
--fragment-retries 10
--concurrent-fragments 4
--ignore-errors
--yes-playlist
EOF

  chown "$u:$u" "$cfg_file"
}

ensure_group_and_perms() {
  local download_dir="$1"
  local group_name="$2"
  local service_user="$3"
  local nas_user="$4"

  if ! getent group "$group_name" >/dev/null 2>&1; then
    groupadd "$group_name"
  fi

  usermod -a -G "$group_name" "$service_user"
  if [[ -n "$nas_user" ]]; then
    usermod -a -G "$group_name" "$nas_user"
  fi

  mkdir -p "$download_dir"
  chown -R "$service_user:$group_name" "$download_dir"

  chmod 2775 "$download_dir"
  chmod -R g+rwX "$download_dir"

  mkdir -p "$download_dir/.queue"
  chown -R "$service_user:$group_name" "$download_dir/.queue"
  chmod 2770 "$download_dir/.queue"
  chmod -R g+rwX "$download_dir/.queue"
}

write_queue_files() {
  local download_dir="$1"
  mkdir -p "$download_dir/.queue"
  touch "$download_dir/.queue/queue.txt"
  touch "$download_dir/.queue/archive.txt"
  touch "$download_dir/.queue/yt-dlp.log"
  touch "$download_dir/.queue/endpoint.log"
}

write_secret() {
  local download_dir="$1"
  local service_user="$2"
  local group_name="$3"
  local token="$4"
  local secret_file="$download_dir/.queue/endpoint.secret"

  backup_if_exists "$secret_file"
  printf '%s\n' "$token" >"$secret_file"
  chown "$service_user:$group_name" "$secret_file"
  chmod 600 "$secret_file"
}

write_add_script() {
  local download_dir="$1"
  backup_if_exists "$ADD_SH"
  cat >"$ADD_SH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

QUEUE_DIR="${download_dir}/.queue"
QUEUE_FILE="\$QUEUE_DIR/queue.txt"
LOCK_FILE="\$QUEUE_DIR/queue.lock"

URL="\${1:-}"

if [[ -z "\$URL" ]]; then
  echo "Missing URL" >&2
  exit 2
fi
if [[ ! "\$URL" =~ ^https?:// ]]; then
  echo "Invalid URL" >&2
  exit 2
fi

mkdir -p "\$QUEUE_DIR"
touch "\$QUEUE_FILE"

(
  flock -x 200
  printf '%s\n' "\$URL" >> "\$QUEUE_FILE"
) 200>"\$LOCK_FILE"

echo "OK"
EOF
  chmod 755 "$ADD_SH"
}

write_run_script() {
  local download_dir="$1"
  local service_user="$2"
  local ytdlp_path
  ytdlp_path="$(user_home "$service_user")/.local/bin/yt-dlp"

  backup_if_exists "$RUN_SH"
  cat >"$RUN_SH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

YTDLP="${ytdlp_path}"

QUEUE_DIR="${download_dir}/.queue"
QUEUE_FILE="\$QUEUE_DIR/queue.txt"
ARCHIVE_FILE="\$QUEUE_DIR/archive.txt"
RUN_LOCK="\$QUEUE_DIR/run.lock"
QUEUE_LOCK="\$QUEUE_DIR/queue.lock"
LOG_FILE="\$QUEUE_DIR/yt-dlp.log"

mkdir -p "\$QUEUE_DIR"
touch "\$QUEUE_FILE" "\$ARCHIVE_FILE" "\$LOG_FILE"

exec 201>"\$RUN_LOCK"
flock -n 201 || exit 0

BATCH_FILE="\$QUEUE_DIR/batch_\$(date +%Y%m%d_%H%M%S).txt"

(
  flock -x 200
  if [[ ! -s "\$QUEUE_FILE" ]]; then
    exit 0
  fi
  cp "\$QUEUE_FILE" "\$BATCH_FILE"
  : > "\$QUEUE_FILE"
) 200>"\$QUEUE_LOCK"

if [[ ! -s "\$BATCH_FILE" ]]; then
  rm -f "\$BATCH_FILE"
  exit 0
fi

{
  echo "==== \$(date) START \$BATCH_FILE ===="
  "\$YTDLP" -a "\$BATCH_FILE" --download-archive "\$ARCHIVE_FILE"
  RC=\$?
  echo "==== \$(date) END rc=\$RC ===="
  exit \$RC
} >>"\$LOG_FILE" 2>&1 || {
  (
    flock -x 200
    cat "\$BATCH_FILE" >> "\$QUEUE_FILE"
  ) 200>"\$QUEUE_LOCK"
  exit 1
}

rm -f "\$BATCH_FILE"
EOF
  chmod 755 "$RUN_SH"
}

write_server_py() {
  local download_dir="$1"
  local port="$2"
  backup_if_exists "$SERVER_PY"
  cat >"$SERVER_PY" <<EOF
#!/usr/bin/env python3
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

QUEUE_DIR = "${download_dir}/.queue"
SECRET_FILE = os.path.join(QUEUE_DIR, "endpoint.secret")
QUEUE_FILE = os.path.join(QUEUE_DIR, "queue.txt")
ENDPOINT_LOG = os.path.join(QUEUE_DIR, "endpoint.log")
YTDLP_LOG = os.path.join(QUEUE_DIR, "yt-dlp.log")
ADD_SCRIPT = "${ADD_SH}"

MAX_BODY_BYTES = 2048
PORT = int(os.environ.get("YT2NAS_PORT", "${port}"))

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

    if host == "youtu.be":
        return len(u.path.strip("/")) > 0

    path = (u.path or "").lower()
    if path.startswith("/watch"):
        q = parse_qs(u.query)
        return "v" in q and len(q["v"]) > 0
    if path.startswith("/shorts/"):
        parts = path.split("/")
        return len(parts) >= 3 and len(parts[2]) > 0
    if path.startswith("/playlist"):
        q = parse_qs(u.query)
        return "list" in q and len(q["list"]) > 0

    return True

def tail_lines(path: str, n: int) -> str:
    n = max(1, min(500, int(n)))
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            block = 4096
            data = b""
            pos = size
            while pos > 0 and data.count(b"\\n") <= n:
                read_size = block if pos - block > 0 else pos
                pos -= read_size
                f.seek(pos)
                data = f.read(read_size) + data
            lines = data.splitlines()[-n:]
        return "\\n".join(line.decode("utf-8", errors="replace") for line in lines)
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
        f.write(msg + "\\n")

class Handler(BaseHTTPRequestHandler):
    server_version = "yt2nas/1.0"

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
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.serve_forever()

if __name__ == "__main__":
    main()
EOF
  chmod 755 "$SERVER_PY"
}

write_systemd_units() {
  local service_user="$1"
  local group_name="$2"
  local download_dir="$3"
  local port="$4"
  local interval_min="$5"

  backup_if_exists "$ENDPOINT_SERVICE"
  cat >"$ENDPOINT_SERVICE" <<EOF
[Unit]
Description=YT2NAS endpoint (yt-dlp TXT queue)
After=network-online.target
Wants=network-online.target
RequiresMountsFor=${download_dir}

[Service]
Type=simple
User=${service_user}
Group=${group_name}
Environment=YT2NAS_PORT=${port}
ExecStart=/usr/bin/python3 ${SERVER_PY}
Restart=always
RestartSec=2
WorkingDirectory=${download_dir}/.queue

[Install]
WantedBy=multi-user.target
EOF

  backup_if_exists "$QUEUE_SERVICE"
  cat >"$QUEUE_SERVICE" <<EOF
[Unit]
Description=YT2NAS queue runner (yt-dlp batch)
After=network-online.target
Wants=network-online.target
RequiresMountsFor=${download_dir}

[Service]
Type=oneshot
User=${service_user}
Group=${group_name}
ExecStart=${RUN_SH}
WorkingDirectory=${download_dir}/.queue
EOF

  backup_if_exists "$QUEUE_TIMER"
  cat >"$QUEUE_TIMER" <<EOF
[Unit]
Description=Run YT2NAS queue runner every ${interval_min} minute(s)

[Timer]
OnBootSec=1min
OnUnitActiveSec=${interval_min}min
AccuracySec=15s
Unit=yt2nas-queue.service

[Install]
WantedBy=timers.target
EOF
}

save_config() {
  local download_dir="$1"
  local service_user="$2"
  local nas_user="$3"
  local group_name="$4"
  local port="$5"
  local subnet="$6"
  local interval_min="$7"
  local max_height="$8"

  mkdir -p "$(dirname "$CONFIG_FILE")"
  backup_if_exists "$CONFIG_FILE"
  cat >"$CONFIG_FILE" <<EOF
DOWNLOAD_DIR="${download_dir}"
SERVICE_USER="${service_user}"
NAS_USER="${nas_user}"
GROUP_NAME="${group_name}"
PORT="${port}"
TRUSTED_SUBNET="${subnet}"
INTERVAL_MIN="${interval_min}"
MAX_HEIGHT="${max_height}"
EOF
  chmod 600 "$CONFIG_FILE"
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] || die "Config not found: $CONFIG_FILE. Run install first."
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
}

setup_ufw() {
  local subnet="$1"
  local port="$2"

  ufw --force enable
  ufw deny "${port}/tcp" >/dev/null || true
  ufw allow from "$subnet" to any port "$port" proto tcp >/dev/null || true
}

systemd_reload_enable() {
  systemctl daemon-reload
  systemctl enable --now yt2nas-endpoint.service
  systemctl enable --now yt2nas-queue.timer
}

systemd_stop_disable() {
  systemctl disable --now yt2nas-queue.timer 2>/dev/null || true
  systemctl disable --now yt2nas-endpoint.service 2>/dev/null || true
  systemctl stop yt2nas-queue.service 2>/dev/null || true
}

health_check() {
  local port="$1"
  if command_exists curl; then
    curl -sS "http://127.0.0.1:${port}/health" || true
    echo
  fi
}

print_usage() {
  cat <<EOF
Usage:
  sudo ./${APP_NAME} install [--yes] [options]
  sudo ./${APP_NAME} update
  sudo ./${APP_NAME} status
  sudo ./${APP_NAME} uninstall [--purge]

Install options (can be given as flags, or env vars with same names):
  --service-user USER        (env: YT2NAS_SERVICE_USER)
  --nas-user USER            (env: YT2NAS_NAS_USER)
  --group GROUP              (env: YT2NAS_GROUP)
  --download-dir DIR         (env: YT2NAS_DOWNLOAD_DIR)
  --port PORT                (env: YT2NAS_PORT)
  --subnet CIDR              (env: YT2NAS_SUBNET)
  --interval MINUTES         (env: YT2NAS_INTERVAL)
  --max-height HEIGHT        (env: YT2NAS_MAX_HEIGHT)
  --token TOKEN              (env: YT2NAS_TOKEN)
  --yes                      non-interactive, fail if required values missing
EOF
}

# -------- argument parsing for install --------

INSTALL_NON_INTERACTIVE="0"
INSTALL_SERVICE_USER=""
INSTALL_NAS_USER=""
INSTALL_GROUP=""
INSTALL_DOWNLOAD_DIR=""
INSTALL_PORT=""
INSTALL_SUBNET=""
INSTALL_INTERVAL=""
INSTALL_MAX_HEIGHT=""
INSTALL_TOKEN=""

parse_install_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) INSTALL_NON_INTERACTIVE="1"; shift ;;
      --service-user) INSTALL_SERVICE_USER="${2:-}"; shift 2 ;;
      --nas-user) INSTALL_NAS_USER="${2:-}"; shift 2 ;;
      --group) INSTALL_GROUP="${2:-}"; shift 2 ;;
      --download-dir) INSTALL_DOWNLOAD_DIR="${2:-}"; shift 2 ;;
      --port) INSTALL_PORT="${2:-}"; shift 2 ;;
      --subnet) INSTALL_SUBNET="${2:-}"; shift 2 ;;
      --interval) INSTALL_INTERVAL="${2:-}"; shift 2 ;;
      --max-height) INSTALL_MAX_HEIGHT="${2:-}"; shift 2 ;;
      --token) INSTALL_TOKEN="${2:-}"; shift 2 ;;
      -h|--help) print_usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
}

get_install_value() {
  local flag_val="$1"
  local env_name="$2"
  local def_val="$3"
  local out=""
  if [[ -n "$flag_val" ]]; then
    out="$flag_val"
  elif [[ -n "${!env_name:-}" ]]; then
    out="${!env_name}"
  else
    out="$def_val"
  fi
  echo "$out"
}

install_flow() {
  need_root

  echo "YT2NAS server setup for Ubuntu"
  echo "Note: choose a download folder inside your NAS mounted path."
  echo

  local def_user; def_user="$(get_default_user)"

  local service_user nas_user group_name download_dir port subnet interval token max_height

  service_user="$(get_install_value "$INSTALL_SERVICE_USER" "YT2NAS_SERVICE_USER" "$def_user")"
  nas_user="$(get_install_value "$INSTALL_NAS_USER" "YT2NAS_NAS_USER" "")"
  group_name="$(get_install_value "$INSTALL_GROUP" "YT2NAS_GROUP" "yt2nas")"
  download_dir="$(get_install_value "$INSTALL_DOWNLOAD_DIR" "YT2NAS_DOWNLOAD_DIR" "/mnt/NAS/Youtube")"
  port="$(get_install_value "$INSTALL_PORT" "YT2NAS_PORT" "9835")"
  subnet="$(get_install_value "$INSTALL_SUBNET" "YT2NAS_SUBNET" "192.168.0.0/24")"
  interval="$(get_install_value "$INSTALL_INTERVAL" "YT2NAS_INTERVAL" "5")"
  max_height="$(get_install_value "$INSTALL_MAX_HEIGHT" "YT2NAS_MAX_HEIGHT" "2160")"
  token="$(get_install_value "$INSTALL_TOKEN" "YT2NAS_TOKEN" "")"

  if [[ "$INSTALL_NON_INTERACTIVE" == "0" ]]; then
    prompt service_user "Service Linux user (runs endpoint and downloads)" "$service_user"

    prompt nas_user "Optional second Linux user (NAS file access user), leave empty if none" "$nas_user"

    prompt group_name "Shared group name for folder permissions" "$group_name"

    prompt download_dir "Download folder (inside NAS mount)" "$download_dir"

    prompt port "Endpoint port" "$port"

    prompt subnet "Trusted subnet CIDR for UFW (LAN)" "$subnet"

    prompt interval "Queue runner interval in minutes" "$interval"

    echo "Max video height examples: 720, 1080, 2160"
    prompt max_height "Max video height" "$max_height"

    if [[ -z "$token" ]]; then
      while true; do
        prompt_hidden token "Endpoint token/password (min 4 chars)"
        [[ "${#token}" -ge 4 ]] && break
        echo "Token too short."
      done
    fi
  else
    [[ -n "$service_user" ]] || die "Missing service user (use --service-user or YT2NAS_SERVICE_USER)."
    [[ -n "$download_dir" ]] || die "Missing download dir (use --download-dir or YT2NAS_DOWNLOAD_DIR)."
    [[ -n "$port" ]] || die "Missing port (use --port or YT2NAS_PORT)."
    [[ -n "$subnet" ]] || die "Missing subnet (use --subnet or YT2NAS_SUBNET)."
    [[ -n "$interval" ]] || die "Missing interval (use --interval or YT2NAS_INTERVAL)."
    [[ -n "$max_height" ]] || die "Missing max height (use --max-height or YT2NAS_MAX_HEIGHT)."
    [[ -n "$token" ]] || die "Missing token (use --token or YT2NAS_TOKEN)."
  fi

  user_exists "$service_user" || die "User does not exist: $service_user"
  if [[ -n "$nas_user" ]]; then
    user_exists "$nas_user" || die "User does not exist: $nas_user"
  fi

  validate_port "$port" || die "Invalid port: $port"
  validate_cidr "$subnet" || die "Invalid CIDR: $subnet"
  is_number "$interval" || die "Interval must be a number"
  is_number "$max_height" || die "Max height must be a number"
  [[ "${#token}" -ge 4 ]] || die "Token too short (min 4)."

  echo
  echo "Installing packages..."
  ensure_packages

  echo "Installing yt-dlp for user: $service_user"
  install_ytdlp_for_user "$service_user"

  echo "Writing yt-dlp config..."
  write_ytdlp_config_for_user "$service_user" "$download_dir" "$max_height"

  echo "Creating folder permissions and queue files..."
  ensure_group_and_perms "$download_dir" "$group_name" "$service_user" "$nas_user"
  write_queue_files "$download_dir"
  write_secret "$download_dir" "$service_user" "$group_name" "$token"

  echo "Writing scripts..."
  write_add_script "$download_dir"
  write_run_script "$download_dir" "$service_user"
  write_server_py "$download_dir" "$port"

  echo "Writing systemd units..."
  write_systemd_units "$service_user" "$group_name" "$download_dir" "$port" "$interval"

  echo "Saving config..."
  save_config "$download_dir" "$service_user" "$nas_user" "$group_name" "$port" "$subnet" "$interval" "$max_height"

  echo "Configuring UFW..."
  setup_ufw "$subnet" "$port"

  echo "Enabling services..."
  systemd_reload_enable

  echo
  echo "Health check:"
  health_check "$port"

  echo "DONE."
  echo "Endpoint base URL: http://YOUR_SERVER_IP:${port}"
  echo "Test from LAN: curl http://YOUR_SERVER_IP:${port}/health"
}

update_flow() {
  need_root
  load_config

  echo "Updating yt-dlp for user: ${SERVICE_USER}"
  install_ytdlp_for_user "$SERVICE_USER"

  echo "Rewriting scripts and units from config..."
  ensure_group_and_perms "$DOWNLOAD_DIR" "$GROUP_NAME" "$SERVICE_USER" "${NAS_USER:-}"
  write_queue_files "$DOWNLOAD_DIR"
  write_add_script "$DOWNLOAD_DIR"
  write_run_script "$DOWNLOAD_DIR" "$SERVICE_USER"
  write_server_py "$DOWNLOAD_DIR" "$PORT"
  write_systemd_units "$SERVICE_USER" "$GROUP_NAME" "$DOWNLOAD_DIR" "$PORT" "$INTERVAL_MIN"

  echo "Refreshing UFW rules..."
  setup_ufw "$TRUSTED_SUBNET" "$PORT"

  echo "Reloading services..."
  systemctl daemon-reload
  systemctl restart yt2nas-endpoint.service
  systemctl restart yt2nas-queue.timer

  echo "DONE."
  health_check "$PORT"
}

status_flow() {
  need_root
  echo "Config: $CONFIG_FILE"
  if [[ -f "$CONFIG_FILE" ]]; then
    cat "$CONFIG_FILE"
  else
    echo "No config found."
  fi
  echo
  systemctl status yt2nas-endpoint.service --no-pager || true
  echo
  systemctl status yt2nas-queue.timer --no-pager || true
  echo
  ufw status verbose || true
}

uninstall_flow() {
  need_root
  local purge="0"
  if [[ "${1:-}" == "--purge" ]]; then
    purge="1"
  elif [[ -n "${1:-}" ]]; then
    die "Unknown uninstall option: $1"
  fi

  local download_dir=""
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    download_dir="${DOWNLOAD_DIR:-}"
  fi

  echo "Stopping services..."
  systemd_stop_disable

  echo "Removing systemd units..."
  rm -f "$ENDPOINT_SERVICE" "$QUEUE_SERVICE" "$QUEUE_TIMER"
  systemctl daemon-reload

  echo "Removing scripts..."
  rm -f "$ADD_SH" "$RUN_SH" "$SERVER_PY"

  echo "Removing config..."
  rm -f "$CONFIG_FILE"

  if [[ "$purge" == "1" ]]; then
    if [[ -n "$download_dir" && -d "$download_dir/.queue" ]]; then
      echo "Purging queue folder: $download_dir/.queue"
      rm -rf "$download_dir/.queue"
    else
      echo "Purge requested, but queue folder not found (or config missing)."
    fi
  fi

  echo "Note: download folder videos are NOT deleted."
  echo "DONE."
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    install)
      parse_install_args "$@"
      install_flow
      ;;
    update) update_flow ;;
    status) status_flow ;;
    uninstall) uninstall_flow "${1:-}" ;;
    -h|--help|"") print_usage; exit 0 ;;
    *) die "Unknown command: $cmd" ;;
  esac
}

main "$@"
