from __future__ import annotations

from typing import Any

from .config import merged_settings
from .constants import DEFAULT_PYTHON, PLUGIN_DIR_PATH
from .plugin_registry import CommandRegistry, load_builtin_plugins, load_external_plugins
from .runtime import EngineContext
from .utils import base_response, coalesce


def dispatch(query: str, settings: dict[str, Any], attachments: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    response = base_response()
    response["history_input"] = query

    trimmed = query.strip()
    if not trimmed:
        return response

    effective_settings = merged_settings(settings)

    alias_py = str(coalesce(effective_settings, "aliasPy", "py") or "py")
    alias_def = str(coalesce(effective_settings, "aliasDef", "def") or "def")
    alias_ask = str(coalesce(effective_settings, "aliasAsk", "ask") or "ask")
    alias_ser = str(coalesce(effective_settings, "aliasSer", "ser") or "ser")

    python_path = str(coalesce(effective_settings, "pythonPath", DEFAULT_PYTHON) or DEFAULT_PYTHON)
    script_dir = str(coalesce(effective_settings, "scriptDirectory", "") or "")
    plugin_dir = str(
        coalesce(effective_settings, "pluginDirectory", str(PLUGIN_DIR_PATH))
        or str(PLUGIN_DIR_PATH)
    )
    enabled_plugins = parse_plugin_filter(
        str(coalesce(effective_settings, "enabledPlugins", "") or "")
    )
    disabled_plugins = parse_plugin_filter(
        str(coalesce(effective_settings, "disabledPlugins", "") or "")
    )

    context = EngineContext(
        query=query,
        settings=effective_settings,
        attachments=[dict(item) for item in (attachments or []) if isinstance(item, dict)],
        aliases={"py": alias_py, "def": alias_def, "ask": alias_ask, "ser": alias_ser},
        python_path=python_path,
        script_dir=script_dir,
        response=response,
    )

    registry = CommandRegistry()
    context.registry = registry

    builtin_report = load_builtin_plugins(
        registry,
        context,
        enabled_plugins=enabled_plugins,
        disabled_plugins=disabled_plugins,
    )
    external_report = load_external_plugins(
        registry,
        context,
        plugin_dir=plugin_dir,
        enabled_plugins=enabled_plugins,
        disabled_plugins=disabled_plugins,
    )

    context.runtime_metadata["loaded_plugins"] = (
        builtin_report["loaded"] + external_report["loaded"]
    )
    context.runtime_metadata["plugin_errors"] = registry.plugin_errors
    context.runtime_metadata["plugin_directory"] = plugin_dir
    context.runtime_metadata["enabled_plugins"] = sorted(enabled_plugins)
    context.runtime_metadata["disabled_plugins"] = sorted(disabled_plugins)
    context.runtime_metadata["available_plugins"] = (
        builtin_report["available"] + external_report["available"]
    )
    context.runtime_metadata["skipped_plugins"] = (
        builtin_report["skipped"] + external_report["skipped"]
    )
    context.runtime_metadata["attachments"] = [dict(item) for item in context.attachments]

    handled = registry.dispatch(context, trimmed)
    if not handled and not response["output"]:
        response["output"] = "Unknown command. Type `help`."

    return response


def parse_plugin_filter(raw: str) -> set[str]:
    cleaned = raw.replace("\n", ",").replace("\t", ",")
    tokens = [token.strip().lower() for token in cleaned.replace(" ", ",").split(",")]
    return {token for token in tokens if token}
