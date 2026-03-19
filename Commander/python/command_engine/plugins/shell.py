from __future__ import annotations

from pathlib import Path

from ..executors import execute_python_snippet, execute_shell, resolve_run_command
from ..runtime import EngineContext
from ..utils import fenced
from ..plugin_registry import CommandRegistry

IMAGE_SUFFIXES = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".bmp",
    ".tif",
    ".tiff",
    ".heic",
    ".heif",
    ".icns",
}


def register(registry: CommandRegistry, context: EngineContext | None = None) -> None:
    alias_py = "py"
    if context is not None:
        alias_py = context.aliases.get("py", "py").strip() or "py"

    registry.register_help_section(
        "Shell Commands",
        [
            "`run <command>` run shell command and capture output",
            "`run <command> &` open interactive process window",
            "`terminal [command]` always use process window (empty opens blank shell)",
            "`note [title]` open scratch note window",
            "`todo [text]` open todo list or add one item",
            "`preview <path>` preview image or file in its own window",
            f"`{alias_py} <python code>` run inline python snippet",
        ],
    )

    registry.register_command(
        alias_py,
        handle_py,
        usage=f"{alias_py} <python code>",
        description="Run inline Python code and return output.",
    )
    registry.register_command(
        "run",
        handle_run,
        usage="run <command or script_name> [&]",
        description="Run shell command (`&` to open interactive process panel).",
    )
    registry.register_command(
        "terminal",
        handle_terminal,
        aliases=["term", "t"],
        usage="terminal [command or script_name]",
        description="Open interactive process window (empty command opens a blank shell).",
    )
    registry.register_command(
        "note",
        handle_note,
        usage="note [title]",
        description="Open a scratch note window.",
    )
    registry.register_command(
        "todo",
        handle_todo,
        usage="todo [text]",
        description="Open the todo list or append one todo item.",
    )
    registry.register_command(
        "preview",
        handle_preview,
        usage="preview <path>",
        description="Preview a local image or file in its own window.",
    )


def handle_py(context: EngineContext, content: str) -> None:
    code = content.strip()
    result = execute_python_snippet(code, context.python_path)
    context.response["output"] = "\n".join(
        [
            "### Python Output",
            fenced("text", result),
        ]
    )
    context.response["history_type"] = "py"
    context.response["should_save_history"] = True


def handle_run(context: EngineContext, content: str) -> None:
    run_input = content.strip()
    if not run_input:
        context.response["output"] = "Usage: run <command or script_name>"
        return

    final_command, run_in_terminal = resolve_run_command(
        run_input, context.script_dir, context.python_path
    )
    if not final_command:
        context.response["output"] = "Usage: run <command or script_name>"
        return

    context.response["history_type"] = "run"

    if run_in_terminal:
        context.response["defer_shell"] = True
        context.response["shell_command"] = final_command
        context.response["shell_run_in_background"] = False
        context.response["progress_presentation"] = "terminal"
        context.response["progress_title"] = run_input
        context.response["output"] = "Running..."
        context.response["should_save_history"] = False
        return

    output = execute_shell(final_command, run_in_background=False)
    context.response["output"] = output
    context.response["should_save_history"] = True


def handle_terminal(context: EngineContext, content: str) -> None:
    run_input = content.strip()
    if run_input:
        final_command, _ = resolve_run_command(
            run_input, context.script_dir, context.python_path
        )
        if not final_command:
            context.response["output"] = "Usage: terminal [command or script_name]"
            return
    else:
        final_command = "exec ${SHELL:-/bin/zsh} -i"

    context.response["history_type"] = "run"
    context.response["defer_shell"] = True
    context.response["shell_command"] = final_command
    context.response["shell_run_in_background"] = False
    context.response["progress_presentation"] = "terminal"
    context.response["progress_title"] = run_input or "terminal"
    context.response["output"] = "Running in terminal..."
    context.response["should_save_history"] = False


def handle_note(context: EngineContext, content: str) -> None:
    title = content.strip() or "Scratchpad"
    history_input = f"note {content.strip()}".strip() or "note"

    context.response["open_panel"] = True
    context.response["panel_presentation"] = "note"
    context.response["panel_title"] = title
    context.response["panel_text"] = ""
    context.response["history_type"] = "note"
    context.response["history_input"] = history_input


def handle_todo(context: EngineContext, content: str) -> None:
    item_text = content.strip()
    history_input = f"todo {item_text}".strip() or "todo"

    context.response["open_panel"] = True
    context.response["panel_presentation"] = "todo"
    context.response["panel_title"] = "Todo"
    context.response["panel_text"] = item_text
    context.response["history_type"] = "todo"
    context.response["history_input"] = history_input


def handle_preview(context: EngineContext, content: str) -> None:
    raw = content.strip()
    if not raw:
        context.response["output"] = "Usage: preview <path>"
        return

    candidate = Path(raw).expanduser()
    path = candidate.resolve() if candidate.is_absolute() else (Path.cwd() / candidate).resolve()
    if not path.exists() or not path.is_file():
        context.response["output"] = f"File not found: {path}"
        return

    suffix = path.suffix.lower()
    presentation = "image" if suffix in IMAGE_SUFFIXES else "file"

    context.response["open_panel"] = True
    context.response["panel_presentation"] = presentation
    context.response["panel_title"] = path.name
    context.response["panel_path"] = str(path)
    context.response["history_type"] = "preview"
    context.response["history_input"] = f"preview {raw}"
