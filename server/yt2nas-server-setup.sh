#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$SCRIPT_DIR/install.sh"

if [[ ! -f "$INSTALLER" ]]; then
  echo "ERROR: expected installer not found: $INSTALLER" >&2
  echo "Run from a full checkout of the yt2nas repository, then use server/install.sh." >&2
  exit 1
fi

echo "server/yt2nas-server-setup.sh is deprecated; forwarding to server/install.sh." >&2
if [[ -x "$INSTALLER" ]]; then
  exec "$INSTALLER" "$@"
fi

exec bash "$INSTALLER" "$@"
