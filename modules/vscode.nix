{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    profiles.default.extensions =
      let
        vscode = pkgs.vscode-extensions;
      in
      [
        vscode.charliermarsh.ruff
        vscode.editorconfig.editorconfig
        vscode.esbenp.prettier-vscode
        vscode.github.vscode-github-actions
        vscode.gplane.wasm-language-tools
        vscode.jnoortheen.nix-ide
        vscode.jock.svg
        vscode.llvm-vs-code-extensions.vscode-clangd
        vscode.mkhl.direnv
        vscode.moss-lang.moss-vscode
        vscode.ms-python.python
        vscode.ms-python.vscode-pylance
        vscode.ms-vscode.cmake-tools
        vscode.myriad-dreamin.tinymist
        vscode.ocamllabs.ocaml-platform
        vscode.rocq-prover.vsrocq
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
}
