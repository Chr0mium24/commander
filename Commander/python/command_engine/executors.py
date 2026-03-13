from __future__ import annotations

import os
import shlex
import subprocess
import tempfile

from .constants import DEFAULT_PYTHON


def safe_python(python_path: str) -> str:
    if python_path and os.path.isfile(python_path):
        return python_path
    if os.path.isfile(DEFAULT_PYTHON):
        return DEFAULT_PYTHON
    return "python3"


def shell_env() -> dict[str, str]:
    env = os.environ.copy()
    current_path = env.get("PATH", "")
    env["PATH"] = (
        "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:"
        + current_path
    )
    env["SWIFT_CTX"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    return env


def resolve_run_command(input_text: str, script_dir: str, python_path: str) -> tuple[str, bool]:
    trimmed = input_text.strip()
    run_in_background = trimmed.endswith("&")
    if run_in_background:
        trimmed = trimmed[:-1].strip()

    if not trimmed:
        return "", run_in_background

    command_name, _, arg_str = trimmed.partition(" ")
    final_command = trimmed

    if script_dir:
        sh_path = os.path.join(script_dir, f"{command_name}.sh")
        py_path = os.path.join(script_dir, f"{command_name}.py")
        exact_path = os.path.join(script_dir, command_name)

        if os.path.isfile(sh_path):
            final_command = f"/bin/bash {shlex.quote(sh_path)}"
            if arg_str:
                final_command += f" {arg_str}"

        if os.path.isfile(py_path):
            interpreter = safe_python(python_path)
            final_command = f"{shlex.quote(interpreter)} {shlex.quote(py_path)}"
            if arg_str:
                final_command += f" {arg_str}"

        if os.path.isfile(exact_path):
            final_command = shlex.quote(exact_path)
            if arg_str:
                final_command += f" {arg_str}"

    return final_command, run_in_background


def execute_shell(command: str, run_in_background: bool) -> str:
    env = shell_env()
    if run_in_background:
        launch_cmd = f"nohup {command} > /dev/null 2>&1 &"
        subprocess.Popen(
            ["/bin/zsh", "-c", launch_cmd],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            env=env,
        )
        return f"Background process launched: {command}"

    proc = subprocess.run(
        ["/bin/zsh", "-c", command],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    output = "\\n".join(part for part in [proc.stdout.strip(), proc.stderr.strip()] if part)
    return output if output else "Done (No Output)"


def execute_python_snippet(code: str, python_path: str) -> str:
    if not code.strip():
        return "Usage: py <python code>"

    interpreter = safe_python(python_path)
    if interpreter != "python3" and not os.path.isfile(interpreter):
        return f"Python executable not found: {python_path}"

    runner = (
        "import ast,sys,traceback\\n"
        "target_file=sys.argv[1]\\n"
        "try:\\n"
        "  source=open(target_file,'r',encoding='utf-8').read()\\n"
        "  tree=ast.parse(source)\\n"
        "  if tree.body and isinstance(tree.body[-1], ast.Expr):\\n"
        "    last=tree.body.pop()\\n"
        "    ctx={}\\n"
        "    if tree.body:\\n"
        "      exec(compile(tree,target_file,'exec'),ctx)\\n"
        "    result=eval(compile(ast.Expression(last.value),target_file,'eval'),ctx)\\n"
        "    if result is not None:\\n"
        "      print(result)\\n"
        "  else:\\n"
        "    exec(compile(source,target_file,'exec'),{})\\n"
        "except Exception:\\n"
        "  traceback.print_exc()\\n"
    )

    temp_file = None
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8") as f:
            temp_file = f.name
            f.write(code)

        proc = subprocess.run(
            [interpreter, "-u", "-c", runner, temp_file],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=shell_env(),
        )

        stdout = proc.stdout.strip()
        stderr = proc.stderr.strip()

        final_output = stdout
        if stderr:
            if final_output:
                final_output += "\\n\\n"
            final_output += f"Error/Stderr:\\n{stderr}"

        return final_output if final_output else "Done (No Output)"
    finally:
        if temp_file and os.path.exists(temp_file):
            try:
                os.remove(temp_file)
            except OSError:
                pass
