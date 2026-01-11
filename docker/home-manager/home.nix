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
    # # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "root";
    homeDirectory = "/root";
  };

  programs = util.programs // {
    bash.enable = true; # Necessary for aliases and Starship to work.
  };
}
