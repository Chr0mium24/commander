from __future__ import annotations

import re

from .constants import SETTING_SCHEMA
from .plugin_registry import PluginHelpSection
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
    setting_schema: list[dict[str, str]] | None = None,
    plugin_sections: list[PluginHelpSection] | None = None,
    active_plugins: list[str] | None = None,
    skipped_plugins: list[str] | None = None,
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

    loaded = active_plugins or []
    skipped = skipped_plugins or []
    sections = plugin_sections or []

    lines: list[str] = [
        "### Commander Python Engine",
        "",
        "Aliases:",
        f"- Python: `{aliases['py']}`",
        f"- Dictionary: `{aliases['def']}`",
        f"- Ask: `{aliases['ask']}`",
        f"- Search: `{aliases['ser']}`",
        "",
        "Settable keys:",
        keys_line or "(none)",
    ]

    if loaded:
        lines.extend(["", "Active plugins:"])
        lines.extend(f"- `{name}`" for name in loaded)

    if skipped:
        lines.extend(["", "Skipped plugins:"])
        lines.extend(f"- `{name}`" for name in skipped)

    if sections:
        grouped: dict[str, list[PluginHelpSection]] = {}
        for section in sections:
            grouped.setdefault(section.plugin, []).append(section)

        lines.append("")
        lines.append("Plugin docs:")
        for plugin_name in sorted(grouped.keys()):
            lines.append("")
            lines.append(f"#### {plugin_name}")
            for section in grouped[plugin_name]:
                lines.append(f"- **{section.title}**")
                lines.extend(f"  - {line}" for line in section.lines)
    else:
        lines.extend(["", "Plugin docs:", "- None"])

    return "\n".join(lines)
