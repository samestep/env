{ config, pkgs }:
rec {
  symlink = subpath: {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/github/samestep/env/${subpath}";
  };

  # https://nix-community.github.io/home-manager/options.xhtml#opt-nixpkgs.config
  nixpkgs = {
    config.allowUnfree = true;
  };

  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.packages
  packages = [
    pkgs.cloc
    pkgs.code-cursor
    pkgs.discord
    pkgs.gh
    pkgs.git
    pkgs.obsidian
    pkgs.spotify

    (pkgs.symlinkJoin {
      name = "samestep";
      paths = [
        (pkgs.writeTextDir "template.nix" (builtins.readFile ./template.nix))
        (pkgs.writers.writePython3Bin "flake" { } ./bin/flake.py)
        (pkgs.writers.writePython3Bin "ghcode" { } ./bin/ghcode.py)
        (pkgs.writers.writePython3Bin "scratch" { } ./bin/scratch.py)
        (pkgs.writers.writePython3Bin "shell" { } ./bin/shell.py)
      ];
    })
  ];

  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.file
  file = {
    ".config/cloc" = symlink "cloc";
    ".gitconfig" = symlink ".gitconfig";
  };

  # https://nix-community.github.io/home-manager/options.xhtml#opt-home.shellAliases
  shellAliases = {
    code = "cursor";
  };

  programs = {
    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.bat.enable
    bat.enable = true;

    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.eza.enable
    eza.enable = true;

    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.direnv.enable
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.home-manager.enable
    home-manager.enable = true;

    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.starship.enable
    starship.enable = true;
  };
}
