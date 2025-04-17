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
          dbaeumer.vscode-eslint
          esbenp.prettier-vscode
          github.vscode-github-actions
          jnoortheen.nix-ide
          julialang.language-julia
          llvm-vs-code-extensions.vscode-clangd
          mkhl.direnv
          ms-azuretools.vscode-docker
          ms-python.python
          ms-vscode.cmake-tools
          rust-lang.rust-analyzer
          tamasfe.even-better-toml
        ]
        ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          {
            publisher = "DIKU";
            name = "futhark-vscode";
            version = "0.1.3";
            sha256 = "sha256-URikRSOUR/vdOKGP8/wopROAd18J81pxii8+DHd0sa0=";
          }
          {
            publisher = "oven";
            name = "bun-vscode";
            version = "0.0.28";
            sha256 = "sha256-WlGqqKbfrV0gqCCdVo/UFF+Gnxhq0TNJ4LuHwFaFYXA=";
          }
          {
            publisher = "sysoev";
            name = "vscode-open-in-github";
            version = "1.18.0";
            sha256 = "sha256-bOJ+b6jfRxYGhUizFGWYGsqI1M80awcAlLCUvWjizPk=";
          }
        ];
    };
  };
}
