{ ... }:
{
  home = {
    # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "26.05";

    username = "admin";
    homeDirectory = "/home/admin";
  };

  programs.bash.enable = true; # Necessary for aliases and Starship to work.
}
