{
  config,
  lib,
  pkgs,
}:
rec {
  symlink = subpath: {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/github/samestep/env/${subpath}";
  };

  nixpkgs = {
    config.allowUnfree = true;
  };

  packages = [
    (pkgs.writeShellScriptBin "claude" ''
      export CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1
      exec ${pkgs.claude-code}/bin/claude "$@"
    '')
    pkgs.cloc
    pkgs.comma
    pkgs.git
    pkgs.nixfmt
    pkgs.npc

    (pkgs.symlinkJoin {
      name = "samestep";
      paths = [
        (pkgs.writeTextDir "template.nix" (builtins.readFile ./template.nix))
        (pkgs.writers.writePython3Bin "codex" {
          makeWrapperArgs = [
            "--prefix"
            "PATH"
            ":"
            (lib.makeBinPath [ pkgs.codex ])
          ];
        } ./bin/codex.py)
        (pkgs.writers.writePython3Bin "doing" { } ./bin/doing.py)
        (pkgs.writers.writePython3Bin "flake" { } ./bin/flake.py)
        (pkgs.writers.writePython3Bin "ghcode" { } ./bin/ghcode.py)
        (pkgs.writers.writePython3Bin "scratch" { } ./bin/scratch.py)
        (pkgs.writers.writePython3Bin "shell" { } ./bin/shell.py)
        (pkgs.writers.writePython3Bin "title" { } ./bin/title.py)
        (pkgs.writers.writePython3Bin "worktree" { } ./bin/worktree.py)
      ];
    })
  ];

  file = {
    ".claude/settings.json" = symlink "claude/safe.json";
    ".codex/config.toml" = symlink "codex/safe.toml";
    ".config/cloc" = symlink "cloc";
    ".gitconfig" = symlink ".gitconfig";
  };

  programs = {
    eza.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    nix-index.enable = false; # Comma obviates this slow command-not-found hook.

    starship.enable = true;

    vscode = {
      enable = true;
      profiles.default.extensions =
        let
          vscode = pkgs.vscode-extensions;
        in
        [
          vscode.charliermarsh.ruff
          vscode.esbenp.prettier-vscode
          vscode.github.vscode-github-actions
          vscode.gplane.wasm-language-tools
          vscode.jnoortheen.nix-ide
          vscode.jock.svg
          vscode.llvm-vs-code-extensions.vscode-clangd
          vscode.mkhl.direnv
          vscode.moss-lang.moss-vscode
          vscode.ms-azuretools.vscode-containers
          vscode.ms-azuretools.vscode-docker
          vscode.ms-python.python
          vscode.ms-python.vscode-pylance
          vscode.ms-vscode-remote.remote-containers
          vscode.ms-vscode-remote.remote-ssh
          vscode.ms-vscode.cmake-tools
          vscode.myriad-dreamin.tinymist
          vscode.rust-lang.rust-analyzer
          vscode.stkb.rewrap
          vscode.tamasfe.even-better-toml
          vscode.vadimcn.vscode-lldb
          vscode.xaver.clang-format
          vscode.ziglang.vscode-zig
        ]
        ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
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

  assertions = [
  ];
}
