import argparse
import json
import subprocess
from pathlib import Path

HOSTS = ["sandbox-amd64", "ubuntu", "tahoe-vanilla"]


def main():
    description = "generate an SSH config file for Tailscale"
    parser = argparse.ArgumentParser(description=description)
    parser.parse_args()

    out = subprocess.check_output(
        ["tailscale", "status", "--json"],
        encoding="utf8",
    )
    suffix = json.loads(out)["MagicDNSSuffix"]
    path = Path.home() / ".ssh" / "tailnet"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"Host {' '.join(HOSTS)}\n  HostName %h.{suffix}\n")


if __name__ == "__main__":
    main()
