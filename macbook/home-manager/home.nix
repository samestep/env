{ config, pkgs, ... }:
let
  util = import ../../util.nix { inherit config pkgs; };
in
{
  nixpkgs.config.allowUnfree = true;

  home = {
    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    #
    # You should not change this value, even if you update Home Manager. If you do
    # want to update the value, then make sure to first check the Home Manager
    # release notes.
    stateVersion = "24.11"; # Please read the comment before changing.

    username = "samueles";
    homeDirectory = "/Users/samueles";

    packages = util.packages ++ [
      pkgs.iterm2
    ];

    file = {
      "Library/Application Support/Cursor/User/keybindings.json" =
        util.symlink "macbook/cursor/keybindings.json";
      "Library/Application Support/Cursor/User/settings.json" = util.symlink "cursor/settings.json";
      ".gitconfig" = util.symlink ".gitconfig";
    };

    shellAliases = {
      code = "cursor";
    };
  };

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    home-manager.enable = true; # Let Home Manager install and manage itself.

    starship.enable = true;

    zsh.enable = true; # Necessary for aliases and Starship to work.
  };
}
