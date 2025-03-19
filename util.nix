{ config, pkgs }:
rec {
  nixpkgs = {
    config.allowUnfree = true;
  };

  packages = [
    pkgs.code-cursor
    pkgs.discord
    pkgs.gh
    pkgs.git
    pkgs.obsidian
    pkgs.spotify

    (pkgs.writers.writePython3Bin "ghcode" { } ./ghcode.py)
  ];

  symlink = subpath: {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/github/samestep/env/${subpath}";
  };

  file = {
    ".gitconfig" = symlink ".gitconfig";
  };

  shellAliases = {
    code = "cursor";
  };

  programs = {
    bat.enable = true;

    eza.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    home-manager.enable = true;

    starship.enable = true;
  };
}
