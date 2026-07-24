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


def main() -> None:
    args = sys.argv[1:]
    # Every other subcommand is left alone; PATH puts the real tart first.
    if not args or args[0] != "run":
        os.execvp("tart", ["tart", *args])

    proc: subprocess.Popen[bytes] | None = None
    stage = 0

    def interrupt(signum: int, frame: FrameType | None) -> None:
        nonlocal stage
        if proc is None or stage >= len(ESCALATION):
            return
        sig, message = ESCALATION[stage]
        stage += 1
        print(f"tart: {message}", file=sys.stderr)
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
