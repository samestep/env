{ pkgs, symlink, ... }:
{
  # `tailnet` (re)generates the machine-local ~/.ssh/tailnet that ssh/config
  # includes, filling in this tailnet's MagicDNS suffix from `tailscale status`
  # (see README). It's not committed because the suffix is tailnet-specific.
  home.packages = [ (pkgs.writers.writePython3Bin "tailnet" { } ../bin/tailnet.py) ];

  home.file = {
    ".claude/CLAUDE.md" = symlink "claude/CLAUDE.md";
    ".claude/settings.json" = symlink "claude/yolo.json";
    ".codex/config.toml" = symlink "codex/yolo.toml";

    # Tailscale ties the three agent VMs into one mesh so any of them can
    # control the others (see README). The `tailscaled` daemon is set up
    # out-of-band per OS; here we just teach SSH how to reach the other VMs by
    # their MagicDNS names, symmetrically: any VM can `ssh <name>` into any
    # other. The host/user mapping is identical on all three, so it's a single
    # static file rather than generated config.
    ".ssh/config" = symlink "ssh/config";
  };
}
