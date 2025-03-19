{ config, pkgs }:
rec {
  nixpkgs = {
    config.allowUnfree = true;
  };

  packages = [
    pkgs.code-cursor
    pkgs.gh
    pkgs.git

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
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    home-manager.enable = true;

    starship.enable = true;
  };
}
