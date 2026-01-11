{
  config,
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

    username = "agent";
    homeDirectory = "/home/agent";

    packages = util.packages;

    file = util.file // {
      ".codex/config.toml" = util.symlink "docker/codex/config.toml";
    };

    sessionVariables = {
      # Prevent Bash warnings about not being able to change locale.
      LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
    };
  };

  programs = util.programs // {
    bash.enable = true; # Necessary for aliases and Starship to work.
  };
}
