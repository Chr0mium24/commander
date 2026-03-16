from __future__ import annotations

from ..config import config_paths, update_user_config
from ..executors import list_scripts
from ..prompts import help_text
from ..settings import handle_set_command
from ..runtime import EngineContext
from ..plugin_registry import CommandRegistry


def register(registry: CommandRegistry, context: EngineContext | None = None) -> None:
    registry.register_help_section(
        "Core Commands",
        [
            "`help` show dynamic help from active plugins",
            "`hist` open history",
            "`scripts` list scripts in script directory",
            "`set` open settings window",
            "`set get <key>` read one setting",
            "`set <key> <value>` update one setting",
            "`set list` print schema",
            "`set file` show config paths",
            "`plugins` show plugin state",
            "`plugins enable <name...>` enable plugins",
            "`plugins disable <name...>` disable plugins",
            "`plugins reset` clear plugin filters",
            "`quit` exit app",
        ],
    )

    registry.register_command(
        "help",
        handle_help,
        usage="help",
        description="Show command help and aliases.",
    )
    registry.register_command(
        "hist",
        handle_hist,
        usage="hist",
        description="Open history list.",
    )
    registry.register_command(
        "quit",
        handle_quit,
        usage="quit",
        description="Quit Commander.",
    )
    registry.register_command(
        "scripts",
        handle_scripts,
        usage="scripts",
        description="List runnable .sh/.py scripts from script directory.",
    )
    registry.register_command(
        "set",
        handle_set,
        usage="set [get|list|schema|file] ...",
        description="Read/write settings and open settings UI.",
    )
    registry.register_command(
        "plugins",
        handle_plugins,
        usage="plugins [inspect|errors|reload|enable|disable|reset] ...",
        description="Inspect plugin state and switch plugin activation.",
    )
    registry.register_command(
        "config",
        handle_config,
        usage="config",
        description="Show config and plugin paths.",
    )


def handle_help(context: EngineContext, content: str) -> None:
    schema = None
    sections = []
    if context.registry is not None:
        schema = context.registry.setting_schema()
        sections = context.registry.help_sections()

    loaded_plugins = context.runtime_metadata.get("loaded_plugins", [])
    skipped_plugins = context.runtime_metadata.get("skipped_plugins", [])
    context.response["output"] = help_text(
        context.aliases,
        setting_schema=schema,
        plugin_sections=sections,
        active_plugins=loaded_plugins,
        skipped_plugins=skipped_plugins,
    )


def handle_hist(context: EngineContext, content: str) -> None:
    context.response["show_history"] = True


def handle_quit(context: EngineContext, content: str) -> None:
    context.response["should_quit"] = True


def handle_scripts(context: EngineContext, content: str) -> None:
    if not context.script_dir:
        context.response["output"] = "Script directory is not configured. Set it in Settings."
        return

    names = list_scripts(context.script_dir)
    if not names:
        context.response["output"] = f"No .sh/.py scripts found in: {context.script_dir}"
        return

    lines = "\n".join(f"- `{name}`" for name in names)
    context.response["output"] = f"### Scripts in `{context.script_dir}`\n\n{lines}"


def handle_set(context: EngineContext, content: str) -> None:
    schema = context.registry.setting_schema() if context.registry is not None else None
    handle_set_command(content, context.settings, context.response, setting_schema=schema)


def handle_plugins(context: EngineContext, content: str) -> None:
    tokens = [part for part in content.strip().split(" ") if part]
    action = tokens[0].lower() if tokens else ""

    if action == "enable":
        _handle_plugins_toggle(context, tokens[1:], enable=True)
        return
    if action == "disable":
        _handle_plugins_toggle(context, tokens[1:], enable=False)
        return
    if action == "reset":
        _reset_plugin_filters(context)
        return
    if action == "inspect":
        _handle_plugins_inspect(context)
        return
    if action == "errors":
        _handle_plugins_errors(context)
        return
    if action == "reload":
        context.response["output"] = (
            "Plugins are loaded on every command dispatch. "
            "Changes and switches are hot-reloaded on the next command."
        )
        return

    loaded = context.runtime_metadata.get("loaded_plugins", [])
    errors = context.runtime_metadata.get("plugin_errors", [])
    plugin_directory = context.runtime_metadata.get("plugin_directory", "")
    available = context.runtime_metadata.get("available_plugins", [])
    skipped = context.runtime_metadata.get("skipped_plugins", [])
    enabled_filter = context.runtime_metadata.get("enabled_plugins", [])
    disabled_filter = context.runtime_metadata.get("disabled_plugins", [])

    lines = ["### Plugins"]
    if available:
        lines.append("")
        lines.append("Available:")
        lines.extend(f"- `{name}`" for name in available)

    if loaded:
        lines.append("")
        lines.append("Active:")
        lines.extend(f"- `{name}`" for name in loaded)

    if skipped:
        lines.append("")
        lines.append("Skipped by filters:")
        lines.extend(f"- `{name}`" for name in skipped)

    if enabled_filter:
        lines.append("")
        lines.append("Enabled filter:")
        lines.extend(f"- `{name}`" for name in enabled_filter)

    if disabled_filter:
        lines.append("")
        lines.append("Disabled filter:")
        lines.extend(f"- `{name}`" for name in disabled_filter)

    if plugin_directory:
        lines.append("")
        lines.append(f"Directory: `{plugin_directory}`")

    if errors:
        lines.append("")
        lines.append("Errors:")
        lines.extend(f"- {item}" for item in errors)

    if not loaded and not errors:
        lines.append("")
        lines.append("No plugins loaded.")

    lines.append("")
    lines.append("Tips:")
    lines.append("- `plugins enable ai read` enable by short names")
    lines.append("- `plugins disable ai` disable by short name")
    lines.append("- `plugins disable builtin:read` disable by explicit id")
    lines.append("- `plugins reset` clear enabled/disabled filters")
    lines.append("- `plugins inspect` list commands grouped by plugin")
    lines.append("- `plugins errors` print only plugin errors")
    lines.append("- `plugins reload` explain reload behavior")

    context.response["output"] = "\n".join(lines)


def handle_config(context: EngineContext, content: str) -> None:
    paths = config_paths()
    context.response["output"] = "\n".join(
        [
            "### Config Paths",
            "",
            f"- Defaults: `{paths['defaults']}`",
            f"- User config: `{paths['user_config']}`",
            f"- Plugin directory: `{paths['plugin_directory']}`",
        ]
    )


def _handle_plugins_errors(context: EngineContext) -> None:
    errors = context.runtime_metadata.get("plugin_errors", [])
    if not errors:
        context.response["output"] = "No plugin errors."
        return

    lines = ["### Plugin Errors", ""]
    lines.extend(f"- {item}" for item in errors)
    context.response["output"] = "\n".join(lines)


def _handle_plugins_inspect(context: EngineContext) -> None:
    registry = context.registry
    if registry is None:
        context.response["output"] = "Plugin registry unavailable."
        return

    grouped = registry.entries_by_plugin()
    if not grouped:
        context.response["output"] = "No commands registered by plugins."
        return

    lines = ["### Plugin Command Map"]
    for plugin_name in sorted(grouped.keys()):
        lines.append("")
        lines.append(f"#### {plugin_name}")
        for item in grouped[plugin_name]:
            usage = item.usage or item.command
            alias_part = (
                f" | aliases: {', '.join(f'`{alias}`' for alias in item.aliases)}"
                if item.aliases
                else ""
            )
            detail = item.description or "No description."
            lines.append(f"- `{usage}` | {detail}{alias_part}")

    context.response["output"] = "\n".join(lines)


def _handle_plugins_toggle(context: EngineContext, names: list[str], *, enable: bool) -> None:
    if not names:
        verb = "enable" if enable else "disable"
        context.response["output"] = f"Usage: plugins {verb} <plugin_name...>"
        return

    enabled = _parse_filter_list(str(context.settings.get("enabledPlugins") or ""))
    disabled = _parse_filter_list(str(context.settings.get("disabledPlugins") or ""))
    updated: list[str] = []
    ignored: list[str] = []

    for raw in names:
        token = raw.strip().lower()
        if not token:
            continue
        if not enable and token in {"core", "builtin:core"}:
            ignored.append(token)
            continue

        updated.append(token)
        if enable:
            enabled.add(token)
            disabled.discard(token)
        else:
            disabled.add(token)
            enabled.discard(token)

    if not updated and ignored:
        context.response["output"] = "Core plugin cannot be disabled."
        return

    _persist_plugin_filters(context, enabled, disabled)
    action_word = "Enabled" if enable else "Disabled"
    lines = [f"{action_word}: {', '.join(f'`{name}`' for name in updated)}"]
    if ignored:
        lines.append(f"Ignored: {', '.join(f'`{name}`' for name in ignored)}")
    lines.append("Plugin switches are hot-reloaded on the next command.")
    context.response["output"] = "\n".join(lines)


def _reset_plugin_filters(context: EngineContext) -> None:
    _persist_plugin_filters(context, set(), set())
    context.response["output"] = (
        "Cleared enabled/disabled plugin filters.\n"
        "Plugin switches are hot-reloaded on the next command."
    )


def _persist_plugin_filters(
    context: EngineContext,
    enabled: set[str],
    disabled: set[str],
) -> None:
    enabled_value = ",".join(sorted(enabled))
    disabled_value = ",".join(sorted(disabled))
    response_updates = [
        {"key": "enabledPlugins", "value": enabled_value, "value_type": "string"},
        {"key": "disabledPlugins", "value": disabled_value, "value_type": "string"},
    ]
    context.response["setting_updates"] = response_updates

    try:
        update_user_config("enabledPlugins", enabled_value)
        update_user_config("disabledPlugins", disabled_value)
    except OSError as exc:
        context.response["output"] = f"Updated in memory; failed saving plugin filters: {exc}"


def _parse_filter_list(raw: str) -> set[str]:
    cleaned = raw.replace("\n", ",").replace("\t", ",")
    tokens = [token.strip().lower() for token in cleaned.replace(" ", ",").split(",")]
    return {token for token in tokens if token}
