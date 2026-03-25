from __future__ import annotations

import re
from typing import Any


def base_response() -> dict[str, Any]:
    return {
        "output": "",
        "is_ai_response": False,
        "defer_ai": False,
        "ai_prompt": "",
        "ai_request_kind": "",
        "ai_request_provider": "",
        "ai_request_base_url": "",
        "ai_request_api_key": "",
        "ai_request_model": "",
        "ai_request_proxy_url": "",
        "ai_request_system_prompt": "",
        "open_panel": False,
        "panel_presentation": "",
        "panel_title": "",
        "panel_text": "",
        "panel_path": "",
        "defer_shell": False,
        "shell_command": "",
        "shell_run_in_background": False,
        "progress_presentation": "terminal",
        "progress_title": "",
        "show_history": False,
        "open_settings": False,
        "should_quit": False,
        "should_save_history": False,
        "history_type": "",
        "history_input": "",
        "open_url": None,
        "setting_updates": [],
        "setting_schema": [],
        "config_paths": {},
    }


def coalesce(settings: dict[str, Any], key: str, fallback: Any = "") -> Any:
    if key in settings:
        return settings[key]
    snake = camel_to_snake(key)
    if snake in settings:
        return settings[snake]
    return fallback


def is_truthy(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on", "enabled"}


def fenced(language: str, content: str) -> str:
    safe = (content or "").replace("```", "` ` `")
    return f"```{language}\\n{safe}\\n```"


def camel_to_snake(name: str) -> str:
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name).lower()


def normalize_value_type(value_type: str) -> str:
    lowered = (value_type or "").strip().lower()
    if lowered in {"bool", "boolean"}:
        return "bool"
    if lowered in {"int", "integer"}:
        return "int"
    if lowered in {"secret", "password", "token"}:
        return "secret"
    return "string"
