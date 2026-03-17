#!/usr/bin/env python3
from __future__ import annotations

import sys
import types
from pathlib import Path


def _bootstrap_flattened_bundle() -> None:
    script_dir = Path(__file__).resolve().parent
    package_dir = script_dir / "command_engine"
    if package_dir.is_dir():
        return

    required_files = ("main.py", "router.py", "plugin_registry.py")
    if not all((script_dir / filename).is_file() for filename in required_files):
        return

    package = types.ModuleType("command_engine")
    package.__path__ = [str(script_dir)]  # type: ignore[attr-defined]
    package.__file__ = str(script_dir / "__init__.py")
    sys.modules.setdefault("command_engine", package)

    plugins_package = types.ModuleType("command_engine.plugins")
    plugins_package.__path__ = [str(script_dir)]  # type: ignore[attr-defined]
    plugins_package.__file__ = str(script_dir / "__init__.py")
    sys.modules.setdefault("command_engine.plugins", plugins_package)


_bootstrap_flattened_bundle()

from command_engine.main import main


if __name__ == "__main__":
    main()
