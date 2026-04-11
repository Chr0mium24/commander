from __future__ import annotations

import shlex
from typing import Any

from .constants import SETTING_KEY_MAP, SETTING_SCHEMA
from .config import config_paths, update_user_config
from .utils import camel_to_snake, coalesce, is_truthy, normalize_value_type


def handle_set_command(
    content: str,
    settings: dict[str, Any],
    response: dict[str, Any],
    setting_schema: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    normalized_schema = normalize_setting_schema(setting_schema, settings=settings)
    schema_key_map = build_schema_key_map(normalized_schema)

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
        mapped = resolve_setting_key(key, schema_key_map)
        if not mapped:
            response["output"] = f"Unknown key: {key}"
            return response

        storage_key, _value_type = mapped
        value = coalesce(settings, storage_key, "")
        response["output"] = f"{storage_key} = {value}"
        return response

    if action in {"list", "schema", "keys"}:
        response["output"] = render_setting_schema(normalized_schema)
        return response

    if action in {"schema_json", "schemajson"}:
        response["setting_schema"] = normalized_schema
        response["config_paths"] = config_paths()
        response["output"] = "Schema loaded."
        return response

    if action in {"file", "path", "paths"}:
        paths = config_paths()
        response["config_paths"] = paths
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
    mapped = resolve_setting_key(key, schema_key_map)
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


def normalize_setting_schema(
    schema: list[dict[str, str]] | None,
    *,
    settings: dict[str, Any],
) -> list[dict[str, str]]:
    source = schema if schema is not None else SETTING_SCHEMA
    normalized: list[dict[str, str]] = []
    seen: set[str] = set()

    for item in source:
        storage_key = str(item.get("key", "")).strip()
        if not storage_key or storage_key in seen:
            continue
        seen.add(storage_key)

        value_type = normalize_value_type(str(item.get("type", "string")))
        group = str(item.get("group", "general")).strip() or "general"
        label = str(item.get("label", storage_key)).strip() or storage_key
        command_key = camel_to_snake(storage_key)
        value = coalesce(settings, storage_key, "")
        normalized.append(
            {
                "key": storage_key,
                "command_key": command_key,
                "type": value_type,
                "group": group,
                "label": label,
                "value": stringify_setting_value(value),
            }
        )

    normalized.sort(key=lambda row: row["command_key"])
    return normalized


def stringify_setting_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def build_schema_key_map(schema: list[dict[str, str]]) -> dict[str, tuple[str, str]]:
    mapping: dict[str, tuple[str, str]] = {}
    for item in schema:
        storage_key = str(item.get("key", "")).strip()
        command_key = str(item.get("command_key", "")).strip().lower()
        value_type = normalize_value_type(str(item.get("type", "string")))
        if value_type == "secret":
            value_type = "string"

        if storage_key:
            mapping[storage_key] = (storage_key, value_type)
        if command_key:
            mapping[command_key] = (storage_key, value_type)
    return mapping


def resolve_setting_key(
    key: str,
    schema_key_map: dict[str, tuple[str, str]],
) -> tuple[str, str] | None:
    return SETTING_KEY_MAP.get(key) or schema_key_map.get(key.lower())


def render_setting_schema(schema: list[dict[str, str]]) -> str:
    rows = []
    for item in schema:
        key = str(item.get("key", "")).strip()
        command_key = str(item.get("command_key", "")).strip()
        if not key:
            continue

        snake = command_key or camel_to_snake(key)
        value_type = normalize_value_type(str(item.get("type", "string")).strip() or "string")
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
        "- `set get ai_model`",
        "- `set ai_provider openai_compatible`",
        "- `set plugin_dir ~/Library/Application\\ Support/Commander/plugins`",
        "- `set file`",
    ]
    return "\n".join(header + body + tips)
