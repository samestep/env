{ ... }:
{
  home = {
    # # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "agent-arm64";
    homeDirectory = "/home/agent-arm64";
  };

  programs.bash.enable = true; # Necessary for aliases and Starship to work.
}
