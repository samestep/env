{
  config,
  lib,
  pkgs,
  symlink,
  ...
}:
{
  home = {
    # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "sam";
    homeDirectory = "/home/sam";

    packages = [
      pkgs.discord
      pkgs.gh
      pkgs.gnomeExtensions.appindicator # Allow GNOME tray items.
      pkgs.obsidian
      pkgs.prismlauncher
      pkgs.vim
      pkgs.virt-viewer
      pkgs.xsel # Used by the VS Code "Open In GitHub" extension.
    ];

    file = {
      ".config/ghostty/config.ghostty" = symlink "ghostty/config.ghostty";
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

      # Allow GNOME tray items.
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
        ];
      };
    };
  };

  programs = {
    bash.enable = true; # Necessary for aliases and Starship to work.

    firefox = {
      enable = true;
      # Using the new default since `stateVersion` isn't the newest.
      configPath = "${config.xdg.configHome}/mozilla/firefox";
    };

    ghostty.enable = true;
  };
}
