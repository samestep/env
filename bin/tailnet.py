import argparse
import json
import subprocess
from pathlib import Path

HOSTS = ["sandbox-amd64", "sandbox-arm64", "tahoe-vanilla"]


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
    tailnet = f"Host {' '.join(HOSTS)}\n  HostName %h.{suffix}\n"
    # The `win-amd64` alias (see ssh/config) reaches the Windows guest via
    # sandbox-amd64, so it needs that host's FQDN.
    tailnet += f"\nHost win-amd64\n  HostName sandbox-amd64.{suffix}\n"
    path.write_text(tailnet)


if __name__ == "__main__":
    main()
