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
      ".codex/config.toml" = util.symlink "docker-x86/codex/config.toml";
    };
  };

  programs = util.programs // {
    bash.enable = true; # Necessary for aliases and Starship to work.
  };

  assertions = util.assertions;
}
