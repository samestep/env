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
  nixpkgs.config.allowUnfree = true;

  home = {
    # This value determines the Home Manager release that your configuration is
    # compatible with. This helps avoid breakage when a new Home Manager release
    # introduces backwards incompatible changes.
    #
    # You should not change this value, even if you update Home Manager. If you
    # do want to update the value, then make sure to first check the Home
    # Manager release notes.
    stateVersion = "24.11"; # Please read the comment before changing.

    username = "sam";
    homeDirectory = "/home/sam";

    packages = util.packages ++ [
      pkgs.discord
      pkgs.obsidian
      pkgs.spotify
      pkgs.vim
    ];

    file = {
      ".config/Cursor/User/keybindings.json" = util.symlink "desktop/cursor/keybindings.json";
      ".config/Cursor/User/settings.json" = util.symlink "cursor/settings.json";
      ".gitconfig" = util.symlink ".gitconfig";
    };

    shellAliases = {
      code = "cursor";
    };
  };

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        clock-format = "12h";
        color-scheme = "prefer-dark";
      };

      # Don't go to sleep.
      "org/gnome/desktop/session".idle-delay = lib.hm.gvariant.mkUint32 0;
      "org/gnome/settings-daemon/plugins/power".sleep-inactive-ac-type = "nothing";
    };
  };

  programs = {
    bash.enable = true; # Necessary for aliases and Starship to work.

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    home-manager.enable = true; # Let Home Manager install and manage itself.

    starship.enable = true;
  };
}
