import argparse
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import NamedTuple


def _prog() -> str:
    # Recover the command name through the makeWrapper wrapping that
    # writePython3Bin applies (it installs the script as `.<name>-wrapped`).
    name = Path(sys.argv[0]).name
    if name.startswith(".") and name.endswith("-wrapped"):
        name = name[1:-len("-wrapped")]
    return name


PROJECTS = Path.home() / ".claude" / "projects"
CLAUDE_JSON = Path.home() / ".claude.json"
PROG = _prog()
LIMIT = 20


class Session(NamedTuple):
    sid: str
    mtime: float
    title: str
    cwd: str


def parse_meta(path: Path) -> tuple[str | None, str | None]:
    """Scan a session JSONL for its latest AI title and its cwd."""
    title: str | None = None
    cwd: str | None = None
    with path.open(errors="ignore") as f:
        for line in f:
            if '"ai-title"' not in line and '"cwd"' not in line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("type") == "ai-title" and entry.get("aiTitle"):
                title = entry["aiTitle"]
            if entry.get("cwd"):
                cwd = entry["cwd"]
    return title, cwd


def recent(limit: int) -> list[Session]:
    """Most-recently-touched sessions, newest first."""
    files = [(p.stat().st_mtime, p) for p in PROJECTS.glob("*/*.jsonl")]
    files.sort(reverse=True)
    sessions = []
    for mtime, path in files[:limit]:
        title, cwd = parse_meta(path)
        sessions.append(
            Session(path.stem, mtime, title or "(untitled)", cwd or "?")
        )
    return sessions


def has_session(name: str) -> bool:
    result = subprocess.run(
        ["tmux", "has-session", "-t", f"={name}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def unique_name(base: str) -> str:
    name = base
    n = 2
    while has_session(name):
        name = f"{base}-{n}"
        n += 1
    return name


def trust_dir(path: str) -> None:
    """Pre-accept Claude's per-directory trust prompt, which otherwise
    blocks a detached session forever (nobody is there to answer it)."""
    try:
        data = json.loads(CLAUDE_JSON.read_text())
    except (OSError, json.JSONDecodeError):
        return
    entry = data.setdefault("projects", {}).setdefault(path, {})
    if entry.get("hasTrustDialogAccepted"):
        return
    entry["hasTrustDialogAccepted"] = True
    tmp = CLAUDE_JSON.with_name(".claude.json.steer-tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(CLAUDE_JSON)


def launch(name: str, cwd: str, cmd: list[str]) -> None:
    """Start `cmd` detached in tmux so it outlives the SSH session."""
    start = cwd if cwd != "?" else str(Path.home())
    trust_dir(start)
    subprocess.run(
        ["tmux", "new-session", "-d", "-s", name, "-c", start, *cmd],
        check=True,
    )


def attach_hint(name: str) -> None:
    print("open the Claude app to attach, or watch locally with:")
    print(f"  tmux attach -t {name}")


def short(cwd: str) -> str:
    home = str(Path.home())
    return "~" + cwd[len(home):] if cwd.startswith(home) else cwd


def cmd_list(args: argparse.Namespace) -> None:
    sessions = recent(args.limit)
    if not sessions:
        print("no Claude Code sessions found")
        return
    for i, s in enumerate(sessions, 1):
        when = time.strftime("%m-%d %H:%M", time.localtime(s.mtime))
        print(f"{i:2}) {when}  {short(s.cwd)}")
        print(f"     {s.title}")


def cmd_resume(args: argparse.Namespace) -> None:
    sessions = recent(LIMIT)
    if not 1 <= args.index <= len(sessions):
        sys.exit(f"no session #{args.index} (run `{PROG}` to list)")
    s = sessions[args.index - 1]
    name = f"{PROG}-{s.sid[:8]}"
    if has_session(name):
        print(f"already running: {s.title}")
        attach_hint(name)
        return
    launch(name, s.cwd, ["claude", "--resume", s.sid, "--remote-control"])
    print(f"resumed: {s.title}")
    attach_hint(name)


def cmd_new(args: argparse.Namespace) -> None:
    target = Path(args.dir).expanduser().resolve()
    name = unique_name(f"{PROG}-{target.name or 'session'}")
    launch(name, str(target), ["claude", "--remote-control"])
    print(f"new session in {short(str(target))}")
    attach_hint(name)


def main() -> None:
    description = "launch remote-controllable Claude Code sessions in tmux"
    parser = argparse.ArgumentParser(prog=PROG, description=description)
    sub = parser.add_subparsers()

    lister = sub.add_parser("list", help="list recent sessions")
    lister.add_argument("-n", "--limit", type=int, default=LIMIT)
    lister.set_defaults(func=cmd_list)

    resumer = sub.add_parser("resume", help="resume session number N")
    resumer.add_argument("index", type=int, metavar="N")
    resumer.set_defaults(func=cmd_resume)

    starter = sub.add_parser("new", help="start a new session")
    starter.add_argument("dir", nargs="?", default=".")
    starter.set_defaults(func=cmd_new)

    argv = sys.argv[1:]
    if argv and argv[0].isdigit():
        argv = ["resume", *argv]
    if not argv:
        argv = ["list"]

    args = parser.parse_args(argv)
    try:
        args.func(args)
    except FileNotFoundError as e:
        sys.exit(f"missing command: {e.filename}")
    except subprocess.CalledProcessError as e:
        sys.exit(e.returncode)


if __name__ == "__main__":
    main()
