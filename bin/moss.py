"""Select a compiler with `moss switch [--bootstrap] FLAKE`."""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def cache_root() -> Path:
    xdg = os.environ.get("XDG_CACHE_HOME", "")
    if xdg and Path(xdg).is_absolute():
        return Path(xdg) / "moss"
    if sys.platform == "darwin":
        return Path.home() / "Library/Caches/moss"
    return Path.home() / ".cache/moss"


def resolve(reference: str) -> tuple[str, str]:
    metadata = json.loads(subprocess.check_output(
        ["nix", "flake", "metadata", "--json",
         "--no-write-lock-file", reference],
        encoding="utf8",
    ))
    revision = metadata.get("revision") or ""
    if not re.fullmatch(r"[0-9a-fA-F]{40}", revision):
        raise ValueError(
            "flake must identify a clean Git commit; commit your changes "
            "or select a committed snapshot with ?rev=COMMIT",
        )
    return revision.lower(), metadata["url"]


def replace_link(link: Path, destination: str) -> None:
    temporary = link.with_name(f".{link.name}-{os.getpid()}")
    temporary.unlink(missing_ok=True)
    try:
        temporary.symlink_to(destination)
        temporary.replace(link)
    finally:
        temporary.unlink(missing_ok=True)


def switch(cache: Path, reference: str, *, bootstrap: bool = False) -> None:
    revision, reference = resolve(reference)
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / revision
    current = cache / "current"
    package = target
    if bootstrap or not target.exists():
        command = ["nix", "build", "--no-link", "--print-out-paths"]
        if not bootstrap and current.exists():
            deriver = subprocess.check_output(
                ["nix-store", "--query", "--deriver", str(current.resolve())],
                encoding="utf8",
            ).strip()
            if not Path(deriver).is_file() or not deriver.endswith(".drv"):
                raise ValueError("selected compiler's derivation is missing")
            # Import the actual derivation, preserving the seed dependency
            # rather than copying its output into an opaque store file.
            quoted_reference = json.dumps(
                reference, ensure_ascii=False,
            ).replace("${", r"\${")
            expression = f"""
              let
                target = builtins.getFlake {quoted_reference};
                seed = import {json.dumps(deriver)};
              in
              target.packages.${{builtins.currentSystem}}.default.override {{
                inherit seed;
              }}
            """
            command += ["--impure", "--expr", expression]
        else:
            print("moss: selecting the bootstrap package", file=sys.stderr)
            command.append(reference)
        package = Path(subprocess.check_output(
            command, encoding="utf8",
        ).strip())
    if not package.is_absolute() or not (package / "bin/moss").is_file():
        raise ValueError(f"not a complete Moss package: {package}")
    if package != target:
        replace_link(target, str(package))
    replace_link(current, revision)


def main() -> None:
    args = sys.argv[1:]
    cache = cache_root()
    if args[:1] == ["switch"]:
        parser = argparse.ArgumentParser(
            prog="moss switch", allow_abbrev=False,
        )
        parser.add_argument(
            "--bootstrap", action="store_true",
            help="select the revision's bootstrapped package",
        )
        parser.add_argument("flake", metavar="FLAKE")
        options = parser.parse_args(args[1:])
        switch(cache, options.flake, bootstrap=options.bootstrap)
    else:
        executable = (cache / "current/bin/moss").resolve()
        if not executable.is_file():
            raise ValueError(
                "no compiler selected; run moss switch FLAKE",
            )
        os.execv(executable, [str(executable), *args])


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
    except (OSError, ValueError) as error:
        sys.exit(f"moss: {error}")
