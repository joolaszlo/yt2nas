#!/usr/bin/env bash
set -euo pipefail

APP_NAME="yt2nas-server"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SERVER_PY="$SCRIPT_DIR/yt2nas_server.py"

INSTALL_DIR="/opt/yt2nas-server"
INSTALLED_SERVER_PY="$INSTALL_DIR/yt2nas_server.py"
ENV_FILE="/etc/yt2nas-server.env"
LEGACY_CONFIG_FILE="/etc/yt2nas/yt2nas.conf"

BIN_DIR="/usr/local/bin"
ADD_SH="$BIN_DIR/yt2nas-add.sh"
RUN_SH="$BIN_DIR/yt2nas-run.sh"

SYSTEMD_DIR="/etc/systemd/system"
SERVER_SERVICE="$SYSTEMD_DIR/yt2nas-server.service"
LEGACY_ENDPOINT_SERVICE="$SYSTEMD_DIR/yt2nas-endpoint.service"
QUEUE_SERVICE="$SYSTEMD_DIR/yt2nas-queue.service"
QUEUE_TIMER="$SYSTEMD_DIR/yt2nas-queue.timer"

DEFAULT_DOWNLOAD_DIR="/mnt/NAS/Youtube"
DEFAULT_PORT="9835"
DEFAULT_GROUP="yt2nas"
DEFAULT_SUBNET="192.168.0.0/24"
DEFAULT_INTERVAL="5"
DEFAULT_MAX_HEIGHT="2160"

PYTHON_BIN=""

now_ts() { date +"%Y%m%d_%H%M%S"; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Run as root (use sudo)."
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }
is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }
user_exists() { id "$1" >/dev/null 2>&1; }

backup_if_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    cp -a "$path" "${path}.bak_$(now_ts)"
  fi
}

get_default_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    echo "$SUDO_USER"
  else
    echo ""
  fi
}

find_python() {
  if command_exists python3; then
    PYTHON_BIN="$(command -v python3)"
  elif command_exists python; then
    PYTHON_BIN="$(command -v python)"
  else
    cat >&2 <<EOF
ERROR: Python is required but was not found.

Install Python 3 first, then rerun this installer. On Ubuntu:
  sudo apt update
  sudo apt install python3
EOF
    exit 1
  fi

  "$PYTHON_BIN" - <<'PY' || die "Python 3 is required. Found: $PYTHON_BIN"
import sys
raise SystemExit(0 if sys.version_info >= (3, 9) else 1)
PY
}

generate_token() {
  "$PYTHON_BIN" - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
}

prompt() {
  local var_name="$1"
  local question="$2"
  local default_value="${3:-}"
  local value=""

  if [[ -n "$default_value" ]]; then
    read -r -p "${question} [default: ${default_value}]: " value
    value="${value:-$default_value}"
  else
    read -r -p "${question}: " value
  fi

  printf -v "$var_name" "%s" "$value"
}

prompt_hidden_optional() {
  local var_name="$1"
  local question="$2"
  local value=""

  read -r -s -p "${question}: " value
  echo
  printf -v "$var_name" "%s" "$value"
}

validate_port() {
  local port="$1"
  is_number "$port" || return 1
  [[ "$port" -ge 1 && "$port" -le 65535 ]]
}

validate_cidr() {
  local cidr="$1"
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]
}

validate_absolute_path() {
  local path="$1"
  [[ "$path" == /* && "$path" != "/" ]]
}

user_home() {
  local user="$1"
  local home
  home="$(getent passwd "$user" | cut -d: -f6)"
  [[ -n "$home" ]] || die "Cannot determine home directory for user: $user"
  echo "$home"
}

quote_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

install_existing_packages() {
  if ! command_exists apt-get; then
    echo "Skipping package install because apt-get was not found."
    return
  fi

  apt-get update -y
  apt-get install -y --no-install-recommends \
    ffmpeg curl ca-certificates ufw util-linux
}

install_ytdlp_for_user() {
  local run_user="$1"
  local home
  local target

  home="$(user_home "$run_user")"
  target="$home/.local/bin/yt-dlp"

  command_exists curl || die "curl is required to install yt-dlp."

  su - "$run_user" -c "mkdir -p \"$home/.local/bin\""
  su - "$run_user" -c "curl -L \"https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp\" -o \"$target\""
  chmod a+rx "$target"

  grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "$home/.bashrc" 2>/dev/null || \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$home/.bashrc"
  grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "$home/.profile" 2>/dev/null || \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$home/.profile"

  su - "$run_user" -c "\"$target\" --version" >/dev/null
}

write_ytdlp_config_for_user() {
  local run_user="$1"
  local download_dir="$2"
  local max_height="$3"
  local home
  local config_dir
  local config_file

  home="$(user_home "$run_user")"
  config_dir="$home/.config/yt-dlp"
  config_file="$config_dir/config"

  su - "$run_user" -c "mkdir -p \"$config_dir\""
  backup_if_exists "$config_file"

  cat >"$config_file" <<EOF
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

  chown "$run_user:$run_user" "$config_file"
}

ensure_group_and_permissions() {
  local download_dir="$1"
  local group_name="$2"
  local run_user="$3"
  local nas_user="$4"

  if ! getent group "$group_name" >/dev/null 2>&1; then
    groupadd "$group_name"
  fi

  usermod -a -G "$group_name" "$run_user"
  if [[ -n "$nas_user" ]]; then
    usermod -a -G "$group_name" "$nas_user"
  fi

  mkdir -p "$download_dir/.queue"
  chown -R "$run_user:$group_name" "$download_dir"
  chmod 2775 "$download_dir"
  chmod -R g+rwX "$download_dir"
  chmod 2770 "$download_dir/.queue"
}

write_queue_files() {
  local download_dir="$1"
  local group_name="$2"
  local run_user="$3"
  local queue_dir="$download_dir/.queue"

  mkdir -p "$queue_dir"
  touch "$queue_dir/queue.txt" "$queue_dir/archive.txt" "$queue_dir/yt-dlp.log" "$queue_dir/endpoint.log"
  chown -R "$run_user:$group_name" "$queue_dir"
  chmod 2770 "$queue_dir"
  chmod g+rw "$queue_dir/queue.txt" "$queue_dir/archive.txt" "$queue_dir/yt-dlp.log" "$queue_dir/endpoint.log"
}

write_secret_file() {
  local download_dir="$1"
  local run_user="$2"
  local group_name="$3"
  local token="$4"
  local secret_file="$download_dir/.queue/endpoint.secret"

  backup_if_exists "$secret_file"
  printf '%s\n' "$token" >"$secret_file"
  chown "$run_user:$group_name" "$secret_file"
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
  local run_user="$2"
  local ytdlp_path

  ytdlp_path="$(user_home "$run_user")/.local/bin/yt-dlp"
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

install_server_file() {
  [[ -f "$SOURCE_SERVER_PY" ]] || die "Missing server module: $SOURCE_SERVER_PY"

  install -d -m 755 "$INSTALL_DIR"
  backup_if_exists "$INSTALLED_SERVER_PY"
  install -m 755 "$SOURCE_SERVER_PY" "$INSTALLED_SERVER_PY"
}

write_env_file() {
  local run_user="$1"
  local download_dir="$2"
  local port="$3"
  local token="$4"
  local group_name="$5"
  local nas_user="$6"
  local subnet="$7"
  local interval="$8"
  local max_height="$9"

  backup_if_exists "$ENV_FILE"
  cat >"$ENV_FILE" <<EOF
YT2NAS_RUN_USER=$(quote_env_value "$run_user")
YT2NAS_DOWNLOAD_DIR=$(quote_env_value "$download_dir")
YT2NAS_PORT=$(quote_env_value "$port")
YT2NAS_TOKEN=$(quote_env_value "$token")
YT2NAS_GROUP=$(quote_env_value "$group_name")
YT2NAS_NAS_USER=$(quote_env_value "$nas_user")
YT2NAS_SUBNET=$(quote_env_value "$subnet")
YT2NAS_INTERVAL=$(quote_env_value "$interval")
YT2NAS_MAX_HEIGHT=$(quote_env_value "$max_height")
YT2NAS_ADD_SCRIPT=$(quote_env_value "$ADD_SH")
YT2NAS_SECRET_FILE=$(quote_env_value "$download_dir/.queue/endpoint.secret")
EOF

  chown root:root "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

write_legacy_config_file() {
  local run_user="$1"
  local download_dir="$2"
  local port="$3"
  local group_name="$4"
  local nas_user="$5"
  local subnet="$6"
  local interval="$7"
  local max_height="$8"

  mkdir -p "$(dirname "$LEGACY_CONFIG_FILE")"
  backup_if_exists "$LEGACY_CONFIG_FILE"
  cat >"$LEGACY_CONFIG_FILE" <<EOF
DOWNLOAD_DIR="${download_dir}"
SERVICE_USER="${run_user}"
NAS_USER="${nas_user}"
GROUP_NAME="${group_name}"
PORT="${port}"
TRUSTED_SUBNET="${subnet}"
INTERVAL_MIN="${interval}"
MAX_HEIGHT="${max_height}"
EOF

  chown root:root "$LEGACY_CONFIG_FILE"
  chmod 600 "$LEGACY_CONFIG_FILE"
}

write_systemd_units() {
  local run_user="$1"
  local group_name="$2"
  local download_dir="$3"
  local interval="$4"

  backup_if_exists "$SERVER_SERVICE"
  cat >"$SERVER_SERVICE" <<EOF
[Unit]
Description=YT2NAS server
After=network-online.target
Wants=network-online.target
RequiresMountsFor=${download_dir}

[Service]
Type=simple
User=${run_user}
Group=${group_name}
EnvironmentFile=${ENV_FILE}
ExecStart=${PYTHON_BIN} ${INSTALLED_SERVER_PY}
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
User=${run_user}
Group=${group_name}
ExecStart=${RUN_SH}
WorkingDirectory=${download_dir}/.queue
EOF

  backup_if_exists "$QUEUE_TIMER"
  cat >"$QUEUE_TIMER" <<EOF
[Unit]
Description=Run YT2NAS queue runner every ${interval} minute(s)

[Timer]
OnBootSec=1min
OnUnitActiveSec=${interval}min
AccuracySec=15s
Unit=yt2nas-queue.service

[Install]
WantedBy=timers.target
EOF
}

setup_ufw() {
  local subnet="$1"
  local port="$2"

  command_exists ufw || {
    echo "Skipping UFW configuration because ufw was not found."
    return
  }

  ufw --force enable
  ufw deny "${port}/tcp" >/dev/null || true
  ufw allow from "$subnet" to any port "$port" proto tcp >/dev/null || true
}

systemd_reload_enable() {
  systemctl daemon-reload
  systemctl disable --now yt2nas-endpoint.service 2>/dev/null || true
  systemctl enable --now yt2nas-server.service
  systemctl enable --now yt2nas-queue.timer
}

systemd_stop_disable() {
  systemctl disable --now yt2nas-queue.timer 2>/dev/null || true
  systemctl disable --now yt2nas-server.service 2>/dev/null || true
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
  sudo ./server/install.sh install [--yes] [options]
  sudo ./server/install.sh update
  sudo ./server/install.sh status
  sudo ./server/install.sh uninstall [--purge]

Install options can also be supplied with matching environment variables:
  --run-user USER         env: RUN_USER or YT2NAS_RUN_USER
  --service-user USER     legacy alias for --run-user
  --download-dir DIR      env: DOWNLOAD_DIR or YT2NAS_DOWNLOAD_DIR
  --port PORT             env: PORT or YT2NAS_PORT
  --token TOKEN           env: TOKEN or YT2NAS_TOKEN

Compatibility options:
  --nas-user USER         env: YT2NAS_NAS_USER
  --group GROUP           env: YT2NAS_GROUP
  --subnet CIDR           env: YT2NAS_SUBNET
  --interval MINUTES      env: YT2NAS_INTERVAL
  --max-height HEIGHT     env: YT2NAS_MAX_HEIGHT
  --yes                   non-interactive; token is generated if omitted
EOF
}

INSTALL_NON_INTERACTIVE="0"
INSTALL_RUN_USER=""
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
      --run-user|--service-user) INSTALL_RUN_USER="${2:-}"; shift 2 ;;
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

first_non_empty() {
  local value
  for value in "$@"; do
    if [[ -n "$value" ]]; then
      echo "$value"
      return
    fi
  done
}

collect_install_values() {
  local default_user
  default_user="$(get_default_user)"

  RUN_USER="$(first_non_empty "$INSTALL_RUN_USER" "${RUN_USER:-}" "${YT2NAS_RUN_USER:-}" "${YT2NAS_SERVICE_USER:-}" "$default_user")"
  NAS_USER="$(first_non_empty "$INSTALL_NAS_USER" "${YT2NAS_NAS_USER:-}")"
  GROUP_NAME="$(first_non_empty "$INSTALL_GROUP" "${YT2NAS_GROUP:-}" "$DEFAULT_GROUP")"
  DOWNLOAD_DIR="$(first_non_empty "$INSTALL_DOWNLOAD_DIR" "${DOWNLOAD_DIR:-}" "${YT2NAS_DOWNLOAD_DIR:-}" "$DEFAULT_DOWNLOAD_DIR")"
  PORT="$(first_non_empty "$INSTALL_PORT" "${PORT:-}" "${YT2NAS_PORT:-}" "$DEFAULT_PORT")"
  SUBNET="$(first_non_empty "$INSTALL_SUBNET" "${YT2NAS_SUBNET:-}" "$DEFAULT_SUBNET")"
  INTERVAL="$(first_non_empty "$INSTALL_INTERVAL" "${YT2NAS_INTERVAL:-}" "$DEFAULT_INTERVAL")"
  MAX_HEIGHT="$(first_non_empty "$INSTALL_MAX_HEIGHT" "${YT2NAS_MAX_HEIGHT:-}" "$DEFAULT_MAX_HEIGHT")"
  TOKEN_VALUE="$(first_non_empty "$INSTALL_TOKEN" "${TOKEN:-}" "${YT2NAS_TOKEN:-}")"
}

validate_install_values() {
  [[ -n "$RUN_USER" ]] || die "RUN_USER is required."
  [[ "$RUN_USER" != "root" ]] || die "RUN_USER must be a non-root user."
  user_exists "$RUN_USER" || die "User does not exist: $RUN_USER"

  if [[ -n "$NAS_USER" ]]; then
    user_exists "$NAS_USER" || die "NAS user does not exist: $NAS_USER"
  fi

  validate_absolute_path "$DOWNLOAD_DIR" || die "DOWNLOAD_DIR must be an absolute path: $DOWNLOAD_DIR"
  validate_port "$PORT" || die "Invalid PORT: $PORT"
  validate_cidr "$SUBNET" || die "Invalid subnet CIDR: $SUBNET"
  is_number "$INTERVAL" || die "Interval must be a number: $INTERVAL"
  is_number "$MAX_HEIGHT" || die "Max height must be a number: $MAX_HEIGHT"

  if [[ -n "$TOKEN_VALUE" && "${#TOKEN_VALUE}" -lt 4 ]]; then
    die "TOKEN must be at least 4 characters."
  fi
}

install_flow() {
  need_root
  find_python
  collect_install_values

  echo "YT2NAS server installer"
  echo "Python: $PYTHON_BIN"
  echo

  if [[ "$INSTALL_NON_INTERACTIVE" == "0" ]]; then
    local prompted_token=""
    prompt RUN_USER "RUN_USER, the non-root Linux user that runs the server" "$RUN_USER"
    prompt DOWNLOAD_DIR "DOWNLOAD_DIR, media root folder" "$DOWNLOAD_DIR"
    prompt PORT "PORT" "$PORT"
    prompt_hidden_optional prompted_token "TOKEN (leave empty to keep supplied token or generate one)"
    if [[ -n "$prompted_token" || -z "$TOKEN_VALUE" ]]; then
      TOKEN_VALUE="$prompted_token"
    fi
  fi

  if [[ -z "$TOKEN_VALUE" ]]; then
    TOKEN_VALUE="$(generate_token)"
  fi

  validate_install_values

  echo "Installing required packages already used by the legacy installer..."
  install_existing_packages

  echo "Installing yt-dlp for $RUN_USER..."
  install_ytdlp_for_user "$RUN_USER"

  echo "Preparing download root and queue..."
  write_ytdlp_config_for_user "$RUN_USER" "$DOWNLOAD_DIR" "$MAX_HEIGHT"
  ensure_group_and_permissions "$DOWNLOAD_DIR" "$GROUP_NAME" "$RUN_USER" "$NAS_USER"
  write_queue_files "$DOWNLOAD_DIR" "$GROUP_NAME" "$RUN_USER"
  write_secret_file "$DOWNLOAD_DIR" "$RUN_USER" "$GROUP_NAME" "$TOKEN_VALUE"

  echo "Installing scripts and server module..."
  write_add_script "$DOWNLOAD_DIR"
  write_run_script "$DOWNLOAD_DIR" "$RUN_USER"
  install_server_file

  echo "Writing configuration and systemd units..."
  write_env_file "$RUN_USER" "$DOWNLOAD_DIR" "$PORT" "$TOKEN_VALUE" "$GROUP_NAME" "$NAS_USER" "$SUBNET" "$INTERVAL" "$MAX_HEIGHT"
  write_legacy_config_file "$RUN_USER" "$DOWNLOAD_DIR" "$PORT" "$GROUP_NAME" "$NAS_USER" "$SUBNET" "$INTERVAL" "$MAX_HEIGHT"
  write_systemd_units "$RUN_USER" "$GROUP_NAME" "$DOWNLOAD_DIR" "$INTERVAL"

  echo "Configuring firewall..."
  setup_ufw "$SUBNET" "$PORT"

  echo "Enabling services..."
  systemd_reload_enable

  echo
  echo "Health check:"
  health_check "$PORT"
  echo "DONE."
  echo "Endpoint base URL: http://YOUR_SERVER_IP:${PORT}"
  echo "Token: ${TOKEN_VALUE}"
  echo "Config file: ${ENV_FILE}"
}

load_current_config() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    RUN_USER="${YT2NAS_RUN_USER:-}"
    DOWNLOAD_DIR="${YT2NAS_DOWNLOAD_DIR:-}"
    PORT="${YT2NAS_PORT:-$DEFAULT_PORT}"
    TOKEN_VALUE="${YT2NAS_TOKEN:-}"
    GROUP_NAME="${YT2NAS_GROUP:-$DEFAULT_GROUP}"
    NAS_USER="${YT2NAS_NAS_USER:-}"
    SUBNET="${YT2NAS_SUBNET:-$DEFAULT_SUBNET}"
    INTERVAL="${YT2NAS_INTERVAL:-$DEFAULT_INTERVAL}"
    MAX_HEIGHT="${YT2NAS_MAX_HEIGHT:-$DEFAULT_MAX_HEIGHT}"
    return
  fi

  if [[ -f "$LEGACY_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$LEGACY_CONFIG_FILE"
    RUN_USER="${SERVICE_USER:-}"
    DOWNLOAD_DIR="${DOWNLOAD_DIR:-}"
    PORT="${PORT:-$DEFAULT_PORT}"
    TOKEN_VALUE=""
    GROUP_NAME="${GROUP_NAME:-$DEFAULT_GROUP}"
    NAS_USER="${NAS_USER:-}"
    SUBNET="${TRUSTED_SUBNET:-$DEFAULT_SUBNET}"
    INTERVAL="${INTERVAL_MIN:-$DEFAULT_INTERVAL}"
    MAX_HEIGHT="${MAX_HEIGHT:-$DEFAULT_MAX_HEIGHT}"
    return
  fi

  die "No config found. Run install first."
}

update_flow() {
  need_root
  find_python
  load_current_config
  validate_install_values

  if [[ -z "$TOKEN_VALUE" && -f "$DOWNLOAD_DIR/.queue/endpoint.secret" ]]; then
    TOKEN_VALUE="$(tr -d '\r\n' < "$DOWNLOAD_DIR/.queue/endpoint.secret")"
  fi

  echo "Updating server module and managed files..."
  install_ytdlp_for_user "$RUN_USER"
  write_ytdlp_config_for_user "$RUN_USER" "$DOWNLOAD_DIR" "$MAX_HEIGHT"
  ensure_group_and_permissions "$DOWNLOAD_DIR" "$GROUP_NAME" "$RUN_USER" "$NAS_USER"
  write_queue_files "$DOWNLOAD_DIR" "$GROUP_NAME" "$RUN_USER"
  write_add_script "$DOWNLOAD_DIR"
  write_run_script "$DOWNLOAD_DIR" "$RUN_USER"
  install_server_file
  write_env_file "$RUN_USER" "$DOWNLOAD_DIR" "$PORT" "$TOKEN_VALUE" "$GROUP_NAME" "$NAS_USER" "$SUBNET" "$INTERVAL" "$MAX_HEIGHT"
  write_legacy_config_file "$RUN_USER" "$DOWNLOAD_DIR" "$PORT" "$GROUP_NAME" "$NAS_USER" "$SUBNET" "$INTERVAL" "$MAX_HEIGHT"
  write_systemd_units "$RUN_USER" "$GROUP_NAME" "$DOWNLOAD_DIR" "$INTERVAL"
  setup_ufw "$SUBNET" "$PORT"

  systemctl daemon-reload
  systemctl restart yt2nas-server.service
  systemctl restart yt2nas-queue.timer

  echo "DONE."
  health_check "$PORT"
}

status_flow() {
  need_root

  echo "Environment file: $ENV_FILE"
  if [[ -f "$ENV_FILE" ]]; then
    sed 's/^YT2NAS_TOKEN=.*/YT2NAS_TOKEN="<hidden>"/' "$ENV_FILE"
  else
    echo "No environment file found."
  fi

  echo
  systemctl status yt2nas-server.service --no-pager || true
  echo
  systemctl status yt2nas-queue.timer --no-pager || true

  if command_exists ufw; then
    echo
    ufw status verbose || true
  fi
}

safe_purge_queue() {
  local download_dir="$1"
  local queue_dir="$download_dir/.queue"

  [[ -n "$download_dir" ]] || die "Refusing purge because DOWNLOAD_DIR is empty."
  [[ "$download_dir" == /* ]] || die "Refusing purge because DOWNLOAD_DIR is not absolute: $download_dir"
  [[ "$download_dir" != "/" ]] || die "Refusing purge because DOWNLOAD_DIR is /."
  [[ -d "$queue_dir" ]] || {
    echo "Queue folder not found: $queue_dir"
    return
  }

  rm -rf -- "$queue_dir"
}

uninstall_flow() {
  need_root
  local purge="${1:-}"
  local download_dir=""

  if [[ -n "$purge" && "$purge" != "--purge" ]]; then
    die "Unknown uninstall option: $purge"
  fi

  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    download_dir="${YT2NAS_DOWNLOAD_DIR:-}"
  elif [[ -f "$LEGACY_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$LEGACY_CONFIG_FILE"
    download_dir="${DOWNLOAD_DIR:-}"
  fi

  echo "Stopping services..."
  systemd_stop_disable

  echo "Removing systemd units..."
  rm -f "$SERVER_SERVICE" "$LEGACY_ENDPOINT_SERVICE" "$QUEUE_SERVICE" "$QUEUE_TIMER"
  systemctl daemon-reload

  echo "Removing installed server files..."
  rm -f "$ADD_SH" "$RUN_SH" "$INSTALLED_SERVER_PY"
  rmdir "$INSTALL_DIR" 2>/dev/null || true

  echo "Removing config files..."
  rm -f "$ENV_FILE" "$LEGACY_CONFIG_FILE"

  if [[ "$purge" == "--purge" ]]; then
    safe_purge_queue "$download_dir"
  fi

  echo "Note: downloaded videos are NOT deleted."
  echo "DONE."
}

main() {
  local command_name="${1:-install}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  case "$command_name" in
    install)
      parse_install_args "$@"
      install_flow
      ;;
    update) update_flow ;;
    status) status_flow ;;
    uninstall) uninstall_flow "${1:-}" ;;
    -h|--help) print_usage ;;
    *) die "Unknown command: $command_name" ;;
  esac
}

main "$@"
