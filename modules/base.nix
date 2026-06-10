{
  config,
  lib,
  pkgs,
  ...
}:
let
  symlink = subpath: {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/github/samestep/env/${subpath}";
  };
in
{
  # Expose `symlink` to the other modules and the host configs.
  _module.args.symlink = symlink;

  nixpkgs.config.allowUnfree = true;

  home.packages = [
    (pkgs.writeShellScriptBin "claude" ''
      export CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1
      exec ${pkgs.claude-code}/bin/claude "$@"
    '')
    pkgs.cloc
    pkgs.comma
    pkgs.git
    pkgs.nh # https://github.com/nix-community/nix-index/issues/317
    pkgs.nixfmt
    pkgs.npc

    (pkgs.symlinkJoin {
      name = "samestep";
      paths = [
        (pkgs.writeTextDir "template.nix" (builtins.readFile ../template.nix))
        (pkgs.writers.writePython3Bin "codex" {
          makeWrapperArgs = [
            "--prefix"
            "PATH"
            ":"
            (lib.makeBinPath [ pkgs.codex ])
          ];
        } ../bin/codex.py)
        (pkgs.writers.writePython3Bin "doing" { } ../bin/doing.py)
        (pkgs.writers.writePython3Bin "flake" { } ../bin/flake.py)
        (pkgs.writers.writePython3Bin "ghcode" { } ../bin/ghcode.py)
        (pkgs.writers.writePython3Bin "scratch" { } ../bin/scratch.py)
        (pkgs.writers.writePython3Bin "shell" { } ../bin/shell.py)
        (pkgs.writers.writePython3Bin "title" { } ../bin/title.py)
        (pkgs.writers.writePython3Bin "worktree" { } ../bin/worktree.py)
      ];
    })
  ];

  home.file = {
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
  };
}
