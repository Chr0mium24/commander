from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class EngineContext:
    query: str
    settings: dict[str, Any]
    attachments: list[dict[str, Any]]
    aliases: dict[str, str]
    python_path: str
    script_dir: str
    response: dict[str, Any]
    runtime_metadata: dict[str, Any] = field(default_factory=dict)
    registry: Any = None
