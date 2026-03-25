from __future__ import annotations

import json
import sys
import traceback
from typing import Any

from .router import dispatch
from .utils import base_response

STDIO_RESPONSE_PREFIX = "__COMMANDER_JSON__:"


def _handle_payload(raw_payload: str) -> dict[str, Any]:
    payload = json.loads(raw_payload)
    query = str(payload.get("query", ""))
    settings = payload.get("settings", {}) or {}
    attachments = payload.get("attachments", []) or []
    return dispatch(query, settings, attachments)


def _write_response(response: dict[str, Any], *, stdio: bool) -> None:
    encoded = json.dumps(response, ensure_ascii=False)
    if stdio:
        print(f"{STDIO_RESPONSE_PREFIX}{encoded}", flush=True)
    else:
        print(encoded)


def _write_error(exc: Exception, *, stdio: bool) -> None:
    error_response = base_response()
    error_response["output"] = f"Command engine error: {exc}\\n\\n{traceback.format_exc()}"
    _write_response(error_response, stdio=stdio)


def _serve_stdio() -> None:
    for raw_line in sys.stdin:
        raw_payload = raw_line.strip()
        if not raw_payload:
            continue

        try:
            response = _handle_payload(raw_payload)
            _write_response(response, stdio=True)
        except Exception as exc:  # noqa: BLE001
            _write_error(exc, stdio=True)


def main() -> None:
    if len(sys.argv) >= 2 and sys.argv[1] == "--stdio":
        _serve_stdio()
        return

    if len(sys.argv) < 2:
        print(json.dumps({"output": "Missing request payload"}, ensure_ascii=False))
        return

    try:
        response = _handle_payload(sys.argv[1])
        _write_response(response, stdio=False)
    except Exception as exc:  # noqa: BLE001
        _write_error(exc, stdio=False)
