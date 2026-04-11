from __future__ import annotations

import json
import shlex
from requests import RequestException
from requests import get
from requests.compat import urlparse, urlunparse
from requests.exceptions import HTTPError

from ..config import update_user_config
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
            "`ai model` list saved model presets",
            "`ai model save <name> [model]` save a preset",
            "`ai model use <name>` switch to a saved preset",
            "`ai model rm <name>` delete a saved preset",
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

    parts = payload.split(maxsplit=1)
    head = parts[0].lower() if parts else ""
    tail = parts[1] if len(parts) > 1 else ""

    if head == "models":
        context.response["output"] = render_openai_models(context.settings)
        context.response["should_save_history"] = False
        return
    if head == "model":
        context.response["output"] = handle_model_preset_command(context, tail)
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


def handle_model_preset_command(context: EngineContext, content: str) -> str:
    presets = load_model_presets(context.settings)
    current_model = str(context.settings.get("aiModel") or "").strip()

    stripped = content.strip()
    if not stripped:
        return render_model_presets(presets, current_model)

    try:
        tokens = shlex.split(stripped)
    except ValueError as exc:
        return f"Invalid syntax: {exc}"

    if not tokens:
        return render_model_presets(presets, current_model)

    action = tokens[0].lower()
    if action in {"list", "ls"}:
        return render_model_presets(presets, current_model)

    if action in {"save", "add"}:
        if len(tokens) < 2:
            return "Usage: `ai model save <name> [model]`"
        name = normalize_preset_name(tokens[1])
        if not name:
            return "Preset name cannot be empty."
        model = " ".join(tokens[2:]).strip() if len(tokens) > 2 else current_model
        if not model:
            return "Model cannot be empty. Use `ai model save <name> <model>`."
        presets[name] = model
        save_error = save_model_presets(presets)
        if save_error is not None:
            return save_error
        return f"Saved preset `{name}` -> `{model}`."

    if action in {"use", "switch"}:
        if len(tokens) < 2:
            return "Usage: `ai model use <name>`"
        name = normalize_preset_name(tokens[1])
        model = presets.get(name)
        if not model:
            return f"Preset `{name}` not found."
        context.response["setting_updates"] = [
            {"key": "aiModel", "value": model, "value_type": "string"}
        ]
        try:
            update_user_config("aiModel", model)
            return f"Switched model to `{model}` via preset `{name}`."
        except OSError as exc:
            return f"Switched model to `{model}` in memory; failed saving: {exc}"

    if action in {"rm", "del", "delete", "remove"}:
        if len(tokens) < 2:
            return "Usage: `ai model rm <name>`"
        name = normalize_preset_name(tokens[1])
        if name not in presets:
            return f"Preset `{name}` not found."
        removed = presets.pop(name)
        save_error = save_model_presets(presets)
        if save_error is not None:
            return save_error
        return f"Removed preset `{name}` (`{removed}`)."

    return (
        "Unknown model action. Use one of:\n"
        "- `ai model`\n"
        "- `ai model save <name> [model]`\n"
        "- `ai model use <name>`\n"
        "- `ai model rm <name>`"
    )


def normalize_preset_name(raw: str) -> str:
    return raw.strip().lower()


def load_model_presets(settings: dict[str, object]) -> dict[str, str]:
    raw = settings.get("aiModelPresets")
    payload: object = raw
    if isinstance(raw, str):
        text = raw.strip()
        if not text:
            return {}
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            return {}

    if not isinstance(payload, dict):
        return {}

    presets: dict[str, str] = {}
    for key, value in payload.items():
        if not isinstance(key, str) or not isinstance(value, str):
            continue
        name = normalize_preset_name(key)
        model = value.strip()
        if name and model:
            presets[name] = model
    return presets


def save_model_presets(presets: dict[str, str]) -> str | None:
    normalized = {name: presets[name] for name in sorted(presets)}
    try:
        update_user_config("aiModelPresets", normalized)
        return None
    except OSError as exc:
        return f"Failed saving model presets: {exc}"


def render_model_presets(presets: dict[str, str], current_model: str) -> str:
    lines = [
        "### AI Model Presets",
        "",
        f"- Current: `{current_model or '(empty)'}`",
        "",
    ]

    if not presets:
        lines.append("- No presets saved.")
    else:
        for name in sorted(presets):
            marker = " (active)" if current_model and presets[name] == current_model else ""
            lines.append(f"- `{name}` -> `{presets[name]}`{marker}")

    lines.extend(
        [
            "",
            "Commands:",
            "- `ai model save <name> [model]`",
            "- `ai model use <name>`",
            "- `ai model rm <name>`",
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

    try:
        response = get(
            models_url,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Accept": "application/json",
                "User-Agent": "curl/8.7.1",
            },
            timeout=20,
        )
        raw = response.text
        response.raise_for_status()
    except HTTPError as exc:
        body = exc.response.text if exc.response is not None else ""
        status_code = exc.response.status_code if exc.response is not None else "unknown"
        return f"Model list request failed ({status_code}).\n{body}".strip()
    except RequestException as exc:
        return f"Model list request failed: {exc}"

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
    parsed = urlparse(base_url)
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

    return urlunparse((parsed.scheme, parsed.netloc, path, "", "", ""))


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
