{ symlink, ... }:
{
  home.file = {
    ".claude/settings.json" = symlink "claude/safe.json";
    ".codex/config.toml" = symlink "codex/safe.toml";
  };
}
