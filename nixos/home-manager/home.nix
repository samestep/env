{
  config,
  lib,
  pkgs,
  npc,
  ...
}:
let
  util = import ../../util.nix { inherit config pkgs npc; };
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

    username = "sam";
    homeDirectory = "/home/sam";

    packages = util.packages ++ [
      pkgs.discord
      pkgs.gnomeExtensions.appindicator # Needed for Dropbox in tray.
      pkgs.obsidian
      pkgs.spotify
      pkgs.vim
      pkgs.xsel # Used by the VS Code "Open In GitHub" extension.
    ];

    file = util.file // {
      ".config/Code/User/keybindings.json" = util.symlink "vscode/keybindings.json";
      ".config/Code/User/settings.json" = util.symlink "vscode/settings.json";
    };

    activation = {
      dropbox = lib.hm.dag.entryAfter [
        "writeBoundary"
      ] "run ${pkgs.dropbox-cli}/bin/dropbox autostart y";
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
      "org/gnome/shell".enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com" # Needed for Dropbox in tray.
      ];
    };
  };

  programs = util.programs // {
    bash.enable = true; # Necessary for aliases and Starship to work.
  };

  services = {
    dropbox.enable = true;
  };
}
