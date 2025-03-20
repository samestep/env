import argparse
import subprocess
import sys
from pathlib import Path
from typing import Any


def run(cmd: list[str], **kwargs: Any) -> None:
    returncode = subprocess.run(cmd, **kwargs).returncode
    if returncode != 0:
        sys.exit(returncode)


flake_contents = """
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShell =
          with pkgs;
          mkShell {
            buildInputs = [
              nixfmt-rfc-style
            ];
          };
      }
    );
}
""".lstrip()


def main() -> None:
    description = "open a scratch space in Cursor"
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("name")
    args = parser.parse_args()

    path = Path.home() / "scratch" / f"{args.name}-scratch"
    if not path.exists():
        path.mkdir(parents=True, exist_ok=True)
        run(["git", "init"], cwd=path)
        (path / "flake.nix").write_text(flake_contents)
        run(["git", "add", "flake.nix"], cwd=path)
        run(["nix", "flake", "lock"], cwd=path)
        (path / ".envrc").write_text("use flake\n")
        (path / ".gitignore").write_text("/.direnv/\n")
        run(["git", "add", "."], cwd=path)
        run(["git", "commit", "-m", "Initial commit"], cwd=path)
        run(["direnv", "allow"], cwd=path)
    run(["cursor", path])


if __name__ == "__main__":
    main()
