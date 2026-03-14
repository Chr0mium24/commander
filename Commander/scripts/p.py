#!/usr/bin/env python3

from __future__ import annotations

import os
import random
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

MUSIC_DIR = Path("/Users/cr/scripts/music")
MUSIC_DIR.mkdir(parents=True, exist_ok=True)

RESET = "\033[0m"
BOLD = "\033[1m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
MAGENTA = "\033[35m"
CYAN = "\033[36m"


def is_hidden(path: Path) -> bool:
    return any(part.startswith(".") for part in path.parts)


def list_music_files() -> list[Path]:
    files: list[Path] = []
    if not MUSIC_DIR.exists():
        return files

    for root, _dirs, names in os.walk(MUSIC_DIR):
        root_path = Path(root)
        if is_hidden(root_path.relative_to(MUSIC_DIR)):
            continue
        for name in names:
            if name.startswith("."):
                continue
            p = root_path / name
            if p.is_file():
                files.append(p)
    return files


def fnv1a3(file_path: Path) -> str:
    s = file_path.name
    h = 2166136261
    for ch in s:
        h ^= ord(ch)
        h = (h * 16777619) & 0xFFFFFFFF
    return f"{h:08x}"[:3]


def find_song_by_id(target_hash: str) -> Path | None:
    for p in list_music_files():
        if fnv1a3(p) == target_hash:
            return p
    return None


def run_cmd(args: list[str]) -> int:
    try:
        return subprocess.run(args).returncode
    except FileNotFoundError:
        print(f"{RED}Command not found: {args[0]}{RESET}")
        return 127


def run_shell(cmd: str) -> int:
    try:
        return subprocess.run(cmd, shell=True).returncode
    except FileNotFoundError:
        print(f"{RED}Command not found while executing shell command.{RESET}")
        return 127


def to_bili_link(v: str) -> str:
    if v.startswith("BV"):
        return f"https://www.bilibili.com/video/{v}"
    return v


def launch_alacritty(script_args: list[str]) -> None:
    script_path = Path(__file__).resolve()
    cmd = [
        "alacritty",
        "--title",
        "Music Player",
        "--command",
        sys.executable,
        str(script_path),
        "--internal-run",
        *script_args,
    ]
    try:
        subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    except FileNotFoundError:
        print(f"{RED}alacritty not found; run in current terminal.{RESET}")


def play_random_playlist() -> int:
    songs = list_music_files()
    if not songs:
        print(f"{RED}No songs found in {MUSIC_DIR}{RESET}")
        return 1

    random.shuffle(songs)
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8") as tf:
        playlist = Path(tf.name)
        for song in songs:
            tf.write(str(song) + "\n")

    try:
        print(f"{BOLD}{GREEN}Random playlist...{RESET}")
        print(f"{CYAN}(q quit, Enter next, Space pause){RESET}")
        return run_cmd(["mpv", "--no-video", f"--playlist={playlist}"])
    finally:
        try:
            playlist.unlink(missing_ok=True)
        except OSError:
            pass


def cmd_ls() -> int:
    songs = list_music_files()
    print()
    print(f"{BOLD}{BLUE}{'ID':<10} SONG NAME{RESET}")
    print(f"{BLUE}{'-'*8} {'-'*40}{RESET}")

    for song in songs:
        title = song.stem
        if len(title) > 80:
            title = title[:77] + "..."
        sid = fnv1a3(song)
        print(f"{YELLOW}{sid:<10}{RESET} {title}")

    print()
    return 0


def cmd_add(items: list[str]) -> int:
    if not items:
        print(f"{RED}Error: provide BV or URL (quote links with ?).{RESET}")
        return 1

    print(f"{BOLD}{MAGENTA}Batch download started ({len(items)} tasks){RESET}")
    code = 0
    total = len(items)

    for i, item in enumerate(items, start=1):
        link = to_bili_link(item)
        if item.startswith("BV"):
            print(f"{CYAN}[{i}/{total}] BV->URL: {link}{RESET}")
        else:
            print(f"{CYAN}[{i}/{total}] URL: {link}{RESET}")

        rc = run_cmd([
            "yt-dlp",
            "-x",
            "-P",
            str(MUSIC_DIR),
            "-o",
            "%(title)s.%(ext)s",
            link,
        ])
        if rc != 0:
            code = rc
        print(f"{BLUE}{'-'*40}{RESET}")

    print(f"{GREEN}Download finished.{RESET}")
    return code


def cmd_single(arg: str | None, internal_run: bool) -> int:
    if not arg:
        songs = list_music_files()
        if not songs:
            print(f"{RED}No songs found.{RESET}")
            return 1
        song = random.choice(songs)
    else:
        song = find_song_by_id(arg)
        if not song:
            print(f"{RED}Not found ID: {arg}{RESET}")
            if internal_run:
                input("Press Enter to exit...")
            return 1

    print(f"{GREEN}Play single: {BOLD}{song.name}{RESET}")
    return run_cmd(["mpv", "--no-video", str(song)])


def cmd_loop(song_id: str, internal_run: bool) -> int:
    song = find_song_by_id(song_id)
    if not song:
        print(f"{RED}Not found ID: {song_id}{RESET}")
        if internal_run:
            input("Press Enter to exit...")
        return 1

    print(f"{MAGENTA}Single loop: {BOLD}{song.name}{RESET}")
    return run_cmd(["mpv", "--no-video", "--loop", str(song)])


def cmd_quick_play(source: str) -> int:
    link = to_bili_link(source)
    print(f"{YELLOW}Download and play...{RESET}")
    shell_cmd = (
        f"yt-dlp -x -P {shlex.quote(str(MUSIC_DIR))} "
        f"-o {shlex.quote('%(title)s.%(ext)s')} "
        f"--exec {shlex.quote('mpv --no-video {}')} "
        f"{shlex.quote(link)}"
    )
    return run_shell(shell_cmd)


def show_help(internal_run: bool) -> int:
    p = Path(__file__).name
    print(f"{BOLD}Usage:{RESET}")
    print(f"  {GREEN}{p}{RESET}                   # random play")
    print(f"  {GREEN}{p} add \"<URL>\" ...{RESET}   # batch download")
    print(f"  {GREEN}{p} ls{RESET}                # list songs")
    print(f"  {GREEN}{p} single [ID]{RESET}       # play one")
    print(f"  {GREEN}{p} <3-char ID>{RESET}       # single loop")
    print(f"  {GREEN}{p} <URL/BV>{RESET}          # download + play")

    if internal_run:
        input("Press Enter to exit...")
    return 0


def main() -> int:
    args = sys.argv[1:]
    in_commander = os.environ.get("SWIFT_CTX") == "1"
    allow_popup = os.environ.get("P_PY_POPUP", "1") == "1"

    if allow_popup and not in_commander and (not args or args[0] not in {"--internal-run", "ls", "add"}):
        launch_alacritty(args)
        return 0

    internal_run = False
    if args and args[0] == "--internal-run":
        internal_run = True
        args = args[1:]

    if not args:
        return play_random_playlist()

    cmd = args[0]
    arg2 = args[1] if len(args) > 1 else None

    if cmd == "ls":
        return cmd_ls()

    if cmd == "add":
        return cmd_add(args[1:])

    if cmd == "single":
        return cmd_single(arg2, internal_run)

    if len(cmd) == 3:
        return cmd_loop(cmd, internal_run)

    if cmd.startswith("https") or cmd.startswith("BV"):
        return cmd_quick_play(cmd)

    return show_help(internal_run)


if __name__ == "__main__":
    raise SystemExit(main())
