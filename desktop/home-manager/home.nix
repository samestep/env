{
  config,
  lib,
  pkgs,
  ...
}:
let
  util = import ../../util.nix { inherit config; };
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "sam";
  home.homeDirectory = "/home/sam";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.11"; # Please read the comment before changing.

  nixpkgs.config.allowUnfree = true;

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    pkgs.code-cursor
    pkgs.discord
    pkgs.gh
    pkgs.git
    pkgs.nixfmt-rfc-style
    pkgs.obsidian
    pkgs.spotify
    pkgs.vim

    (pkgs.writers.writePython3Bin "ghcode" { } ../../ghcode.py)
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';

    ".config/Cursor/User/keybindings.json" = util.symlink "desktop/cursor/keybindings.json";
    ".config/Cursor/User/settings.json" = util.symlink "cursor/settings.json";
    ".gitconfig" = util.symlink ".gitconfig";
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/sam/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    # EDITOR = "emacs";
  };

  home.shellAliases = {
    code = "cursor";
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

    # Let Home Manager install and manage itself.
    home-manager.enable = true;

    starship.enable = true;
  };
}
