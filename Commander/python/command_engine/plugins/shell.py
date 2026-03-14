from __future__ import annotations

from ..executors import execute_python_snippet, execute_shell, resolve_run_command
from ..runtime import EngineContext
from ..utils import fenced
from ..plugin_registry import CommandRegistry


def register(registry: CommandRegistry, context: EngineContext | None = None) -> None:
    alias_py = "py"
    if context is not None:
        alias_py = context.aliases.get("py", "py").strip() or "py"

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
        context.response["output"] = "Running..."
        context.response["should_save_history"] = False
        return

    output = execute_shell(final_command, run_in_background=False)
    context.response["output"] = output
    context.response["should_save_history"] = True
