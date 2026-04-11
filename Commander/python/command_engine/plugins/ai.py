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
            "`ai save <name>` save current AI config profile",
            "`ai ls` list saved AI config profiles",
            "`ai ls <name>` or `ai show <name>` show one profile (without key)",
            "`ai use <name>` switch to a saved profile",
            "`ai rm <name>` remove a saved profile",
            "`ai <prompt>` force AI mode",
            f"`{alias_def} <word>` force dictionary mode",
            f"`{alias_ask} <question>` force AI mode alias",
            "Fallback routing: single English word -> dictionary; otherwise -> AI",
        ],
    )

    registry.register_command(
        "ai",
        handle_ai,
        usage="ai [status|models|save|ls|show|use|rm|<prompt>]",
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
    if head in {"save", "ls", "use", "rm", "show"}:
        context.response["output"] = handle_profile_command(context, head, tail)
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
    active_profile = current_profile_name(settings)
    use_gemini = (not provider and not base_url) or provider == "gemini"
    resolved_provider = "gemini" if use_gemini else "openai_compatible"

    lines = [
        "### AI Status",
        "",
        f"- Profile: `{active_profile or '(none)'}`",
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
                "- `ai save <name>`",
                "- `ai ls`",
                "- `ai use <name>`",
            ]
        )
    return "\n".join(lines)


def handle_profile_command(context: EngineContext, action: str, tail: str) -> str:
    if action == "save":
        return save_current_profile(context, tail)
    if action == "ls":
        return list_or_show_profile(context, tail)
    if action == "show":
        return show_profile(context, tail)
    if action == "use":
        return use_profile(context, tail)
    if action == "rm":
        return remove_profile(context, tail)
    return "Unknown action."


def save_current_profile(context: EngineContext, tail: str) -> str:
    name = normalize_profile_name(tail)
    if not name:
        return "Usage: `ai save <name>`"

    settings = context.settings
    provider = str(settings.get("aiProvider") or "").strip().lower()
    base_url = str(settings.get("aiBaseURL") or "").strip()
    model = str(settings.get("aiModel") or "").strip()
    api_key = str(settings.get("aiApiKey") or "").strip()
    system_prompt = str(settings.get("aiSystemPrompt") or "").strip()

    use_gemini = (not provider and not base_url) or provider == "gemini"
    resolved_provider = "gemini" if use_gemini else "openai_compatible"
    resolved_base_url = "" if use_gemini else (
        base_url or default_openai_base_url("openai_compatible")
    )
    resolved_model = model or ("gemini-1.5-flash" if use_gemini else "")

    profiles = load_profiles(settings)
    profiles[name] = {
        "provider": resolved_provider,
        "base_url": resolved_base_url,
        "model": resolved_model,
        "api_key": api_key,
        "system_prompt": system_prompt,
    }

    error = persist_profiles(profiles)
    if error:
        return error
    return f"Saved profile `{name}`."


def list_or_show_profile(context: EngineContext, tail: str) -> str:
    name = normalize_profile_name(tail)
    if name:
        return show_profile(context, name)

    profiles = load_profiles(context.settings)
    if not profiles:
        return (
            "No saved AI profiles.\n\n"
            "Use `ai save <name>` to save current provider/baseurl/model/key/system prompt."
        )

    lines = ["### AI Profiles", ""]
    for name in sorted(profiles):
        lines.append(f"- `{name}`")

    lines.extend(
        [
            "",
            "Commands:",
            "- `ai save <name>`",
            "- `ai ls <name>`",
            "- `ai use <name>`",
            "- `ai rm <name>`",
        ]
    )
    return "\n".join(lines)


def show_profile(context: EngineContext, tail: str) -> str:
    name = normalize_profile_name(tail)
    if not name:
        return "Usage: `ai show <name>`"

    profiles = load_profiles(context.settings)
    profile = profiles.get(name)
    if profile is None:
        return f"Profile `{name}` not found."

    provider = str(profile.get("provider") or "").strip().lower()
    system_prompt = str(profile.get("system_prompt") or "").strip()
    lines = [
        f"### AI Profile `{name}`",
        "",
        f"- Provider: `{profile.get('provider', '') or '(empty)'}`",
    ]
    if provider != "gemini":
        lines.append(f"- Base URL: `{profile.get('base_url', '') or '(empty)'}`")
    lines.extend(
        [
            f"- Model: `{profile.get('model', '') or '(empty)'}`",
            f"- System Prompt: `{'configured' if system_prompt else 'empty'}`",
        ]
    )
    return "\n".join(lines)


def use_profile(context: EngineContext, tail: str) -> str:
    name = normalize_profile_name(tail)
    if not name:
        return "Usage: `ai use <name>`"

    profiles = load_profiles(context.settings)
    profile = profiles.get(name)
    if profile is None:
        return f"Profile `{name}` not found."

    provider = str(profile.get("provider") or "").strip()
    base_url = str(profile.get("base_url") or "").strip()
    model = str(profile.get("model") or "").strip()
    api_key = str(profile.get("api_key") or "").strip()
    system_prompt = str(profile.get("system_prompt") or "").strip()

    updates = [
        {"key": "aiProvider", "value": provider, "value_type": "string"},
        {"key": "aiBaseURL", "value": base_url, "value_type": "string"},
        {"key": "aiModel", "value": model, "value_type": "string"},
        {"key": "aiApiKey", "value": api_key, "value_type": "string"},
        {"key": "aiSystemPrompt", "value": system_prompt, "value_type": "string"},
    ]
    context.response["setting_updates"] = updates

    try:
        update_user_config("aiProvider", provider)
        update_user_config("aiBaseURL", base_url)
        update_user_config("aiModel", model)
        update_user_config("aiApiKey", api_key)
        update_user_config("aiSystemPrompt", system_prompt)
        update_user_config("aiActiveProfile", name)
    except OSError as exc:
        return f"Applied profile `{name}` in memory; failed saving: {exc}"

    return f"Applied profile `{name}`."


def remove_profile(context: EngineContext, tail: str) -> str:
    name = normalize_profile_name(tail)
    if not name:
        return "Usage: `ai rm <name>`"

    profiles = load_profiles(context.settings)
    if name not in profiles:
        return f"Profile `{name}` not found."
    profiles.pop(name, None)
    error = persist_profiles(profiles)
    if error:
        return error
    active_profile = current_profile_name(context.settings)
    if active_profile == name:
        try:
            update_user_config("aiActiveProfile", "")
        except OSError as exc:
            return f"Removed profile `{name}`; failed clearing active profile: {exc}"
    return f"Removed profile `{name}`."


def normalize_profile_name(raw: str) -> str:
    text = raw.strip()
    if not text:
        return ""
    try:
        tokens = shlex.split(text)
    except ValueError:
        return ""
    if not tokens:
        return ""
    return tokens[0].strip().lower()


def current_profile_name(settings: dict[str, object]) -> str:
    name = normalize_profile_name(str(settings.get("aiActiveProfile") or ""))
    if not name:
        return ""
    profiles = load_profiles(settings)
    if name not in profiles:
        return ""
    return name


def load_profiles(settings: dict[str, object]) -> dict[str, dict[str, str]]:
    raw = settings.get("aiProfiles")
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

    profiles: dict[str, dict[str, str]] = {}
    for key, value in payload.items():
        if not isinstance(key, str) or not isinstance(value, dict):
            continue
        name = key.strip().lower()
        if not name:
            continue
        profiles[name] = {
            "provider": str(value.get("provider") or "").strip(),
            "base_url": str(value.get("base_url") or "").strip(),
            "model": str(value.get("model") or "").strip(),
            "api_key": str(value.get("api_key") or "").strip(),
            "system_prompt": str(value.get("system_prompt") or "").strip(),
        }

    return profiles


def persist_profiles(profiles: dict[str, dict[str, str]]) -> str | None:
    normalized: dict[str, dict[str, str]] = {}
    for name in sorted(profiles):
        item = profiles[name]
        provider = str(item.get("provider") or "").strip().lower()
        normalized_item = {
            "provider": provider,
            "model": str(item.get("model") or "").strip(),
            "api_key": str(item.get("api_key") or "").strip(),
            "system_prompt": str(item.get("system_prompt") or "").strip(),
        }
        if provider != "gemini":
            normalized_item["base_url"] = str(item.get("base_url") or "").strip()
        normalized[name] = normalized_item
    try:
        update_user_config("aiProfiles", normalized)
        return None
    except OSError as exc:
        return f"Failed saving profiles: {exc}"


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
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
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
