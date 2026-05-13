{ pkgs }:
{
  node = pkgs.mkShellNoCC {
    packages = [
      pkgs.nodejs
    ];
  };
  pnpm = pkgs.mkShellNoCC {
    packages = [
      pkgs.nodejs
      pkgs.pnpm
    ];
  };
  rust = pkgs.mkShell {
    packages = [
      pkgs.rust-bin.stable.latest.default
    ];
  };
  uv = pkgs.mkShellNoCC {
    packages = [
      pkgs.python3
      pkgs.uv
    ];
    LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
  };
  yarn = pkgs.mkShellNoCC {
    packages = [
      pkgs.nodejs
      pkgs.yarn
    ];
  };
}
