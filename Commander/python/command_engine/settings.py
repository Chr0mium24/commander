from __future__ import annotations

import shlex
from typing import Any

from .constants import SETTING_KEY_MAP
from .utils import coalesce, is_truthy


def handle_set_command(
    content: str,
    settings: dict[str, Any],
    response: dict[str, Any],
) -> dict[str, Any]:
    stripped = content.strip()
    if not stripped:
        response["open_settings"] = True
        return response

    try:
        tokens = shlex.split(stripped)
    except ValueError as exc:
        response["output"] = f"Invalid set syntax: {exc}"
        return response

    if not tokens:
        response["open_settings"] = True
        return response

    if tokens[0].lower() == "get":
        if len(tokens) < 2:
            response["output"] = "Usage: set get <key>"
            return response

        key = tokens[1]
        mapped = SETTING_KEY_MAP.get(key)
        if not mapped:
            response["output"] = f"Unknown key: {key}"
            return response

        storage_key, _value_type = mapped
        value = coalesce(settings, storage_key, "")
        response["output"] = f"{storage_key} = {value}"
        return response

    if len(tokens) < 2:
        response["output"] = "Usage: set <key> <value>"
        return response

    key = tokens[0]
    mapped = SETTING_KEY_MAP.get(key)
    if not mapped:
        response["output"] = f"Unknown key: {key}"
        return response

    storage_key, value_type = mapped
    value = " ".join(tokens[1:])

    if value_type == "int":
        try:
            int(value)
        except ValueError:
            response["output"] = f"{storage_key} expects an integer value"
            return response

    if value_type == "bool":
        value = "true" if is_truthy(value) else "false"

    response["setting_updates"] = [
        {"key": storage_key, "value": value, "value_type": value_type}
    ]
    response["output"] = f"Updated {storage_key} = {value}"
    return response
