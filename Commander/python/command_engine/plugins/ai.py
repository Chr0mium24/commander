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

    registry.register_help_section(
        "AI Commands",
        [
            "`ai` or `ai status` show active provider/model config",
            "`ai <prompt>` force AI mode",
            f"`{alias_def} <word>` force dictionary mode",
            f"`{alias_ask} <question>` force AI mode alias",
            "Fallback routing: single English word -> dictionary; otherwise -> AI",
        ],
    )

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
    system_prompt = str(settings.get("aiSystemPrompt") or "").strip()

    proxy_url = str(settings.get("geminiProxy") or "").strip()

    use_gemini = (not provider and not base_url) or provider == "gemini"
    if use_gemini:
        return {
            "kind": "gemini",
            "provider": "gemini",
            "base_url": "https://generativelanguage.googleapis.com",
            "api_key": ai_api_key,
            "model": ai_model or "gemini-1.5-flash",
            "proxy_url": proxy_url,
            "system_prompt": system_prompt,
        }

    resolved_base_url = base_url or default_openai_base_url("openai_compatible")
    return {
        "kind": "openai_compatible",
        "provider": "openai_compatible",
        "base_url": resolved_base_url,
        "api_key": ai_api_key,
        "model": ai_model,
        "proxy_url": proxy_url,
        "system_prompt": system_prompt,
    }


def default_openai_base_url(_provider: str) -> str:
    return "https://api.openai.com/v1/chat/completions"


def apply_ai_request(context: EngineContext, request: dict[str, str]) -> None:
    context.response["ai_request_kind"] = request.get("kind", "")
    context.response["ai_request_provider"] = request.get("provider", "")
    context.response["ai_request_base_url"] = request.get("base_url", "")
    context.response["ai_request_api_key"] = request.get("api_key", "")
    context.response["ai_request_model"] = request.get("model", "")
    context.response["ai_request_proxy_url"] = request.get("proxy_url", "")
    context.response["ai_request_system_prompt"] = request.get("system_prompt", "")


def render_ai_status(context: EngineContext) -> str:
    settings = context.settings
    provider = str(settings.get("aiProvider") or "").strip().lower()
    base_url = str(settings.get("aiBaseURL") or "").strip()
    ai_model = str(settings.get("aiModel") or "").strip()
    ai_api_key = str(settings.get("aiApiKey") or "").strip()
    has_system_prompt = bool(str(settings.get("aiSystemPrompt") or "").strip())
    use_gemini = (not provider and not base_url) or provider == "gemini"
    resolved_provider = "gemini" if use_gemini else "openai_compatible"

    lines = [
        "### AI Status",
        "",
        f"- Provider: `{resolved_provider}`",
    ]

    if use_gemini:
        lines.append(f"- Model: `{ai_model or 'gemini-1.5-flash'}`")
        lines.append(f"- Key: `{'configured' if ai_api_key else 'empty'}`")
    else:
        resolved_base_url = base_url or default_openai_base_url("openai_compatible")
        lines.append(f"- Base URL: `{resolved_base_url}`")
        lines.append(f"- Model: `{ai_model or '(empty)'}`")
        lines.append(f"- Key: `{'configured' if ai_api_key else 'empty'}`")
    lines.append(
        f"- System Prompt: `{'configured' if has_system_prompt else 'empty'}`"
    )

    lines.extend(["", "Update via:"])
    if use_gemini:
        lines.extend(
            [
                "- `set ai_provider openai_compatible | gemini`",
                "- `set ai_model <model>`",
                "- `set ai_api_key <key>`",
                "- `set ai_system_prompt <text>`",
            ]
        )
    else:
        lines.extend(
            [
                "- `set ai_provider openai_compatible | gemini`",
                "- `set ai_base_url <url>`",
                "- `set ai_model <model>`",
                "- `set ai_api_key <key>`",
                "- `set ai_system_prompt <text>`",
            ]
        )
    return "\n".join(lines)
