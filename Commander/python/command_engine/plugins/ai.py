from __future__ import annotations

from ..prompts import dictionary_prompt, is_single_word
from ..runtime import EngineContext
from ..plugin_registry import CommandRegistry


def register(registry: CommandRegistry, context: EngineContext | None = None) -> None:
    alias_def = "def"
    alias_ask = "ask"
    if context is not None:
        alias_def = context.aliases.get("def", "def").strip() or "def"
        alias_ask = context.aliases.get("ask", "ask").strip() or "ask"

    registry.register_command(
        "ai",
        handle_ai,
        usage="ai [status|<prompt>]",
        description="Show active AI provider/status or force AI mode with a prompt.",
    )
    registry.register_command(
        alias_def,
        handle_def,
        usage=f"{alias_def} <word>",
        description="Force dictionary mode.",
    )
    registry.register_command(
        alias_ask,
        handle_ask,
        usage=f"{alias_ask} <question>",
        description="Force AI mode.",
    )
    registry.set_fallback_handler(handle_fallback)


def handle_ai(context: EngineContext, content: str) -> None:
    payload = content.strip()
    if not payload or payload.lower() == "status":
        context.response["output"] = render_ai_status(context)
        context.response["should_save_history"] = False
        return

    _route_ask(context, payload)


def handle_def(context: EngineContext, content: str) -> None:
    word = content.strip()
    if not word:
        alias_def = context.aliases.get("def", "def")
        context.response["output"] = f"Usage: {alias_def} <word>"
        return
    _route_dictionary(context, word)


def handle_ask(context: EngineContext, content: str) -> None:
    prompt = content.strip()
    if not prompt:
        alias_ask = context.aliases.get("ask", "ask")
        context.response["output"] = f"Usage: {alias_ask} <question>"
        return
    _route_ask(context, prompt)


def handle_fallback(context: EngineContext, query: str) -> bool:
    trimmed = query.strip()
    if not trimmed:
        return False

    if is_single_word(trimmed):
        _route_dictionary(context, trimmed)
    else:
        _route_ask(context, trimmed)
    return True


def _route_dictionary(context: EngineContext, word: str) -> None:
    ai_request = resolve_ai_request(context.settings)
    context.response["defer_ai"] = True
    context.response["ai_prompt"] = dictionary_prompt(word)
    context.response["output"] = "Thinking..."
    context.response["history_type"] = "def"
    apply_ai_request(context, ai_request)


def _route_ask(context: EngineContext, prompt: str) -> None:
    ai_request = resolve_ai_request(context.settings)
    context.response["defer_ai"] = True
    context.response["ai_prompt"] = prompt
    context.response["output"] = "Thinking..."
    context.response["history_type"] = "ai"
    apply_ai_request(context, ai_request)


def resolve_ai_request(settings: dict[str, object]) -> dict[str, str]:
    provider = str(settings.get("aiProvider") or "").strip().lower()
    base_url = str(settings.get("aiBaseURL") or "").strip()
    ai_api_key = str(settings.get("aiApiKey") or "").strip()
    ai_model = str(settings.get("aiModel") or "").strip()

    gemini_api_key = str(settings.get("geminiApiKey") or "").strip()
    gemini_model = str(settings.get("geminiModel") or "").strip() or "gemini-1.5-flash"
    proxy_url = str(settings.get("geminiProxy") or "").strip()

    use_gemini = (not provider and not base_url) or provider == "gemini"
    if use_gemini:
        return {
            "kind": "gemini",
            "provider": "gemini",
            "base_url": "https://generativelanguage.googleapis.com",
            "api_key": gemini_api_key,
            "model": gemini_model,
            "proxy_url": proxy_url,
        }

    normalized_provider = provider or "openai_compatible"
    resolved_base_url = base_url or default_openai_base_url(normalized_provider)
    return {
        "kind": "openai_compatible",
        "provider": normalized_provider,
        "base_url": resolved_base_url,
        "api_key": ai_api_key,
        "model": ai_model,
        "proxy_url": proxy_url,
    }


def default_openai_base_url(provider: str) -> str:
    if provider in {"edge", "edgefn"}:
        return "https://api.edgefn.net/v1/chat/completions"
    return "https://api.openai.com/v1/chat/completions"


def apply_ai_request(context: EngineContext, request: dict[str, str]) -> None:
    context.response["ai_request_kind"] = request.get("kind", "")
    context.response["ai_request_provider"] = request.get("provider", "")
    context.response["ai_request_base_url"] = request.get("base_url", "")
    context.response["ai_request_api_key"] = request.get("api_key", "")
    context.response["ai_request_model"] = request.get("model", "")
    context.response["ai_request_proxy_url"] = request.get("proxy_url", "")


def render_ai_status(context: EngineContext) -> str:
    settings = context.settings
    provider = str(settings.get("aiProvider") or "").strip()
    base_url = str(settings.get("aiBaseURL") or "").strip()
    model = str(settings.get("aiModel") or "").strip()
    gemini_model = str(settings.get("geminiModel") or "").strip()

    if not provider:
        provider = "openai_compatible" if base_url else "gemini"

    lines = [
        "### AI Status",
        "",
        f"- Provider: `{provider}`",
    ]

    if provider == "gemini":
        lines.append(f"- Model: `{gemini_model or 'gemini-1.5-flash'}`")
        lines.append("- Key: `geminiApiKey`")
    else:
        lines.append(f"- Base URL: `{base_url or '(empty)'}`")
        lines.append(f"- Model: `{model or '(empty)'}`")
        lines.append("- Key: `aiApiKey`")

    lines.extend(
        [
            "",
            "Update via:",
            "- `set ai_provider <name>`",
            "- `set ai_base_url <url>`",
            "- `set ai_model <model>`",
            "- `set ai_api_key <key>`",
            "- `set gemini_model <model>`",
            "- `set gemini_key <key>`",
        ]
    )
    return "\n".join(lines)
