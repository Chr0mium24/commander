from __future__ import annotations

import shlex
from typing import Any

from .constants import SETTING_KEY_MAP
from .config import config_paths, update_user_config
from .utils import camel_to_snake, coalesce, is_truthy


def handle_set_command(
    content: str,
    settings: dict[str, Any],
    response: dict[str, Any],
    setting_schema: list[dict[str, str]] | None = None,
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

    action = tokens[0].lower()

    if action == "get":
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

    if action in {"list", "schema", "keys"}:
        schema = setting_schema if setting_schema is not None else []
        response["output"] = render_setting_schema(schema)
        return response

    if action in {"file", "path", "paths"}:
        paths = config_paths()
        response["output"] = "\n".join(
            [
                "### Config Paths",
                "",
                f"- Defaults: `{paths['defaults']}`",
                f"- User config: `{paths['user_config']}`",
                f"- Plugin directory: `{paths['plugin_directory']}`",
            ]
        )
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
    raw_value = " ".join(tokens[1:])
    value = raw_value
    persist_value: Any = raw_value

    if value_type == "int":
        try:
            persist_value = int(raw_value)
            value = str(persist_value)
        except ValueError:
            response["output"] = f"{storage_key} expects an integer value"
            return response

    if value_type == "bool":
        persist_value = is_truthy(raw_value)
        value = "true" if persist_value else "false"

    if value_type == "string":
        persist_value = raw_value

    response["setting_updates"] = [
        {"key": storage_key, "value": value, "value_type": value_type}
    ]
    try:
        update_user_config(storage_key, persist_value)
        response["output"] = f"Updated {storage_key} = {value} (saved)"
    except OSError as exc:
        response["output"] = f"Updated {storage_key} = {value} (save failed: {exc})"
    return response


def render_setting_schema(schema: list[dict[str, str]]) -> str:
    rows = []
    seen: set[str] = set()
    for item in schema:
        key = str(item.get("key", "")).strip()
        if not key or key in seen:
            continue
        seen.add(key)

        snake = camel_to_snake(key)
        value_type = str(item.get("type", "string")).strip() or "string"
        group = str(item.get("group", "general")).strip() or "general"
        label = str(item.get("label", key)).strip() or key
        rows.append((snake, key, value_type, group, label))

    rows.sort(key=lambda row: row[0])

    header = [
        "### Settings Schema",
        "",
        "| command key | storage key | type | group | label |",
        "| --- | --- | --- | --- | --- |",
    ]
    body = [f"| `{a}` | `{b}` | `{c}` | `{d}` | {e} |" for a, b, c, d, e in rows]

    tips = [
        "",
        "Examples:",
        "- `set get gemini_model`",
        "- `set ai_provider openai_compatible`",
        "- `set plugin_dir ~/Library/Application\\ Support/Commander/plugins`",
        "- `set file`",
    ]
    return "\n".join(header + body + tips)
