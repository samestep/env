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

  home = {
    # # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "agent-amd64";
    homeDirectory = "/home/agent-amd64";

    packages = util.packages;

    file = util.file // {
      ".claude/settings.json" = util.symlink "claude/yolo.json";
      ".codex/config.toml" = util.symlink "codex/yolo.toml";
    };
  };

  programs = util.programs // {
    bash = {
      enable = true; # Necessary for aliases and Starship to work.
      initExtra = util.shellInit;
    };
  };

  assertions = util.assertions;
}
