{ symlink, ... }:
{
  home.file = {
    ".claude/CLAUDE.md" = symlink "claude/CLAUDE.md";
    ".claude/settings.json" = symlink "claude/yolo.json";
    ".codex/config.toml" = symlink "codex/yolo.toml";
  };
}
