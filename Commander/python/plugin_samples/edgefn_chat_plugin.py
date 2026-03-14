from __future__ import annotations

import json

import requests


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

    try:
        response = requests.post(
            base_url,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=60,
        )
        raw = response.text
    except requests.RequestException as exc:
        context.response["output"] = f"Request failed: {exc}"
        return

    if response.status_code >= 400:
        context.response["output"] = f"HTTP {response.status_code}: {raw}"
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
