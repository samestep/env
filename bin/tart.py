import os
import signal
import subprocess
import sys
from types import FrameType


def main() -> None:
    args = sys.argv[1:]
    if not args or args[0] != "run":
        os.execvp("tart", ["tart", *args])

    proc: subprocess.Popen[bytes] | None = None
    ask_nicely = True

    def interrupt(signalnum: int, frame: FrameType | None) -> None:
        nonlocal ask_nicely
        if proc is None:
            return
        elif ask_nicely:
            print()
            print("asking the guest to shut down; ^C again to force")
            print("(for macOS guests this won't work; use SSH instead)")
            proc.send_signal(signal.SIGUSR2)
            ask_nicely = False
        else:
            proc.send_signal(signal.SIGINT)

    signal.signal(signal.SIGINT, interrupt)

    # Give Tart its own process group, so a ^C typed in the terminal
    # goes to this wrapper alone instead of also hitting Tart directly.
    proc = subprocess.Popen(["tart", *args], start_new_session=True)
    status = proc.wait()
    sys.exit(128 - status if status < 0 else status)


if __name__ == "__main__":
    main()
