{ pkgs }:
{
  definitely-typed = pkgs.mkShellNoCC {
    buildInputs = [
      pkgs.dprint
      pkgs.nodejs
      pkgs.pnpm
    ];
  };
  node = pkgs.mkShellNoCC {
    buildInputs = [
      pkgs.nodejs
    ];
  };
  pnpm = pkgs.mkShellNoCC {
    buildInputs = [
      pkgs.nodejs
      pkgs.pnpm
    ];
  };
  rust = pkgs.mkShell {
    buildInputs = [
      pkgs.rust-bin.stable.latest.default
    ];
  };
  uv = pkgs.mkShellNoCC {
    buildInputs = [
      pkgs.python3
      pkgs.uv
    ];
  };
  vscode = pkgs.mkShellNoCC {
    buildInputs = [
      pkgs.clang
      pkgs.krb5
      pkgs.llvm
      pkgs.nodejs_20
      pkgs.python3
    ];
  };
  yarn = pkgs.mkShellNoCC {
    buildInputs = [
      pkgs.nodejs
      pkgs.yarn
    ];
  };
}
