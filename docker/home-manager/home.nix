{
  config,
  lib,
  pkgs,
  ...
}:
let
  util = import ../../util.nix { inherit config pkgs; };
in
{
  nixpkgs = util.nixpkgs;

  home = {
    # # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "root";
    homeDirectory = "/root";

    packages = util.packages;

    file = util.file // {
      ".codex/config.toml" = util.symlink "docker/codex/config.toml";
    };

    activation = {
      # Prevent Bash warnings about not being able to change locale.
      localeArchive = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p /usr/lib/locale
        ln -sfn "${pkgs.glibcLocales}/lib/locale/locale-archive" /usr/lib/locale/locale-archive
      '';
    };
  };

  programs = util.programs // {
    bash = {
      enable = true; # Necessary for aliases and Starship to work.
      bashrcExtra = ''
        export USER=root
      '';
    };

    vscode.enable = false; # The extensions don't build properly inside Docker.
  };
}
