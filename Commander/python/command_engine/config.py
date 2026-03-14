from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .constants import (
    APP_SUPPORT_DIR,
    DEFAULT_SETTINGS,
    DEFAULTS_PATH,
    PLUGIN_DIR_PATH,
    USER_CONFIG_PATH,
)


def ensure_runtime_dirs() -> bool:
    try:
        APP_SUPPORT_DIR.mkdir(parents=True, exist_ok=True)
        PLUGIN_DIR_PATH.mkdir(parents=True, exist_ok=True)
    except OSError:
        return False
    return True


def load_json(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}
    except OSError:
        return {}

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}

    return data if isinstance(data, dict) else {}


def save_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def load_defaults() -> dict[str, Any]:
    merged = dict(DEFAULT_SETTINGS)
    merged.update(load_json(DEFAULTS_PATH))
    return merged


def load_user_config() -> dict[str, Any]:
    if not ensure_runtime_dirs():
        return {}
    return load_json(USER_CONFIG_PATH)


def merged_settings(runtime_settings: dict[str, Any]) -> dict[str, Any]:
    # Priority: defaults < user config file < runtime(request).
    # Runtime settings come from app state/UI and should reflect current user edits immediately.
    merged: dict[str, Any] = {}
    merged.update(load_defaults())
    merged.update(load_user_config())
    merged.update(runtime_settings or {})
    return merged


def update_user_config(key: str, value: Any) -> None:
    payload = load_user_config()
    payload[key] = value
    save_json(USER_CONFIG_PATH, payload)


def config_paths() -> dict[str, str]:
    return {
        "defaults": str(DEFAULTS_PATH),
        "user_config": str(USER_CONFIG_PATH),
        "plugin_directory": str(PLUGIN_DIR_PATH),
    }
