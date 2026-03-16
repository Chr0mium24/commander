from __future__ import annotations

import importlib.util
from functools import lru_cache
from pathlib import Path
from types import ModuleType

from ..plugin_registry import CommandRegistry
from ..runtime import EngineContext


@lru_cache(maxsize=1)
def _music_script_module() -> ModuleType:
    module_path = Path(__file__).resolve()
    candidates = [
        module_path.parents[3] / "scripts" / "p.py",
        module_path.with_name("p.py"),
    ]

    script_path = next((path for path in candidates if path.exists()), None)
    if script_path is None:
        joined = ", ".join(str(path) for path in candidates)
        raise RuntimeError(f"music script not found. looked in: {joined}")

    spec = importlib.util.spec_from_file_location("commander_music_script", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load music plugin bridge: {script_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def register(registry: CommandRegistry, context: EngineContext | None = None) -> None:
    registry.register_help_section(
        "Music Plugin",
        [
            "`music` random playlist",
            "`music ls` list local songs",
            "`music add <url|BV> [more ...]` download via yt-dlp",
            "`music single [id]` play one song",
            "`music loop <id>` loop song",
            "`p ...` alias for music",
        ],
    )
    module = _music_script_module()
    register_fn = getattr(module, "register", None)
    if not callable(register_fn):
        raise RuntimeError("scripts/p.py must expose register(registry, context=None)")
    register_fn(registry, context)
