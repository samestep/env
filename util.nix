{ config, pkgs }:
{
  packages = [
    pkgs.code-cursor
    pkgs.gh
    pkgs.git

    (pkgs.writers.writePython3Bin "ghcode" { } ./ghcode.py)
  ];

  symlink = subpath: {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/github/samestep/env/${subpath}";
  };
}
