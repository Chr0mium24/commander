from __future__ import annotations

import urllib.parse
from typing import Any

from .constants import DEFAULT_PYTHON
from .executors import execute_python_snippet, list_scripts, resolve_run_command
from .prompts import dictionary_prompt, help_text, is_single_word
from .settings import handle_set_command
from .utils import base_response, coalesce, fenced


def dispatch(query: str, settings: dict[str, Any]) -> dict[str, Any]:
    response = base_response()
    response["history_input"] = query

    trimmed = query.strip()
    if not trimmed:
        return response

    alias_py = str(coalesce(settings, "aliasPy", "py") or "py")
    alias_def = str(coalesce(settings, "aliasDef", "def") or "def")
    alias_ask = str(coalesce(settings, "aliasAsk", "ask") or "ask")
    alias_ser = str(coalesce(settings, "aliasSer", "ser") or "ser")

    first, _, content = trimmed.partition(" ")
    command = first.lower()

    py_command = alias_py.lower()
    def_command = alias_def.lower()
    ask_command = alias_ask.lower()
    ser_command = alias_ser.lower()

    python_path = str(coalesce(settings, "pythonPath", DEFAULT_PYTHON) or DEFAULT_PYTHON)
    script_dir = str(coalesce(settings, "scriptDirectory", "") or "")

    aliases = {"py": alias_py, "def": alias_def, "ask": alias_ask, "ser": alias_ser}

    if command == "quit":
        response["should_quit"] = True
        return response

    if command == "hist":
        response["show_history"] = True
        return response

    if command == "help":
        response["output"] = help_text(aliases)
        return response

    if command == "scripts":
        if not script_dir:
            response["output"] = "Script directory is not configured. Set it in Settings."
            return response

        names = list_scripts(script_dir)
        if not names:
            response["output"] = f"No .sh/.py scripts found in: {script_dir}"
            return response

        lines = "\n".join(f"- `{name}`" for name in names)
        response["output"] = f"### Scripts in `{script_dir}`\n\n{lines}"
        return response

    if command == "set":
        return handle_set_command(content, settings, response)

    if command == py_command:
        code = content.strip()
        result = execute_python_snippet(code, python_path)
        response["output"] = "\\n".join([
            "### Python Output",
            fenced("text", result),
        ])
        response["history_type"] = "py"
        response["should_save_history"] = True
        return response

    if command == "run":
        run_input = content.strip()
        if not run_input:
            response["output"] = "Usage: run <command or script_name>"
            return response

        final_command, run_in_background = resolve_run_command(run_input, script_dir, python_path)
        if not final_command:
            response["output"] = "Usage: run <command or script_name>"
            return response

        response["defer_shell"] = True
        response["shell_command"] = final_command
        response["shell_run_in_background"] = run_in_background
        response["output"] = "Running..."
        response["history_type"] = "run"
        response["should_save_history"] = False
        return response

    if command == ser_command:
        term = content.strip()
        if not term:
            response["output"] = f"Usage: {alias_ser} <search terms>"
            return response

        encoded = urllib.parse.quote_plus(term)
        url = f"https://www.google.com/search?q={encoded}"
        response["open_url"] = url
        response["output"] = f"Opened Web Search: {url}"
        response["history_type"] = "ser"
        response["should_save_history"] = True
        return response

    def route_dictionary(word: str) -> None:
        response["defer_ai"] = True
        response["ai_prompt"] = dictionary_prompt(word)
        response["output"] = "Thinking..."
        response["history_type"] = "def"

    def route_ask(prompt: str) -> None:
        response["defer_ai"] = True
        response["ai_prompt"] = prompt
        response["output"] = "Thinking..."
        response["history_type"] = "ai"

    if command == def_command:
        word = content.strip()
        if not word:
            response["output"] = f"Usage: {alias_def} <word>"
            return response
        route_dictionary(word)
        return response

    if command == ask_command:
        prompt = content.strip()
        if not prompt:
            response["output"] = f"Usage: {alias_ask} <question>"
            return response
        route_ask(prompt)
        return response

    if is_single_word(trimmed):
        route_dictionary(trimmed)
    else:
        route_ask(trimmed)

    return response
