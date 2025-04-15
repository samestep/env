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

    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.vscode.enable
    vscode = {
      enable = true;
      profiles.default.extensions =
        with pkgs.vscode-extensions;
        [
          charliermarsh.ruff
          esbenp.prettier-vscode
          jnoortheen.nix-ide
          julialang.language-julia
          mkhl.direnv
          ms-python.python
          ms-vscode.cmake-tools
          rust-lang.rust-analyzer
        ]
        ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          {
            publisher = "ngtystr";
            name = "ppm-pgm-viewer-for-vscode";
            version = "1.2.0";
            sha256 = "sha256-88dKhjfepOovsIjNxPQ5aEwNJlsQoCo9xtkqTJrb2ZA=";
          }
          {
            publisher = "Seaube";
            name = "clangformat";
            version = "2.0.2";
            sha256 = "sha256-vyKAb1CPmRyy89P90jIQ2MTaf2ZKE2jpaegiRWCr5Bw=";
          }
        ];
    };
  };
}
