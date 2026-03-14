from __future__ import annotations

import urllib.parse

from ..runtime import EngineContext
from ..plugin_registry import CommandRegistry


def register(registry: CommandRegistry, context: EngineContext | None = None) -> None:
    alias_ser = "ser"
    if context is not None:
        alias_ser = context.aliases.get("ser", "ser").strip() or "ser"

    registry.register_command(
        alias_ser,
        handle_search,
        usage=f"{alias_ser} <search terms>",
        description="Open Google search for the given terms.",
    )


def handle_search(context: EngineContext, content: str) -> None:
    term = content.strip()
    if not term:
        alias_ser = context.aliases.get("ser", "ser")
        context.response["output"] = f"Usage: {alias_ser} <search terms>"
        return

    encoded = urllib.parse.quote_plus(term)
    url = f"https://www.google.com/search?q={encoded}"
    context.response["open_url"] = url
    context.response["output"] = f"Opened Web Search: {url}"
    context.response["history_type"] = "ser"
    context.response["should_save_history"] = True
