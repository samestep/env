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
    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    #
    # You should not change this value, even if you update Home Manager. If you
    # do want to update the value, then make sure to first check the Home
    # Manager release notes.
    stateVersion = "24.11"; # Please read the comment before changing.

    username = "saestep";
    homeDirectory = "/home/saestep";

    packages = util.packages ++ [
      pkgs.spotify
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
