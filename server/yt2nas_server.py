#!/usr/bin/env python3
"""Small HTTP endpoint for the YT2NAS queue.

The server intentionally uses only the Python standard library. Runtime
configuration comes from environment variables written by server/install.sh.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional
from urllib.parse import ParseResult, parse_qs, urlparse

DEFAULT_DOWNLOAD_DIR = "/mnt/NAS/Youtube"
DEFAULT_PORT = 9835
DEFAULT_ADD_SCRIPT = "/usr/local/bin/yt2nas-add.sh"
MAX_BODY_BYTES = 2048
MAX_DELETE_BODY_BYTES = 64 * 1024

ALLOWED_HOSTS = {
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "music.youtube.com",
    "youtu.be",
}


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name, "").strip()
    if not value:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def media_root() -> Path:
    configured = os.environ.get("YT2NAS_DOWNLOAD_DIR", DEFAULT_DOWNLOAD_DIR)
    return Path(configured).expanduser().resolve(strict=False)


def path_inside_media_root(*parts: str) -> Path:
    root = media_root()
    path = (root.joinpath(*parts)).resolve(strict=False)
    if path != root and root not in path.parents:
        raise ValueError(f"path escapes media root: {path}")
    return path


def queue_dir() -> Path:
    return path_inside_media_root(".queue")


def secret_file() -> Path:
    configured = os.environ.get("YT2NAS_SECRET_FILE", "").strip()
    if configured:
        path = Path(configured).expanduser().resolve(strict=False)
        root = media_root()
        if path != root and root not in path.parents:
            raise ValueError("YT2NAS_SECRET_FILE must be inside YT2NAS_DOWNLOAD_DIR")
        return path
    return queue_dir() / "endpoint.secret"


def queue_file() -> Path:
    return queue_dir() / "queue.txt"


def endpoint_log() -> Path:
    return queue_dir() / "endpoint.log"


def ytdlp_log() -> Path:
    return queue_dir() / "yt-dlp.log"


def add_script() -> str:
    return os.environ.get("YT2NAS_ADD_SCRIPT", DEFAULT_ADD_SCRIPT)


def is_path_inside(child: Path, parent: Path) -> bool:
    return child == parent or parent in child.parents


def path_modified_iso(path: Path) -> str:
    modified = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    return modified.isoformat().replace("+00:00", "Z")


def rel_media_path(path: Path) -> str:
    return path.relative_to(media_root()).as_posix()


def is_hidden_name(name: str) -> bool:
    return name.startswith(".")


def reject_internal_parts(parts: tuple[str, ...]) -> Optional[str]:
    if not parts:
        return "path_is_empty"

    for part in parts:
        if part in ("", ".", ".."):
            return "path_contains_invalid_segment"
        if is_hidden_name(part):
            return "path_contains_internal_or_hidden_segment"

    return None


def split_safe_rel_path(rel_path: str) -> tuple[Optional[tuple[str, ...]], Optional[str]]:
    if not isinstance(rel_path, str):
        return None, "path_must_be_string"

    if "\x00" in rel_path:
        return None, "path_contains_nul"
    if "\\" in rel_path:
        return None, "backslash_paths_are_not_supported"
    if rel_path.startswith("/"):
        return None, "absolute_paths_are_not_allowed"
    if rel_path == "":
        return None, "path_is_empty"

    parts = tuple(rel_path.split("/"))
    error = reject_internal_parts(parts)
    if error:
        return None, error

    return parts, None


def safe_media_path(rel_path: str, *, must_exist: bool = True) -> Path:
    parts, error = split_safe_rel_path(rel_path)
    if error or parts is None:
        raise ValueError(error or "invalid_path")

    root = media_root()
    candidate = root.joinpath(*parts)
    resolved = candidate.resolve(strict=must_exist)

    if not is_path_inside(resolved, root):
        raise ValueError("path_escapes_media_root")
    if resolved == root:
        raise ValueError("download_dir_cannot_be_targeted")

    return candidate


def safe_channel_path(channel: str) -> Path:
    parts, error = split_safe_rel_path(channel)
    if error or parts is None:
        raise ValueError(error or "invalid_channel")
    if len(parts) != 1:
        raise ValueError("channel_must_be_immediate_child")

    path = safe_media_path(parts[0], must_exist=True)
    if not path.is_dir():
        raise FileNotFoundError(channel)

    return path


def visible_media_entry(path: Path) -> bool:
    if is_hidden_name(path.name):
        return False

    try:
        resolved = path.resolve(strict=True)
    except OSError:
        return False

    return is_path_inside(resolved, media_root())


def count_visible_children(path: Path) -> Optional[int]:
    try:
        return sum(1 for child in path.iterdir() if visible_media_entry(child))
    except OSError:
        return None


def media_item(path: Path) -> dict[str, Any]:
    item: dict[str, Any] = {
        "name": path.name,
        "relPath": rel_media_path(path),
        "isDir": path.is_dir(),
        "modified": path_modified_iso(path),
    }

    if item["isDir"]:
        return item

    try:
        item["size"] = path.stat().st_size
    except OSError:
        item["size"] = None

    return item


def channel_item(path: Path) -> dict[str, Any]:
    item = {
        "name": path.name,
        "relPath": rel_media_path(path),
        "modified": path_modified_iso(path),
    }

    item_count = count_visible_children(path)
    if item_count is not None:
        item["itemCount"] = item_count

    return item


def delete_media_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
        return

    if path.is_dir():
        shutil.rmtree(path)
        return

    raise FileNotFoundError(path)


def read_token() -> str:
    token = os.environ.get("YT2NAS_TOKEN", "").strip()
    if token:
        return token

    try:
        return secret_file().read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""


def is_allowed_youtube_url(url: str) -> bool:
    try:
        parsed = urlparse(url.strip())
    except ValueError:
        return False

    if parsed.scheme not in ("http", "https"):
        return False

    host = (parsed.hostname or "").lower()
    if host not in ALLOWED_HOSTS:
        return False

    if host == "youtu.be":
        return bool(parsed.path.strip("/"))

    path = (parsed.path or "").lower()
    if path.startswith("/watch"):
        query = parse_qs(parsed.query)
        return bool(query.get("v"))
    if path.startswith("/shorts/"):
        parts = path.split("/")
        return len(parts) >= 3 and bool(parts[2])
    if path.startswith("/playlist"):
        query = parse_qs(parsed.query)
        return bool(query.get("list"))

    return True


def tail_lines(path: Path, count: int) -> str:
    count = max(1, min(500, count))
    try:
        with path.open("rb") as file:
            file.seek(0, os.SEEK_END)
            size = file.tell()
            block_size = 4096
            data = b""
            position = size
            while position > 0 and data.count(b"\n") <= count:
                read_size = block_size if position - block_size > 0 else position
                position -= read_size
                file.seek(position)
                data = file.read(read_size) + data

        lines = data.splitlines()[-count:]
        return "\n".join(line.decode("utf-8", errors="replace") for line in lines)
    except FileNotFoundError:
        return ""
    except OSError as exc:
        return f"ERROR reading log: {exc}"


def count_queue_lines() -> int:
    try:
        with queue_file().open("r", encoding="utf-8") as file:
            return sum(1 for _ in file)
    except FileNotFoundError:
        return 0


def append_endpoint_log(message: str) -> None:
    queue_dir().mkdir(parents=True, exist_ok=True)
    with endpoint_log().open("a", encoding="utf-8") as file:
        file.write(message + "\n")


def parse_lines_param(query: dict[str, list[str]], default: int) -> int:
    try:
        return int(query.get("lines", [str(default)])[0])
    except ValueError:
        return default


class Handler(BaseHTTPRequestHandler):
    server_version = "yt2nas/1.0"

    def send_json(self, code: int, payload: dict[str, object]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def auth_ok(self) -> bool:
        token = read_token()
        return bool(token) and self.headers.get("X-Token", "") == token

    def require_auth(self) -> bool:
        if self.auth_ok():
            return True
        self.send_json(401, {"ok": False, "error": "unauthorized"})
        return False

    def read_json_body(self, max_bytes: int) -> tuple[Optional[dict[str, Any]], Optional[str]]:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0

        if length <= 0 or length > max_bytes:
            return None, "invalid_body_size"

        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None, "invalid_json"

        if not isinstance(payload, dict):
            return None, "json_body_must_be_object"

        return payload, None

    def handle_health(self) -> None:
        token = read_token()
        script = add_script()
        self.send_json(
            200,
            {
                "ok": bool(token) and os.path.exists(script),
                "queue_len": count_queue_lines(),
                "has_secret": bool(token),
                "has_add_script": os.path.exists(script),
            },
        )

    def handle_media_channels(self) -> None:
        root = media_root()
        if not root.exists() or not root.is_dir():
            self.send_json(
                404,
                {
                    "ok": False,
                    "error": "download_dir_not_found",
                    "downloadDir": str(root),
                },
            )
            return

        try:
            channels = [
                channel_item(child)
                for child in root.iterdir()
                if visible_media_entry(child) and child.is_dir()
            ]
        except OSError as exc:
            self.send_json(
                500,
                {"ok": False, "error": "list_channels_failed", "details": str(exc)},
            )
            return

        channels.sort(key=lambda item: str(item["name"]).lower())
        self.send_json(200, {"ok": True, "channels": channels})

    def handle_media_list(self, parsed_path: ParseResult) -> None:
        query = parse_qs(parsed_path.query)
        channel = query.get("channel", [""])[0]
        if not channel:
            self.send_json(400, {"ok": False, "error": "missing_channel"})
            return

        try:
            channel_path = safe_channel_path(channel)
        except ValueError as exc:
            self.send_json(
                400,
                {"ok": False, "error": "invalid_channel", "details": str(exc)},
            )
            return
        except FileNotFoundError:
            self.send_json(404, {"ok": False, "error": "channel_not_found"})
            return
        except OSError as exc:
            self.send_json(
                500,
                {"ok": False, "error": "channel_lookup_failed", "details": str(exc)},
            )
            return

        try:
            items = [
                media_item(child)
                for child in channel_path.iterdir()
                if visible_media_entry(child)
            ]
        except OSError as exc:
            self.send_json(
                500,
                {"ok": False, "error": "list_media_failed", "details": str(exc)},
            )
            return

        items.sort(key=lambda item: (not bool(item["isDir"]), str(item["name"]).lower()))
        self.send_json(
            200,
            {
                "ok": True,
                "channel": channel_path.name,
                "relPath": rel_media_path(channel_path),
                "items": items,
            },
        )

    def handle_add(self) -> None:
        payload, error = self.read_json_body(MAX_BODY_BYTES)
        if error or payload is None:
            self.send_json(400, {"ok": False, "error": error or "invalid_json"})
            return

        url = str(payload.get("url") or "").strip()
        if not url or not is_allowed_youtube_url(url):
            self.send_json(400, {"ok": False, "error": "invalid_or_non_youtube_url"})
            return

        try:
            result = subprocess.run(
                [add_script(), url],
                capture_output=True,
                check=False,
                text=True,
            )
            append_endpoint_log(f"ADD rc={result.returncode} url={url}")
        except OSError as exc:
            self.send_json(
                500,
                {"ok": False, "error": "enqueue_exception", "details": str(exc)},
            )
            return

        if result.returncode != 0:
            self.send_json(
                500,
                {
                    "ok": False,
                    "error": "enqueue_failed",
                    "details": result.stderr.strip(),
                },
            )
            return

        self.send_json(200, {"ok": True, "queue_len": count_queue_lines()})

    def handle_media_delete(self) -> None:
        payload, error = self.read_json_body(MAX_DELETE_BODY_BYTES)
        if error or payload is None:
            self.send_json(400, {"ok": False, "error": error or "invalid_json"})
            return

        requested_paths = payload.get("paths")
        if not isinstance(requested_paths, list):
            self.send_json(400, {"ok": False, "error": "paths_must_be_array"})
            return

        deleted: list[str] = []
        failed: list[dict[str, str]] = []

        for raw_path in requested_paths:
            rel_path = raw_path if isinstance(raw_path, str) else ""
            try:
                media_path = safe_media_path(rel_path, must_exist=True)
                delete_media_path(media_path)
                deleted.append(rel_media_path(media_path))
                append_endpoint_log(f"DELETE ok path={rel_media_path(media_path)}")
            except FileNotFoundError:
                failed.append({"path": str(raw_path), "error": "not_found"})
                append_endpoint_log(f"DELETE failed error=not_found path={raw_path}")
            except ValueError as exc:
                failed.append({"path": str(raw_path), "error": str(exc)})
                append_endpoint_log(f"DELETE failed error={exc} path={raw_path}")
            except OSError as exc:
                failed.append({"path": str(raw_path), "error": str(exc)})
                append_endpoint_log(f"DELETE failed error={exc} path={raw_path}")

        self.send_json(
            200,
            {
                "ok": not failed,
                "deleted": deleted,
                "failed": failed,
            },
        )

    def do_GET(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path == "/health":
            self.handle_health()
            return

        if not self.require_auth():
            return

        if parsed.path == "/media/channels":
            self.handle_media_channels()
            return

        if parsed.path == "/media/list":
            self.handle_media_list(parsed)
            return

        if parsed.path == "/queue-len":
            self.send_json(200, {"ok": True, "queue_len": count_queue_lines()})
            return

        if parsed.path == "/queue-tail":
            query = parse_qs(parsed.query)
            count = parse_lines_param(query, 50)
            self.send_json(
                200,
                {"ok": True, "lines": count, "text": tail_lines(queue_file(), count)},
            )
            return

        if parsed.path == "/tail":
            query = parse_qs(parsed.query)
            count = parse_lines_param(query, 120)
            requested_log = query.get("log", ["yt"])[0].lower()
            path = ytdlp_log() if requested_log in ("yt", "ytdlp") else endpoint_log()
            self.send_json(
                200,
                {
                    "ok": True,
                    "log": requested_log,
                    "lines": count,
                    "text": tail_lines(path, count),
                },
            )
            return

        self.send_json(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path not in {"/add", "/media/delete"}:
            self.send_json(404, {"ok": False, "error": "not_found"})
            return

        if not self.require_auth():
            return

        if parsed.path == "/add":
            self.handle_add()
            return

        self.handle_media_delete()

    def log_message(self, _format: str, *args: object) -> None:
        return


def main() -> None:
    queue_dir().mkdir(parents=True, exist_ok=True)
    port = env_int("YT2NAS_PORT", DEFAULT_PORT)
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
