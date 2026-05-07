{ pkgs }:
{
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
  yarn = pkgs.mkShellNoCC {
    buildInputs = [
      pkgs.nodejs
      pkgs.yarn
    ];
  };
}
