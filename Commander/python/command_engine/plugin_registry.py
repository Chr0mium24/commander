from __future__ import annotations

import importlib
import importlib.util
import inspect
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .constants import PLUGIN_DIR_PATH, SETTING_SCHEMA
from .runtime import EngineContext

CommandHandler = Callable[[EngineContext, str], None]
FallbackHandler = Callable[[EngineContext, str], bool]


@dataclass
class CommandHelpEntry:
    command: str
    aliases: list[str]
    usage: str
    description: str
    plugin: str


@dataclass
class _RegisteredCommand:
    handler: CommandHandler
    plugin: str
    usage: str
    description: str
    aliases: set[str]


class CommandRegistry:
    def __init__(self) -> None:
        self._handlers: dict[str, CommandHandler] = {}
        self._entries: dict[str, _RegisteredCommand] = {}
        self._fallback: FallbackHandler | None = None
        self._active_plugin = "builtin"
        self._loaded_plugins: list[str] = []
        self._plugin_errors: list[str] = []
        self._setting_schema = [dict(item) for item in SETTING_SCHEMA]

    @property
    def loaded_plugins(self) -> list[str]:
        return list(self._loaded_plugins)

    @property
    def plugin_errors(self) -> list[str]:
        return list(self._plugin_errors)

    def setting_schema(self) -> list[dict[str, str]]:
        return [dict(item) for item in self._setting_schema]

    def activate_plugin(self, name: str) -> None:
        plugin_name = name.strip() or "builtin"
        self._active_plugin = plugin_name
        if plugin_name not in self._loaded_plugins:
            self._loaded_plugins.append(plugin_name)

    def add_plugin_error(self, message: str) -> None:
        self._plugin_errors.append(message)

    def register_setting(
        self,
        key: str,
        value_type: str,
        label: str,
        group: str = "plugin",
    ) -> None:
        normalized = key.strip()
        if not normalized:
            return
        if any(item.get("key") == normalized for item in self._setting_schema):
            return
        self._setting_schema.append(
            {"key": normalized, "type": value_type, "label": label, "group": group}
        )

    def register_command(
        self,
        command: str,
        handler: CommandHandler,
        *,
        aliases: list[str] | None = None,
        usage: str = "",
        description: str = "",
    ) -> None:
        canonical = command.strip().lower()
        if not canonical:
            return

        alias_tokens = {canonical}
        for alias in aliases or []:
            token = alias.strip().lower()
            if token:
                alias_tokens.add(token)

        existing = self._entries.get(canonical)
        if existing is None:
            entry = _RegisteredCommand(
                handler=handler,
                plugin=self._active_plugin,
                usage=usage.strip(),
                description=description.strip(),
                aliases=alias_tokens,
            )
            self._entries[canonical] = entry
        else:
            existing.aliases.update(alias_tokens)
            if usage.strip():
                existing.usage = usage.strip()
            if description.strip():
                existing.description = description.strip()
            entry = existing

        for token in sorted(entry.aliases):
            self._bind_alias(token, entry.handler, canonical)

    def _bind_alias(self, token: str, handler: CommandHandler, canonical: str) -> None:
        existing = self._handlers.get(token)
        if existing is not None and existing is not handler:
            self.add_plugin_error(
                f"Command alias conflict: `{token}` already exists, ignored in plugin `{self._active_plugin}`."
            )
            return
        self._handlers[token] = handler

    def set_fallback_handler(self, handler: FallbackHandler) -> None:
        self._fallback = handler

    def dispatch(self, context: EngineContext, query: str) -> bool:
        trimmed = query.strip()
        if not trimmed:
            return False

        first, _, content = trimmed.partition(" ")
        handler = self._handlers.get(first.lower())
        if handler is not None:
            handler(context, content.strip())
            return True

        if self._fallback is not None:
            return bool(self._fallback(context, trimmed))

        return False

    def help_entries(self) -> list[CommandHelpEntry]:
        rows: list[CommandHelpEntry] = []
        for command, entry in self._entries.items():
            aliases = sorted(alias for alias in entry.aliases if alias != command)
            rows.append(
                CommandHelpEntry(
                    command=command,
                    aliases=aliases,
                    usage=entry.usage,
                    description=entry.description,
                    plugin=entry.plugin,
                )
            )
        return sorted(rows, key=lambda item: item.command)

    def entries_by_plugin(self) -> dict[str, list[CommandHelpEntry]]:
        grouped: dict[str, list[CommandHelpEntry]] = {}
        for item in self.help_entries():
            grouped.setdefault(item.plugin, []).append(item)
        return grouped


def load_builtin_plugins(registry: CommandRegistry, context: EngineContext) -> None:
    modules = (
        "command_engine.plugins.core",
        "command_engine.plugins.shell",
        "command_engine.plugins.music",
        "command_engine.plugins.web",
        "command_engine.plugins.ai",
        "command_engine.plugins.read",
    )

    for module_name in modules:
        short_name = module_name.rsplit(".", maxsplit=1)[-1]
        registry.activate_plugin(f"builtin:{short_name}")
        try:
            module = importlib.import_module(module_name)
        except Exception as exc:  # noqa: BLE001
            registry.add_plugin_error(f"Failed loading `{module_name}`: {exc}")
            continue
        _invoke_register(module, registry, context, source=module_name)


def load_external_plugins(
    registry: CommandRegistry,
    context: EngineContext,
    plugin_dir: str,
) -> None:
    if plugin_dir.strip():
        path = Path(plugin_dir).expanduser()
    else:
        path = PLUGIN_DIR_PATH

    if not path.exists():
        return

    if not path.is_dir():
        registry.add_plugin_error(f"Plugin path is not a directory: {path}")
        return

    for file_path in sorted(path.glob("*.py"), key=lambda p: p.name.lower()):
        if file_path.name.startswith("_"):
            continue

        plugin_name = file_path.stem
        module_name = f"commander_external_plugin_{plugin_name}"
        spec = importlib.util.spec_from_file_location(module_name, str(file_path))
        if spec is None or spec.loader is None:
            registry.add_plugin_error(f"Failed to load plugin spec: {file_path}")
            continue

        module = importlib.util.module_from_spec(spec)
        registry.activate_plugin(f"external:{plugin_name}")
        try:
            spec.loader.exec_module(module)
        except Exception as exc:  # noqa: BLE001
            registry.add_plugin_error(f"Plugin `{plugin_name}` crashed on import: {exc}")
            continue

        _invoke_register(module, registry, context, source=str(file_path))


def _invoke_register(module: object, registry: CommandRegistry, context: EngineContext, source: str) -> None:
    register_fn = getattr(module, "register", None)
    if not callable(register_fn):
        registry.add_plugin_error(f"Plugin `{source}` has no callable `register(...)`.")
        return

    try:
        signature = inspect.signature(register_fn)
    except (ValueError, TypeError):
        signature = None

    try:
        if signature is None:
            register_fn(registry)
            return

        if len(signature.parameters) >= 2:
            register_fn(registry, context)
        else:
            register_fn(registry)
    except Exception as exc:  # noqa: BLE001
        registry.add_plugin_error(f"Plugin `{source}` register() failed: {exc}")
