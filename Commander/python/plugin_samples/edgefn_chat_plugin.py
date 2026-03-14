from __future__ import annotations

import json
import urllib.error
import urllib.request


def register(registry, context=None):
    registry.register_setting("aiProvider", "string", "AI Provider", "ai")
    registry.register_setting("aiBaseURL", "string", "AI Base URL", "ai")
    registry.register_setting("aiApiKey", "secret", "AI API Key", "ai")
    registry.register_setting("aiModel", "string", "AI Model", "ai")

    registry.register_command(
        "edge",
        handle_edge_chat,
        usage="edge <prompt>",
        description="Call OpenAI-compatible endpoint (e.g. edgefn) and return one completion.",
    )


def handle_edge_chat(context, content: str):
    prompt = content.strip()
    if not prompt:
        context.response["output"] = "Usage: edge <prompt>"
        return

    settings = context.settings
    base_url = str(settings.get("aiBaseURL") or "https://api.edgefn.net/v1/chat/completions")
    api_key = str(settings.get("aiApiKey") or "")
    model = str(settings.get("aiModel") or "DeepSeek-V3.2")

    if not api_key:
        context.response["output"] = (
            "Missing `aiApiKey`. Use `set ai_api_key <key>` or configure it in settings JSON."
        )
        return

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
    }

    request = urllib.request.Request(
        url=base_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        context.response["output"] = f"HTTP {exc.code}: {body}"
        return
    except Exception as exc:  # noqa: BLE001
        context.response["output"] = f"Request failed: {exc}"
        return

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        context.response["output"] = raw
        return

    message = extract_content(data)
    context.response["output"] = message or raw
    context.response["history_type"] = "ai"
    context.response["should_save_history"] = True
    context.response["is_ai_response"] = True


def extract_content(payload: dict) -> str:
    choices = payload.get("choices")
    if isinstance(choices, list) and choices:
        first = choices[0]
        if isinstance(first, dict):
            message = first.get("message")
            if isinstance(message, dict):
                content = message.get("content")
                if isinstance(content, str):
                    return content

    if isinstance(payload.get("output"), str):
        return payload["output"]

    return ""
