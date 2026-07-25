{
  lib,
  pkgs,
  symlink,
  ...
}:
{
  # Enabling this causes permission issues:
  # https://github.com/nix-community/home-manager/pull/8031
  targets.darwin.copyApps.enable = false;

  home = {
    # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "samueles";
    homeDirectory = "/Users/samueles";

    packages = [
      pkgs.gh

      (pkgs.writers.writePython3Bin "tart" {
        makeWrapperArgs = [
          "--prefix"
          "PATH"
          ":"
          (lib.makeBinPath [ pkgs.tart ])
        ];
      } ../../bin/tart.py)
    ];

    # Necessary for `git send-email` to work.
    sessionVariables = {
      NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };

    file = {
      "Library/Application Support/com.mitchellh.ghostty/config.ghostty" =
        symlink "ghostty/config.ghostty";
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

  programs.zsh.enable = true; # Necessary for aliases and Starship to work.
}
