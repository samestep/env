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
    pkgs.btop
    pkgs.cloc
    pkgs.codex
    pkgs.gh
    pkgs.git
    pkgs.nixfmt
    pkgs.npc
    pkgs.wasm-language-tools

    (pkgs.symlinkJoin {
      name = "samestep";
      paths = [
        (pkgs.writeTextDir "template.nix" (builtins.readFile ./template.nix))
        (pkgs.writers.writePython3Bin "flake" { } ./bin/flake.py)
        (pkgs.writers.writePython3Bin "ghcode" { } ./bin/ghcode.py)
        (pkgs.writers.writePython3Bin "scratch" { } ./bin/scratch.py)
        (pkgs.writers.writePython3Bin "shell" { } ./bin/shell.py)
        (pkgs.writers.writePython3Bin "worktree" { } ./bin/worktree.py)
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

    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.starship.enable
    starship.enable = true;

    # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.vscode.enable
    vscode = {
      enable = true;
      profiles.default.extensions =
        let
          vscode = pkgs.vscode-extensions;
        in
        [
          vscode.charliermarsh.ruff
          vscode.dbaeumer.vscode-eslint
          vscode.esbenp.prettier-vscode
          vscode.github.vscode-github-actions
          vscode.jnoortheen.nix-ide
          vscode.jock.svg
          vscode.llvm-vs-code-extensions.vscode-clangd
          vscode.mkhl.direnv
          vscode.moss-lang.moss-vscode
          vscode.ms-azuretools.vscode-containers
          vscode.ms-azuretools.vscode-docker
          vscode.ms-python.python
          vscode.ms-python.vscode-pylance
          vscode.ms-toolsai.jupyter
          vscode.ms-vscode.cmake-tools
          vscode.myriad-dreamin.tinymist
          vscode.rust-lang.rust-analyzer
          vscode.stkb.rewrap
          vscode.tamasfe.even-better-toml
          vscode.vadimcn.vscode-lldb
          vscode.xaver.clang-format
        ]
        ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          {
            publisher = "DIKU";
            name = "futhark-vscode";
            version = "0.1.3";
            sha256 = "sha256-URikRSOUR/vdOKGP8/wopROAd18J81pxii8+DHd0sa0=";
          }
          {
            publisher = "gplane";
            name = "wasm-language-tools";
            version = "1.15.0";
            sha256 = "sha256-PogHwExxQ9HjMEzh0ifqwk0KndLJLO8FkPVhiJSqvnQ=";
          }
          {
            publisher = "oven";
            name = "bun-vscode";
            version = "0.0.32";
            sha256 = "sha256-VlruOHiF5/wVhVVW1rq6DEc90u3IwbxD/tpTXyphD+U=";
          }
          {
            publisher = "samestep";
            name = "save-constantly";
            version = "0.1.0";
            sha256 = "sha256-s6M64yE1lx0mG/0zxYjNilMniflkAAhCxVccAU0jSEk=";
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
