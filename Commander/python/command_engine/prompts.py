from __future__ import annotations

import re


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


def help_text(aliases: dict[str, str]) -> str:
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
- `run <command>` run and capture output directly
- `run <command> &` run inside process panel (interactive/stop-able)
- `{aliases['py']} <code>` run python snippet
- `{aliases['def']} <word>` force dictionary mode
- `{aliases['ask']} <question>` force AI mode
- `{aliases['ser']} <term>` open Google search
- `quit` exit app

Settable keys:
`alias_py`, `alias_def`, `alias_ask`, `alias_ser`, `python_path`, `script_dir`,
`gemini_key`, `gemini_model`, `gemini_proxy`, `history_limit`, `auto_copy`
"""
