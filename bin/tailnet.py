"""Write ~/.ssh/tailnet, the machine-local SSH include mapping the agent-VM
aliases to their MagicDNS names. The tailnet's MagicDNS suffix is
tailnet-specific (and this repo is public), so it isn't committed; derive it
from `tailscale status`. Re-run after the tailnet's MagicDNS suffix changes."""

import json
import subprocess
from pathlib import Path

HOSTS = ["sandbox-amd64", "sandbox-arm64", "tahoe-vanilla"]


def main():
    status = subprocess.run(
        ["tailscale", "status", "--json"],
        check=True,
        capture_output=True,
        text=True,
    )
    suffix = json.loads(status.stdout)["MagicDNSSuffix"]

    path = Path.home() / ".ssh" / "tailnet"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"Host {' '.join(HOSTS)}\n  HostName %h.{suffix}\n")
    path.chmod(0o600)
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
