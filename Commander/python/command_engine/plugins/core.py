from __future__ import annotations

from ..config import config_paths
from ..executors import list_scripts
from ..prompts import help_text
from ..settings import handle_set_command
from ..runtime import EngineContext
from ..plugin_registry import CommandRegistry


def register(registry: CommandRegistry, context: EngineContext | None = None) -> None:
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
        usage="plugins [inspect|errors|reload]",
        description="Show loaded plugins and plugin errors.",
    )
    registry.register_command(
        "config",
        handle_config,
        usage="config",
        description="Show config and plugin paths.",
    )


def handle_help(context: EngineContext, content: str) -> None:
    entries = []
    if context.registry is not None:
        entries = context.registry.help_entries()
    context.response["output"] = help_text(context.aliases, entries)


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
    action = content.strip().lower()
    if action == "inspect":
        _handle_plugins_inspect(context)
        return
    if action == "errors":
        _handle_plugins_errors(context)
        return
    if action == "reload":
        context.response["output"] = (
            "Plugins are loaded on every command dispatch. No manual reload needed."
        )
        return

    loaded = context.runtime_metadata.get("loaded_plugins", [])
    errors = context.runtime_metadata.get("plugin_errors", [])
    plugin_directory = context.runtime_metadata.get("plugin_directory", "")

    lines = ["### Plugins"]
    if loaded:
        lines.append("")
        lines.append("Loaded:")
        lines.extend(f"- `{name}`" for name in loaded)

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
