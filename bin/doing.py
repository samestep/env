import argparse
import subprocess
import sys


def set_title(title: str) -> None:
    sys.stdout.write(f"\033]0;{title}\a")
    sys.stdout.flush()


def main() -> None:
    description = "set the terminal title to show when a task is done"
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("label")
    parser.add_argument("command")
    args = parser.parse_args()

    set_title(f"⏳ {args.label}")
    try:
        result = subprocess.run(args.command, shell=True)
    finally:
        set_title(f"🔔 {args.label}")
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
