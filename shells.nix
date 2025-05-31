{ pkgs, fenix }:
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
      (fenix.packages.${pkgs.system}.stable.toolchain)
    ];
  };
  uv = pkgs.mkShellNoCC {
    buildInputs = [
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
