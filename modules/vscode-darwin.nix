{ symlink, ... }:
{
  home.file = {
    "Library/Application Support/Code/User/keybindings.json" = symlink "macos/vscode/keybindings.jsonc";
    "Library/Application Support/Code/User/settings.json" = symlink "vscode/settings.jsonc";
  };
}
