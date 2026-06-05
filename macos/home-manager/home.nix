{
  config,
  lib,
  pkgs,
  ...
}:
let
  util = import ../../util.nix { inherit config lib pkgs; };
in
{
  nixpkgs = util.nixpkgs;

  # Enabling this causes permission issues:
  # https://github.com/nix-community/home-manager/pull/8031
  targets.darwin.copyApps.enable = false;

  home = {
    # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "samueles";
    homeDirectory = "/Users/samueles";

    packages = util.packages ++ [
      pkgs.gh
      pkgs.tart
    ];

    # Necessary for `git send-email` to work.
    sessionVariables = {
      NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };

    file = util.file // {
      "Library/Application Support/Code/User/keybindings.json" =
        util.symlink "macos/vscode/keybindings.jsonc";
      "Library/Application Support/Code/User/settings.json" = util.symlink "vscode/settings.jsonc";
      "Library/Application Support/com.mitchellh.ghostty/config.ghostty" =
        util.symlink "ghostty/config.ghostty";
    };

    activation = {
      dock =
        let
          dockutil = "${pkgs.dockutil}/bin/dockutil";
          dockItems = lib.strings.concatLines (
            map (item: "run ${dockutil} --no-restart --add ${lib.strings.escapeShellArg item}") [
              "/System/Applications/System Settings.app"
              "/System/Applications/Utilities/Disk Utility.app"
              "/System/Applications/Utilities/Activity Monitor.app"
              "${pkgs.ghostty-bin}/Applications/Ghostty.app"
              "/Applications/Firefox.app"
              "/Applications/Discord.app"
              "${pkgs.slack}/Applications/Slack.app"
              "/Applications/zoom.us.app"
              "${pkgs.obsidian}/Applications/Obsidian.app"
              "${pkgs.vscode}/Applications/Visual Studio Code.app"
            ]
          );
        in
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${dockutil} --no-restart --remove all
          ${dockItems}
          run ${dockutil} --no-restart --add ~/Downloads --section others --display stack
          run /usr/bin/killall Dock
        '';
    };
  };

  programs = util.programs // {
    zsh.enable = true; # Necessary for aliases and Starship to work.
  };

  assertions = util.assertions;
}
