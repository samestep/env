{ symlink, ... }:
{
  home.file = {
    ".config/Code/User/keybindings.json" = symlink "vscode/keybindings.jsonc";
    ".config/Code/User/settings.json" = symlink "vscode/settings.jsonc";
  };
}
