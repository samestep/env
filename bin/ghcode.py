import argparse
import re
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str]) -> None:
    returncode = subprocess.run(cmd).returncode
    if returncode != 0:
        sys.exit(returncode)


def parse(url: str) -> str:
    regex = r"^(https://github\.com/)?([\w\.-]+/[\w\.-]+)"
    match = re.match(regex, url)
    if match is None:
        print(f"must match this regex: {regex}", file=sys.stderr)
        sys.exit(1)
    return match.group(2)


def main() -> None:
    description = "clone a GitHub repository and open in Cursor"
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("repo")
    args = parser.parse_args()

    repo = parse(args.repo)
    path = Path.home() / "github" / repo
    if not path.exists():
        cmd = ["gh", "repo", "clone", repo, path, "--", "--recurse-submodules"]
        run(cmd)
    run(["cursor", path])


if __name__ == "__main__":
    main()
