from __future__ import annotations

import re

from .constants import SETTING_SCHEMA
from .plugin_registry import CommandHelpEntry
from .utils import camel_to_snake


def dictionary_prompt(word: str) -> str:
    return (
        f"You are a professional dictionary engine. Explain the word: \"{word}\".\n\n"
        "Format requirements:\n"
        "1. Headword with IPA pronunciation.\n"
        "2. Chinese definition (Simplified Chinese).\n"
        "3. Etymology in Chinese.\n"
        "4. Concise English definition.\n"
        "5. Two example sentences.\n"
        "Output in Markdown and avoid filler text."
    )


def is_single_word(text: str) -> bool:
    if " " in text:
        return False
    if re.search(r"[\u4e00-\u9fff]", text):
        return False
    return re.fullmatch(r"[A-Za-z][A-Za-z'\-]*", text) is not None


def help_text(
    aliases: dict[str, str],
    commands: list[CommandHelpEntry],
    setting_schema: list[dict[str, str]] | None = None,
) -> str:
    source_schema = setting_schema if setting_schema is not None else SETTING_SCHEMA
    key_list = sorted(
        {
            camel_to_snake(str(item.get("key", "")))
            for item in source_schema
            if item.get("key")
        }
    )
    keys_line = ", ".join(f"`{key}`" for key in key_list)

    command_rows: list[str] = []
    for item in commands:
        if item.command in {"help", "hist", "quit", "scripts", "set"}:
            continue
        usage = item.usage or item.command
        suffix = f" ({item.description})" if item.description else ""
        alias_part = f" aliases: {', '.join(f'`{alias}`' for alias in item.aliases)}" if item.aliases else ""
        command_rows.append(f"- `{usage}`{suffix}{alias_part}")

    dynamic_block = "\n".join(command_rows) if command_rows else "- None"

    return f"""### Commander Python Engine

Default behavior:
- Single English word: dictionary mode
- Multi-word query: AI mode

Commands:
- `help` show this help
- `hist` open history
- `scripts` list scripts from script directory
- `set` open settings window
- `set get <key>` read one setting
- `set <key> <value>` update one setting
- `set list` print full schema
- `set file` print config/plugin paths
- `set schema_json` return machine-readable schema payload
- `run <command>` run and capture output directly
- `run <command> &` run inside process panel (interactive/stop-able)
- `terminal [command]` open process panel terminal (no command = blank shell)
- `{aliases['py']} <code>` run python snippet
- `{aliases['def']} <word>` force dictionary mode
- `{aliases['ask']} <question>` force AI mode
- `{aliases['ser']} <term>` open Google search
- `plugins` show plugin load status
- `quit` exit app

Settable keys:
{keys_line}

Plugin commands:
{dynamic_block}
"""
