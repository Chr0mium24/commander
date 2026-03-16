from __future__ import annotations

import requests

from ..plugin_registry import CommandRegistry
from ..runtime import EngineContext


def register(registry: CommandRegistry, context: EngineContext | None = None) -> None:
    registry.register_setting("jinaReaderApiKey", "secret", "Jina Reader API Key", "plugins")
    registry.register_setting("jinaReaderBaseURL", "string", "Jina Reader Base URL", "plugins")
    registry.register_help_section(
        "Read Plugin",
        [
            "`read <url>` fetch markdown via Jina Reader",
            "`md <url>` alias for read",
            "`jina <url>` alias for read",
            "`set jina_reader_api_key <token>` configure token",
            "`set jina_reader_base_url <url>` override endpoint prefix",
        ],
    )
    registry.register_command(
        "read",
        handle_md_reader,
        aliases=["md", "jina"],
        usage="read <url>",
        description="Fetch page markdown via Jina Reader API.",
    )


def handle_md_reader(context: EngineContext, content: str) -> None:
    target = content.strip()
    if not target:
        context.response["output"] = "Usage: read <url>"
        return

    endpoint = resolve_endpoint(target, context.settings)
    base_url = str(context.settings.get("jinaReaderBaseURL") or "https://r.jina.ai/").strip()
    api_key = str(context.settings.get("jinaReaderApiKey") or "").strip()

    headers = {
        "User-Agent": "Commander/1.0",
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    try:
        response = requests.get(endpoint, headers=headers, timeout=45)
        payload = response.text
    except requests.RequestException as exc:
        context.response["output"] = (
            f"Jina Reader request failed: {exc}\n\n"
            f"Endpoint: `{endpoint}`\n\n"
            "Check `set jina_reader_api_key <token>` and network connectivity."
        )
        return

    if response.status_code >= 400:
        body = payload
        context.response["output"] = (
            f"Jina Reader HTTP {response.status_code}\n\n"
            f"Endpoint: `{endpoint}`\n\n"
            f"{body}"
        )
        return

    context.response["output"] = payload if payload.strip() else "Done (No Output)"
    context.response["history_type"] = "md"
    context.response["history_input"] = f"read {target}"
    context.response["should_save_history"] = True

    if not api_key and "r.jina.ai" in base_url:
        context.response["output"] += (
            "\n\n---\nTip: set token with `set jina_reader_api_key <token>` "
            "if your endpoint requires authorization."
        )


def resolve_endpoint(target: str, settings: dict[str, object]) -> str:
    trimmed = target.strip()
    if trimmed.startswith("https://r.jina.ai/") or trimmed.startswith("http://r.jina.ai/"):
        return trimmed

    normalized_target = trimmed
    if "://" not in trimmed:
        normalized_target = f"https://{trimmed}"

    base_url = str(settings.get("jinaReaderBaseURL") or "https://r.jina.ai/").strip()
    if not base_url:
        base_url = "https://r.jina.ai/"

    if not base_url.endswith("/"):
        base_url += "/"

    return f"{base_url}{normalized_target}"
