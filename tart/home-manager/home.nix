{ pkgs, ... }:
{
  home = {
    # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "admin";
    homeDirectory = "/Users/admin";

    # The open-source `tailscale`/`tailscaled` variant: on macOS it's the only
    # one that can act as a Tailscale SSH server, so it's what lets the other
    # VMs control this one. The Linux VMs get Tailscale from its official
    # installer instead (see README).
    packages = [ pkgs.tailscale ];
  };

  programs.zsh.enable = true; # Necessary for aliases and Starship to work.
}
