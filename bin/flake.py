import argparse
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str]) -> None:
    returncode = subprocess.run(cmd).returncode
    if returncode != 0:
        sys.exit(returncode)


def get_template() -> str:
    return (Path(__file__).parent.parent / "template.nix").read_text()


def main() -> None:
    description = "create a flake"
    parser = argparse.ArgumentParser(description=description)
    parser.parse_args()

    Path("flake.nix").write_text(get_template())
    run(["git", "add", "flake.nix"])
    run(["nix", "flake", "lock"])
    Path(".envrc").write_text("use flake\n")
    run(["direnv", "allow"])

    try:
        gitignore = Path(".gitignore").read_text().splitlines()
    except FileNotFoundError:
        gitignore = []
    for line in ["/.direnv/", "/.envrc"]:
        if line not in gitignore:
            gitignore.append(line)
    Path(".gitignore").write_text("\n".join(gitignore + [""]))


if __name__ == "__main__":
    main()
