{ pkgs, symlink, ... }:
{
  home.packages = [
    (pkgs.writers.writePython3Bin "tailnet" { } ../bin/tailnet.py)
  ];

  home.file = {
    ".claude/CLAUDE.md" = symlink "agent.md";
    ".claude/settings.json" = symlink "claude/yolo.json";
    ".codex/AGENTS.md" = symlink "agent.md";
    ".codex/config.toml" = symlink "codex/yolo.toml";
    ".ssh/config" = symlink "ssh/config";
  };
}
