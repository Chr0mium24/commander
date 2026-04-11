from __future__ import annotations

import json
from urllib import error as urllib_error
from urllib import parse as urllib_parse
from urllib import request as urllib_request

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
            "`ai models` list models from the configured OpenAI-compatible endpoint",
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
    if payload.lower() == "models":
        context.response["output"] = render_openai_models(context.settings)
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
                "- `ai models`",
            ]
        )
    return "\n".join(lines)


def render_openai_models(settings: dict[str, object]) -> str:
    request = resolve_ai_request(settings)
    if request.get("kind") != "openai_compatible":
        return "Model listing is available only for `openai_compatible` provider."

    api_key = str(request.get("api_key") or "").strip()
    if not api_key:
        return "Missing `aiApiKey`. Use `set ai_api_key <key>`."

    base_url = str(request.get("base_url") or "").strip()
    models_url = resolve_openai_models_url(base_url)
    if not models_url:
        return "Invalid `aiBaseURL`. Please set a valid OpenAI-compatible chat completions URL."

    request_obj = urllib_request.Request(
        models_url,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
            "User-Agent": "curl/8.7.1",
        },
        method="GET",
    )

    try:
        with urllib_request.urlopen(request_obj, timeout=20) as response:
            raw = response.read().decode("utf-8", errors="replace")
    except urllib_error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return f"Model list request failed ({exc.code}).\n{body}".strip()
    except urllib_error.URLError as exc:
        return f"Model list request failed: {exc.reason}"

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return f"Model list request returned non-JSON response:\n{raw}".strip()

    models = extract_model_ids(payload)
    if not models:
        return "No models found in provider response."

    preview_limit = 80
    preview = models[:preview_limit]
    lines = [
        "### OpenAI-Compatible Models",
        "",
        f"- Endpoint: `{models_url}`",
        f"- Count: `{len(models)}`",
        "",
    ]
    lines.extend(f"- `{model}`" for model in preview)
    if len(models) > preview_limit:
        lines.append(f"- `... and {len(models) - preview_limit} more`")
    return "\n".join(lines)


def resolve_openai_models_url(base_url: str) -> str:
    parsed = urllib_parse.urlparse(base_url)
    if not parsed.scheme or not parsed.netloc:
        return ""

    path = parsed.path or ""
    if path.endswith("/chat/completions"):
        path = path[: -len("/chat/completions")] + "/models"
    elif path.endswith("/completions"):
        path = path[: -len("/completions")] + "/models"
    elif path.endswith("/v1"):
        path = f"{path}/models"
    elif path.endswith("/models"):
        pass
    elif path.endswith("/"):
        path = f"{path}models"
    elif path:
        path = f"{path}/models"
    else:
        path = "/v1/models"

    return urllib_parse.urlunparse((parsed.scheme, parsed.netloc, path, "", "", ""))


def extract_model_ids(payload: object) -> list[str]:
    if not isinstance(payload, dict):
        return []

    candidates: list[object] = []
    data = payload.get("data")
    if isinstance(data, list):
        candidates = data
    elif isinstance(payload.get("models"), list):
        candidates = payload["models"]

    model_ids: list[str] = []
    for item in candidates:
        if not isinstance(item, dict):
            continue
        model_id = item.get("id")
        if isinstance(model_id, str):
            trimmed = model_id.strip()
            if trimmed:
                model_ids.append(trimmed)

    return sorted(set(model_ids))
