{ symlink, ... }:
{
  home.file = {
    ".claude/settings.json" = symlink "claude/yolo.json";
    ".codex/config.toml" = symlink "codex/yolo.toml";
  };
}
