#!/usr/bin/env python3

from __future__ import annotations

import os
import random
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_MUSIC_DIR = Path("/Users/cr/scripts/music")
DEFAULT_PLAYER = "mpv"


def register(registry, context=None):
    registry.register_setting("musicDirectory", "string", "Music Directory", "plugins")
    registry.register_setting("musicPlayer", "string", "Music Player Command", "plugins")
    registry.register_command(
        "music",
        handle_music,
        aliases=["p"],
        usage="music [ls|add|single|loop|<id>|<url|BV>]",
        description="Music helper backed by plugins/p.py (mpv + yt-dlp).",
    )


def handle_music(context, content: str):
    try:
        tokens = shlex.split(content.strip()) if content.strip() else []
    except ValueError as exc:
        context.response["output"] = f"Invalid music command: {exc}"
        return

    if not tokens:
        _defer_script(context, [], "music")
        return

    sub = tokens[0].strip()
    sub_lower = sub.lower()

    if sub_lower in {"help", "-h", "--help"}:
        context.response["output"] = plugin_help_markdown()
        context.response["history_type"] = "music"
        context.response["should_save_history"] = True
        return

    if sub_lower in {"ls", "list"}:
        music_dir = resolve_music_dir(context.settings)
        context.response["output"] = render_music_list_markdown(music_dir)
        context.response["history_type"] = "music"
        context.response["should_save_history"] = True
        return

    if sub_lower == "add":
        if len(tokens) < 2:
            context.response["output"] = "Usage: music add <url|BV> [more ...]"
            return
        _defer_script(context, tokens, "music " + " ".join(tokens))
        return

    if sub_lower == "single":
        _defer_script(context, tokens, "music " + " ".join(tokens))
        return

    if sub_lower == "loop":
        if len(tokens) < 2:
            context.response["output"] = "Usage: music loop <id>"
            return
        _defer_script(context, tokens, "music " + " ".join(tokens))
        return

    if is_song_id(sub) or is_url_or_bv(sub):
        _defer_script(context, [sub], f"music {sub}")
        return

    context.response["output"] = plugin_help_markdown()


def _defer_script(context, script_args: list[str], history_input: str) -> None:
    script_path = Path(__file__).resolve()
    python_exec = str(context.python_path or sys.executable or "python3")
    player = resolve_player(context.settings)
    command = build_script_command(
        python_exec=python_exec,
        script_path=script_path,
        script_args=script_args,
        player=player,
    )

    context.response["defer_shell"] = True
    context.response["shell_run_in_background"] = False
    context.response["shell_command"] = command
    context.response["progress_presentation"] = "terminal"
    context.response["progress_title"] = history_input
    context.response["output"] = "Running music command..."
    context.response["history_type"] = "music"
    context.response["history_input"] = history_input
    context.response["should_save_history"] = False


def build_script_command(
    *,
    python_exec: str,
    script_path: Path,
    script_args: list[str],
    player: str,
) -> str:
    parts = [python_exec, str(script_path), "--internal-run", *script_args]
    quoted = " ".join(shlex.quote(part) for part in parts)
    return f"MUSIC_PLAYER={shlex.quote(player)} {quoted}"


def resolve_music_dir(settings: dict | None = None) -> Path:
    raw = ""
    if settings is not None:
        raw = str(settings.get("musicDirectory") or "").strip()
    path = Path(raw).expanduser() if raw else DEFAULT_MUSIC_DIR
    path.mkdir(parents=True, exist_ok=True)
    return path


def resolve_player(settings: dict | None = None) -> str:
    if settings is not None:
        configured = str(settings.get("musicPlayer") or "").strip()
        if configured:
            return configured
    env_player = os.environ.get("MUSIC_PLAYER", "").strip()
    return env_player or DEFAULT_PLAYER


def is_hidden(path: Path) -> bool:
    return any(part.startswith(".") for part in path.parts)


def list_music_files(music_dir: Path) -> list[Path]:
    files: list[Path] = []
    if not music_dir.exists():
        return files

    for root, _dirs, names in os.walk(music_dir):
        root_path = Path(root)
        relative = root_path.relative_to(music_dir)
        if str(relative) != "." and is_hidden(relative):
            continue
        for name in names:
            if name.startswith("."):
                continue
            file_path = root_path / name
            if file_path.is_file():
                files.append(file_path)

    return sorted(files, key=lambda item: item.name.lower())


def fnv1a3(file_path: Path) -> str:
    seed = 2166136261
    for ch in file_path.name:
        seed ^= ord(ch)
        seed = (seed * 16777619) & 0xFFFFFFFF
    return f"{seed:08x}"[:3]


def is_song_id(token: str) -> bool:
    return len(token) == 3 and all(ch.lower() in "0123456789abcdef" for ch in token)


def is_url_or_bv(token: str) -> bool:
    lowered = token.lower()
    return lowered.startswith("http://") or lowered.startswith("https://") or token.startswith("BV")


def to_bili_link(value: str) -> str:
    if value.startswith("BV"):
        return f"https://www.bilibili.com/video/{value}"
    return value


def find_song_by_id(music_dir: Path, song_id: str) -> Path | None:
    target = song_id.lower()
    for item in list_music_files(music_dir):
        if fnv1a3(item) == target:
            return item
    return None


def render_music_list_markdown(music_dir: Path) -> str:
    songs = list_music_files(music_dir)
    lines = [
        f"### Music Library ({len(songs)})",
        "",
        f"Directory: `{music_dir}`",
        "",
    ]

    if not songs:
        lines.append("No songs found.")
        return "\n".join(lines)

    lines.extend(
        [
            "| id | song |",
            "| --- | --- |",
        ]
    )
    for item in songs:
        lines.append(f"| `{fnv1a3(item)}` | {item.stem} |")
    return "\n".join(lines)


def plugin_help_markdown() -> str:
    return "\n".join(
        [
            "### Music Plugin",
            "",
            "- `music` random playlist",
            "- `music ls` list local songs",
            "- `music add <url|BV> [more ...]` download audio via yt-dlp",
            "- `music single [id]` play one song",
            "- `music loop <id>` loop one song",
            "- `music <id>` shortcut for loop",
            "- `music <url|BV>` download and play one source",
            "",
            "Settings:",
            "- `set music_directory /path/to/music`",
            "- `set music_player mpv`",
        ]
    )


def run_command(args: list[str]) -> int:
    try:
        return subprocess.run(args).returncode
    except FileNotFoundError:
        print(f"Command not found: {args[0]}")
        return 127


def run_shell(command: str) -> int:
    try:
        return subprocess.run(command, shell=True).returncode
    except FileNotFoundError:
        print("Shell command failed to start.")
        return 127


def play_random_playlist(music_dir: Path, player: str) -> int:
    songs = list_music_files(music_dir)
    if not songs:
        print(f"No songs found in {music_dir}")
        return 1

    random.shuffle(songs)
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8") as temp:
        playlist = Path(temp.name)
        for song in songs:
            temp.write(str(song) + "\n")

    try:
        return run_command([player, "--no-video", f"--playlist={playlist}"])
    finally:
        playlist.unlink(missing_ok=True)


def cmd_ls(music_dir: Path) -> int:
    songs = list_music_files(music_dir)
    print(f"Music dir: {music_dir}")
    print(f"{'ID':<6} SONG")
    print("-" * 72)
    for item in songs:
        print(f"{fnv1a3(item):<6} {item.stem}")
    return 0


def cmd_add(music_dir: Path, items: list[str]) -> int:
    if not items:
        print("Usage: p.py add <url|BV> [more ...]")
        return 1

    exit_code = 0
    for item in items:
        link = to_bili_link(item)
        rc = run_command(
            [
                "yt-dlp",
                "-x",
                "-P",
                str(music_dir),
                "-o",
                "%(title)s.%(ext)s",
                link,
            ]
        )
        if rc != 0:
            exit_code = rc
    return exit_code


def cmd_single(music_dir: Path, player: str, song_id: str | None) -> int:
    song: Path | None
    if song_id:
        song = find_song_by_id(music_dir, song_id)
        if song is None:
            print(f"Song not found: {song_id}")
            return 1
    else:
        songs = list_music_files(music_dir)
        if not songs:
            print("No songs found.")
            return 1
        song = random.choice(songs)

    return run_command([player, "--no-video", str(song)])


def cmd_loop(music_dir: Path, player: str, song_id: str) -> int:
    song = find_song_by_id(music_dir, song_id)
    if song is None:
        print(f"Song not found: {song_id}")
        return 1
    return run_command([player, "--no-video", "--loop", str(song)])


def cmd_quick_play(music_dir: Path, player: str, source: str) -> int:
    link = to_bili_link(source)
    command = (
        f"yt-dlp -x -P {shlex.quote(str(music_dir))} "
        f"-o {shlex.quote('%(title)s.%(ext)s')} "
        f"--exec {shlex.quote(f'{player} --no-video {{}}')} "
        f"{shlex.quote(link)}"
    )
    return run_shell(command)


def show_help() -> int:
    print(plugin_help_markdown().replace("music", "p.py"))
    return 0


def main() -> int:
    args = sys.argv[1:]
    if args and args[0] == "--internal-run":
        args = args[1:]

    music_dir = resolve_music_dir()
    player = resolve_player()

    if not args:
        return play_random_playlist(music_dir, player)

    cmd = args[0]
    cmd_lower = cmd.lower()

    if cmd_lower in {"help", "-h", "--help"}:
        return show_help()
    if cmd_lower == "ls":
        return cmd_ls(music_dir)
    if cmd_lower == "add":
        return cmd_add(music_dir, args[1:])
    if cmd_lower == "single":
        song_id = args[1] if len(args) > 1 else None
        return cmd_single(music_dir, player, song_id)
    if cmd_lower == "loop":
        if len(args) < 2:
            print("Usage: p.py loop <id>")
            return 1
        return cmd_loop(music_dir, player, args[1])
    if is_song_id(cmd):
        return cmd_loop(music_dir, player, cmd)
    if is_url_or_bv(cmd):
        return cmd_quick_play(music_dir, player, cmd)

    return show_help()


if __name__ == "__main__":
    raise SystemExit(main())
