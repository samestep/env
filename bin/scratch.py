import argparse
import subprocess
import sys
from pathlib import Path
from typing import Any


def run(cmd: list[str], **kwargs: Any) -> None:
    returncode = subprocess.run(cmd, **kwargs).returncode
    if returncode != 0:
        sys.exit(returncode)


def get_template() -> str:
    return (Path(__file__).parent.parent / "template.nix").read_text()


def main() -> None:
    description = "open a scratch space in VS Code"
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("name")
    args = parser.parse_args()

    path = Path.home() / "scratch" / f"{args.name}-scratch"
    if not path.exists():
        path.mkdir(parents=True, exist_ok=True)
        run(["git", "init"], cwd=path)
        (path / "flake.nix").write_text(get_template())
        run(["git", "add", "flake.nix"], cwd=path)
        run(["nix", "flake", "lock"], cwd=path)
        (path / ".envrc").write_text("use flake\n")
        (path / ".gitignore").write_text("/.direnv/\n")
        run(["git", "add", "."], cwd=path)
        run(["git", "commit", "-m", "Initial commit"], cwd=path)
        run(["direnv", "allow"], cwd=path)
    run(["code", path])


if __name__ == "__main__":
    main()
