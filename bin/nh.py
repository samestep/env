import os
import re
import subprocess
import sys
import time
from typing import TextIO

# Nix prints one of these per store path it deletes. `nh clean` shells out to
# `nix store gc`, which drops its verbosity to `lvlNotice` whenever it thinks
# it is attached to a terminal, so these lines only exist because this wrapper
# puts a pipe on nh's stdout:
# https://github.com/NixOS/nix/blob/master/src/nix/main.cc#L435-L441
deleting = re.compile(r"^deleting '/nix/store/[^']*'$")

# Global nh options that take a separate value, which we skip over while
# looking for the subcommand:
# https://github.com/nix-community/nh/blob/master/crates/nh/src/interface.rs
takes_value = {"-e", "--elevation-strategy", "--elevation-program"}


def subcommand(args: list[str]) -> str | None:
    rest = iter(args)
    for arg in rest:
        if arg in takes_value:
            next(rest, None)
        elif not arg.startswith("-"):
            return arg
    return None


def summarize(stdout: TextIO) -> None:
    count = 0
    start = None
    while line := stdout.readline():
        line = line.rstrip("\n")
        if deleting.match(line):
            if start is None:
                start = time.monotonic()
            count += 1
            elapsed = int(time.monotonic() - start)
            minutes, seconds = divmod(elapsed, 60)
            status = f"  {count:,} paths deleted ({minutes}m{seconds:02d}s)"
            print(f"\033[2K\r{status}", end="", flush=True)
        else:
            if start is not None:
                print()
                start = None
            print(line, flush=True)
    if start is not None:
        print()


def main() -> None:
    args = sys.argv[1:]
    # Only `nh clean` sits silent for minutes on end; leave everything else
    # (notably the nom output of `nh os`) exactly as it is. `--ask` wants a
    # terminal for its prompt, and a redirected stdout deserves the unabridged
    # log rather than a status line that redraws itself.
    if (
        subcommand(args) != "clean"
        or "--ask" in args
        or not sys.stdout.isatty()
    ):
        os.execvp("nh", ["nh", *args])
    # Only stdout is piped: nh merges the stderr of `nix store gc` into its own
    # stdout, so that is where the interesting lines land, and nh's own logging
    # on stderr reaches the terminal untouched.
    with subprocess.Popen(
        ["nh", *args],
        stdout=subprocess.PIPE,
        text=True,
        errors="replace",
    ) as process:
        assert process.stdout is not None
        try:
            summarize(process.stdout)
        except KeyboardInterrupt:
            print()
    sys.exit(process.returncode)


if __name__ == "__main__":
    main()
