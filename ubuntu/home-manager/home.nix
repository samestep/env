{
  config,
  lib,
  pkgs,
  ...
}:
let
  util = import ../../util.nix { inherit config pkgs; };
in
{
  nixpkgs = util.nixpkgs;

  home = {
    # # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "saestep";
    homeDirectory = "/home/saestep";

    packages = util.packages ++ [
      pkgs.xsel # Used by the VS Code "Open In GitHub" extension.
    ];

    file = util.file // {
      ".config/Code/User/keybindings.json" = util.symlink "vscode/keybindings.json";
      ".config/Code/User/settings.json" = util.symlink "vscode/settings.json";
    };
  };

  nixGL = {
    packages = pkgs.nixgl.auto;
    installScripts = [ "nvidia" ];
    vulkan.enable = true;
  };

  programs = util.programs // {
    bash.enable = true; # Necessary for aliases and Starship to work.
  };
}
