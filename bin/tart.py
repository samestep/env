import json
import os
import signal
import subprocess
import sys
from types import FrameType

# Tart maps SIGINT to VZVirtualMachine.stop(), which Apple documents as "a
# destructive operation" that stops the VM "without giving the guest a chance
# to stop cleanly", and SIGUSR2 to requestStop(), which instead asks the guest
# to power itself off:
# https://developer.apple.com/documentation/virtualization/vzvirtualmachine
# So translate the first Ctrl-C into a graceful request, and only escalate to
# the destructive stop when asked again.
ESCALATION = [
    (signal.SIGUSR2, "asking the guest to shut down; Ctrl-C again to force"),
    (signal.SIGINT, "forcing the VM to stop"),
    (signal.SIGKILL, "killing tart"),
]

# On macOS guests requestStop() only raises a confirmation dialog, which
# nobody can answer while the VM is headless, so the request hangs there
# forever. Say so, rather than letting Ctrl-C look like it did nothing.
DARWIN_HINT = """\
tart: macOS guests only surface this as a dialog, which you cannot answer
tart: while headless. Shut it down from inside the guest instead:
tart:     ssh admin@$(tart ip {name}) sudo shutdown -h now"""


def find_vm(args: list[str]) -> tuple[str, str] | None:
    """Return the (name, OS) of whichever argument names a VM."""
    for arg in args:
        if arg.startswith("-"):
            continue
        try:
            probe = subprocess.run(
                ["tart", "get", arg, "--format", "json"],
                capture_output=True,
                text=True,
                timeout=10,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        if probe.returncode == 0:
            try:
                return arg, json.loads(probe.stdout)["OS"]
            except (json.JSONDecodeError, KeyError):
                return None
    return None


def main() -> None:
    args = sys.argv[1:]
    # Every other subcommand is left alone; PATH puts the real tart first.
    if not args or args[0] != "run":
        os.execvp("tart", ["tart", *args])

    vm = find_vm(args[1:])
    hint = DARWIN_HINT.format(name=vm[0]) if vm and vm[1] == "darwin" else None

    proc: subprocess.Popen[bytes] | None = None
    stage = 0

    def interrupt(signum: int, frame: FrameType | None) -> None:
        nonlocal stage
        if proc is None or stage >= len(ESCALATION):
            return
        sig, message = ESCALATION[stage]
        stage += 1
        print(f"tart: {message}", file=sys.stderr)
        if stage == 1 and hint is not None:
            print(hint, file=sys.stderr)
        proc.send_signal(sig)

    # Handle SIGTERM the same way: macOS sends it to surviving processes at
    # logout, which is how the VM used to lose power without warning.
    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)

    # Give tart its own process group, so a Ctrl-C typed in the terminal goes
    # to this wrapper alone instead of also hitting tart directly.
    proc = subprocess.Popen(["tart", *args], start_new_session=True)
    status = proc.wait()
    sys.exit(128 - status if status < 0 else status)


if __name__ == "__main__":
    main()
