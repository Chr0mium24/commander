from __future__ import annotations

from typing import Any

from .config import merged_settings
from .constants import DEFAULT_PYTHON, PLUGIN_DIR_PATH
from .plugin_registry import CommandRegistry, load_builtin_plugins, load_external_plugins
from .runtime import EngineContext
from .utils import base_response, coalesce


def dispatch(query: str, settings: dict[str, Any]) -> dict[str, Any]:
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

    context = EngineContext(
        query=query,
        settings=effective_settings,
        aliases={"py": alias_py, "def": alias_def, "ask": alias_ask, "ser": alias_ser},
        python_path=python_path,
        script_dir=script_dir,
        response=response,
    )

    registry = CommandRegistry()
    context.registry = registry

    load_builtin_plugins(registry, context)
    load_external_plugins(registry, context, plugin_dir=plugin_dir)

    context.runtime_metadata["loaded_plugins"] = registry.loaded_plugins
    context.runtime_metadata["plugin_errors"] = registry.plugin_errors

    handled = registry.dispatch(context, trimmed)
    if not handled and not response["output"]:
        response["output"] = "Unknown command. Type `help`."

    return response
