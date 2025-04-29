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
    # You should not change this value, even if you update Home Manager. If you do
    # want to update the value, then make sure to first check the Home Manager
    # release notes.
    stateVersion = "24.11"; # Please read the comment before changing.

    username = "samueles";
    homeDirectory = "/Users/samueles";

    packages = util.packages;

    file = util.file // {
      "Library/Application Support/Code/User/keybindings.json" =
        util.symlink "macbook/vscode/keybindings.json";
      "Library/Application Support/Code/User/settings.json" = util.symlink "vscode/settings.json";
    };

    activation = {
      dock =
        let
          dockutil = "${pkgs.dockutil}/bin/dockutil";
          dockItems = lib.strings.concatLines (
            map (item: "run ${dockutil} --no-restart --add ${lib.strings.escapeShellArg item}") [
              "/Applications/Utilities/Activity Monitor.app"
              "${pkgs.iterm2}/Applications/ITerm2.app"
              "/Applications/Firefox.app"
              "${pkgs.spotify}/Applications/Spotify.app"
              "${pkgs.discord}/Applications/Discord.app"
              "/Applications/Slack.app"
              "/Applications/zoom.us.app"
              "${pkgs.obsidian}/Applications/Obsidian.app"
              "${pkgs.vscode}/Applications/Visual Studio Code.app"
              "/Applications/Steam.app"
            ]
          );
        in
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${dockutil} --no-restart --remove all
          ${dockItems}
          run /usr/bin/killall Dock
        '';
    };
  };

  programs = util.programs // {
    zsh.enable = true; # Necessary for aliases and Starship to work.
  };
}
