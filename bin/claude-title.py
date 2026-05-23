import argparse
import json
import os
import pathlib
import signal
import subprocess
import sys
import time


FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
TICK_SECONDS = 0.08
SHELL_COMMS = {"bash", "sh", "zsh", "fish", "dash", "ksh"}
CLAUDE_COMMS = {"claude", ".claude-wrapped", "claude-code"}


def state_root() -> pathlib.Path:
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/claude-title-{os.getuid()}"
    return pathlib.Path(base) / "claude-title"


def session_state_dir(session_id: str) -> pathlib.Path:
    return state_root() / session_id


def read_ppid(pid: int) -> int | None:
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return None


def read_comm(pid: int) -> str | None:
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip()
    except OSError:
        return None


def find_claude_pid() -> int | None:
    pid: int | None = os.getppid()
    for _ in range(40):
        if pid is None or pid <= 1:
            return None
        comm = read_comm(pid)
        if comm in CLAUDE_COMMS:
            return pid
        pid = read_ppid(pid)
    return None


def find_tty_for_pid(pid: int) -> str | None:
    for fd in ("1", "2", "0"):
        try:
            link = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if link.startswith("/dev/pts/") or link.startswith("/dev/tty"):
            return link
    return None


def format_cwd_label(cwd: str) -> str:
    home = os.path.expanduser("~")
    if cwd == home:
        return "~"
    if cwd.startswith(home + "/"):
        return "~/" + cwd[len(home) + 1 :]
    return cwd


def write_title(tty_path: str, text: str) -> None:
    try:
        fd = os.open(tty_path, os.O_WRONLY | os.O_NOCTTY)
    except OSError:
        return
    try:
        os.write(fd, f"\033]0;{text}\007".encode("utf-8", "replace"))
    finally:
        os.close(fd)


def snapshot_processes() -> dict[int, tuple[int, str]]:
    info: dict[int, tuple[int, str]] = {}
    try:
        entries = os.listdir("/proc")
    except OSError:
        return info
    for name in entries:
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            with open(f"/proc/{pid}/stat", "rb") as f:
                data = f.read()
        except OSError:
            continue
        end = data.rfind(b")")
        if end < 0:
            continue
        head = data[:end]
        tail = data[end + 1 :].split()
        if len(tail) < 2:
            continue
        try:
            ppid = int(tail[1])
        except ValueError:
            continue
        start = head.find(b"(")
        if start < 0:
            continue
        comm = head[start + 1 :].decode("utf-8", "replace")
        info[pid] = (ppid, comm)
    return info


def descendants_have_shell(root_pid: int, exclude: set[int]) -> bool:
    info = snapshot_processes()
    children: dict[int, list[int]] = {}
    for pid, (ppid, _) in info.items():
        children.setdefault(ppid, []).append(pid)
    stack = list(children.get(root_pid, []))
    seen: set[int] = set()
    while stack:
        pid = stack.pop()
        if pid in seen or pid in exclude:
            continue
        seen.add(pid)
        rec = info.get(pid)
        if rec is None:
            continue
        if rec[1] in SHELL_COMMS:
            return True
        stack.extend(children.get(pid, []))
    return False


def run_daemon(state_dir: pathlib.Path) -> None:
    tty_path = (state_dir / "tty").read_text().strip()
    claude_pid = int((state_dir / "claude_pid").read_text().strip())
    cwd_label = (state_dir / "cwd_label").read_text().strip()
    daemon_pid = os.getpid()
    (state_dir / "daemon_pid").write_text(str(daemon_pid))
    busy_file = state_dir / "claude_busy"

    def cleanup(_signum=None, _frame=None):
        write_title(tty_path, cwd_label)
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    frame_idx = 0
    while True:
        try:
            os.kill(claude_pid, 0)
        except OSError:
            break
        if busy_file.exists():
            is_busy = True
        else:
            is_busy = descendants_have_shell(claude_pid, exclude={daemon_pid})
        if is_busy:
            text = f"{FRAMES[frame_idx % len(FRAMES)]} {cwd_label}"
            frame_idx += 1
        else:
            text = cwd_label
        write_title(tty_path, text)
        time.sleep(TICK_SECONDS)
    write_title(tty_path, cwd_label)


def load_hook_payload() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def hook_session_start() -> None:
    payload = load_hook_payload()
    session_id = payload.get("session_id")
    if not session_id:
        return
    cwd = payload.get("cwd") or os.getcwd()
    claude_pid = find_claude_pid()
    if claude_pid is None:
        return
    tty = find_tty_for_pid(claude_pid)
    if tty is None:
        return
    state_dir = session_state_dir(session_id)
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "claude_pid").write_text(str(claude_pid))
    (state_dir / "tty").write_text(tty)
    (state_dir / "cwd_label").write_text(format_cwd_label(cwd))
    log = open(state_dir / "daemon.log", "ab")
    subprocess.Popen(
        ["claude-title", "daemon", str(state_dir)],
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=log,
        start_new_session=True,
        close_fds=True,
    )


def hook_user_prompt_submit() -> None:
    payload = load_hook_payload()
    session_id = payload.get("session_id")
    if not session_id:
        return
    state_dir = session_state_dir(session_id)
    if state_dir.is_dir():
        (state_dir / "claude_busy").touch()


def hook_stop() -> None:
    payload = load_hook_payload()
    session_id = payload.get("session_id")
    if not session_id:
        return
    state_dir = session_state_dir(session_id)
    busy = state_dir / "claude_busy"
    try:
        busy.unlink()
    except FileNotFoundError:
        pass


def hook_session_end() -> None:
    payload = load_hook_payload()
    session_id = payload.get("session_id")
    if not session_id:
        return
    state_dir = session_state_dir(session_id)
    daemon_pid_file = state_dir / "daemon_pid"
    if daemon_pid_file.exists():
        try:
            pid = int(daemon_pid_file.read_text().strip())
            os.kill(pid, signal.SIGTERM)
        except (OSError, ValueError):
            pass
    if state_dir.is_dir():
        for entry in state_dir.iterdir():
            try:
                entry.unlink()
            except OSError:
                pass
        try:
            state_dir.rmdir()
        except OSError:
            pass


HOOKS = {
    "session-start": hook_session_start,
    "user-prompt-submit": hook_user_prompt_submit,
    "stop": hook_stop,
    "session-end": hook_session_end,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Claude Code terminal title spinner")
    sub = parser.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("daemon")
    d.add_argument("state_dir")
    h = sub.add_parser("hook")
    h.add_argument("event", choices=sorted(HOOKS.keys()))
    args = parser.parse_args()
    if args.cmd == "daemon":
        run_daemon(pathlib.Path(args.state_dir))
    else:
        HOOKS[args.event]()


if __name__ == "__main__":
    main()
