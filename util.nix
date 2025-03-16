{ config }:
{
  symlink = subpath: {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/github/samestep/env/${subpath}";
  };
}
