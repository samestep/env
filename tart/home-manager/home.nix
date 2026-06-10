{ ... }:
{
  home = {
    # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "admin";
    homeDirectory = "/Users/admin";
  };

  programs.zsh.enable = true; # Necessary for aliases and Starship to work.
}
