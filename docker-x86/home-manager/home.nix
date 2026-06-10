{ ... }:
{
  home = {
    # # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "agent-amd64";
    homeDirectory = "/home/agent-amd64";
  };

  programs.bash.enable = true; # Necessary for aliases and Starship to work.
}
