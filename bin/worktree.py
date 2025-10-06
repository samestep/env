import argparse
import subprocess
import sys
from pathlib import Path


def main() -> None:
    description = "create a Git worktree and open in VS Code"
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("branch")
    args = parser.parse_args()

    cmd = ["git", "rev-parse", "--show-toplevel"]
    root = subprocess.check_output(cmd, encoding="utf8").strip()
    subpath = Path(root).relative_to(Path.home())
    path = Path.home() / "worktrees" / subpath / args.branch
    subprocess.run(["git", "worktree", "add", path])
    returncode = subprocess.run(["code", path]).returncode
    if returncode != 0:
        sys.exit(returncode)


if __name__ == "__main__":
    main()
