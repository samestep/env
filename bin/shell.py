import argparse
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str]) -> None:
    returncode = subprocess.run(cmd).returncode
    if returncode != 0:
        sys.exit(returncode)


def main() -> None:
    description = "create gitignored direnv config"
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("name")
    args = parser.parse_args()

    git_info_exclude_path = Path(".git/info/exclude")
    git_info_exclude_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        git_info_exclude = git_info_exclude_path.read_text().splitlines()
    except FileNotFoundError:
        git_info_exclude = []
    for line in ["/.direnv/", "/.envrc"]:
        if line not in git_info_exclude:
            git_info_exclude.append(line)
    git_info_exclude_path.write_text("\n".join(git_info_exclude + [""]))

    Path(".envrc").write_text(f"use flake ~/github/samestep/env#{args.name}\n")
    run(["direnv", "allow"])


if __name__ == "__main__":
    main()
