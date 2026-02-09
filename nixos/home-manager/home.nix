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
    # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "sam";
    homeDirectory = "/home/sam";

    packages = util.packages ++ [
      pkgs.discord
      pkgs.gnome-boxes
      pkgs.obsidian
      pkgs.prismlauncher
      pkgs.vim
      pkgs.xsel # Used by the VS Code "Open In GitHub" extension.
    ];

    file = util.file // {
      ".config/Code/User/keybindings.json" = util.symlink "vscode/keybindings.json";
      ".config/Code/User/settings.json" = util.symlink "vscode/settings.json";
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

  programs = util.programs // {
    bash.enable = true; # Necessary for aliases and Starship to work.
  };

  assertions = util.assertions;
}
