{
  config,
  lib,
  pkgs,
  nix-darwin,
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
    # You should not change this value, even if you update Home Manager. If you do
    # want to update the value, then make sure to first check the Home Manager
    # release notes.
    stateVersion = "24.11"; # Please read the comment before changing.

    username = "samueles";
    homeDirectory = "/Users/samueles";

    packages = util.packages ++ [
      nix-darwin.packages."aarch64-darwin".darwin-rebuild
    ];

    file = util.file // {
      "Library/Application Support/Code/User/keybindings.json" =
        util.symlink "macos/vscode/keybindings.json";
      "Library/Application Support/Code/User/settings.json" = util.symlink "vscode/settings.json";
    };

    activation = {
      dock =
        let
          dockutil = "${pkgs.dockutil}/bin/dockutil";
          dockItems = lib.strings.concatLines (
            map (item: "run ${dockutil} --no-restart --add ${lib.strings.escapeShellArg item}") [
              "/System/Applications/System Settings.app"
              "/System/Applications/Utilities/Activity Monitor.app"
              "${pkgs.iterm2}/Applications/ITerm2.app"
              "/Applications/Firefox.app"
              "${pkgs.spotify}/Applications/Spotify.app"
              "${pkgs.discord}/Applications/Discord.app"
              "${pkgs.slack}/Applications/Slack.app"
              "${pkgs.zoom-us}/Applications/zoom.us.app"
              "${pkgs.obsidian}/Applications/Obsidian.app"
              "${pkgs.vscode}/Applications/Visual Studio Code.app"
              "/Applications/Steam.app"
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
}
