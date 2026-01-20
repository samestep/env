{ config, pkgs, ... }:
let
  util = import ../../util.nix { inherit config pkgs; };
in
{
  nixpkgs = util.nixpkgs;

  home = {
    # # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "agent-arm64";
    homeDirectory = "/home/agent-arm64";

    packages = util.packages;

    file = util.file // {
      ".codex/config.toml" = util.symlink "codex/config.toml";
    };
  };

  programs = util.programs // {
    bash.enable = true; # Necessary for aliases and Starship to work.
  };

  assertions = util.assertions;
}
