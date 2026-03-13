from __future__ import annotations

import json
import traceback

from .router import dispatch
from .utils import base_response


def main() -> None:
    import sys

    if len(sys.argv) < 2:
        print(json.dumps({"output": "Missing request payload"}, ensure_ascii=False))
        return

    try:
        payload = json.loads(sys.argv[1])
        query = str(payload.get("query", ""))
        settings = payload.get("settings", {}) or {}
        response = dispatch(query, settings)
        print(json.dumps(response, ensure_ascii=False))
    except Exception as exc:  # noqa: BLE001
        error_response = base_response()
        error_response["output"] = f"Command engine error: {exc}\\n\\n{traceback.format_exc()}"
        print(json.dumps(error_response, ensure_ascii=False))
