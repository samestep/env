{
  lib,
  pkgs,
  symlink,
  ...
}:
{
  # Enabling this causes permission issues:
  # https://github.com/nix-community/home-manager/pull/8031
  targets.darwin.copyApps.enable = false;

  home = {
    # https://nix-community.github.io/home-manager/release-notes.xhtml
    stateVersion = "25.11";

    username = "samueles";
    homeDirectory = "/Users/samueles";

    packages = [
      pkgs.gh
      pkgs.lima
      pkgs.tart
      pkgs.softnet
    ];

    # Necessary for `git send-email` to work.
    sessionVariables = {
      NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };

    file = {
      "Library/Application Support/com.mitchellh.ghostty/config.ghostty" =
        symlink "ghostty/config.ghostty";
    };

    activation = {
      dock =
        let
          dockutil = "${pkgs.dockutil}/bin/dockutil";
          dockItems = lib.strings.concatLines (
            map (item: "run ${dockutil} --no-restart --add ${lib.strings.escapeShellArg item}") [
              "/System/Applications/System Settings.app"
              "/System/Applications/Utilities/Disk Utility.app"
              "/System/Applications/Utilities/Activity Monitor.app"
              "${pkgs.ghostty-bin}/Applications/Ghostty.app"
              "/Applications/Firefox.app"
              "/Applications/Discord.app"
              "${pkgs.slack}/Applications/Slack.app"
              "/Applications/zoom.us.app"
              "${pkgs.obsidian}/Applications/Obsidian.app"
              "${pkgs.vscode}/Applications/Visual Studio Code.app"
            ]
          );
        in
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${dockutil} --no-restart --remove all
          ${dockItems}
          run ${dockutil} --no-restart --add ~/Downloads --section others --display stack
          run /usr/bin/killall Dock
        '';
    };
  };

  # Autostart both sandbox VMs under Tart, each on softnet with isolation
  # disabled (`--net-softnet-allow=0.0.0.0/0`). That drops them onto one shared
  # vmnet bridge (192.168.2.0/24) where they can reach each other directly, which
  # in turn lets Tailscale punch a direct connection between them instead of
  # relaying — so two VMs on this one Mac stop hairpinning their traffic out to
  # the NixOS DERP relay and back (see the README's networking section).
  #
  # These are LaunchAgents, so they start at *login*: a Virtualization.framework
  # VM needs the user's GUI session, so a boot-time LaunchDaemon can't run one —
  # enable auto-login for a headless restart. `tart run` blocks while the VM is
  # up, and KeepAlive brings it back if it exits.
  #
  # softnet must be setuid root (it drives vmnet), which Home Manager can't set,
  # so it's a one-time privileged install (see README). The PATH below points
  # Tart at that setuid copy in /usr/local/bin.
  launchd.agents =
    let
      tartVM = name: {
        enable = true;
        config = {
          ProgramArguments = [
            "${pkgs.tart}/bin/tart"
            "run"
            "--no-graphics"
            "--net-softnet"
            "--net-softnet-allow=0.0.0.0/0"
            name
          ];
          RunAtLoad = true;
          KeepAlive = true;
          EnvironmentVariables.PATH = "/usr/local/bin:/usr/bin:/bin";
          StandardOutPath = "/Users/samueles/Library/Logs/tart-${name}.log";
          StandardErrorPath = "/Users/samueles/Library/Logs/tart-${name}.log";
        };
      };
    in
    {
      # The aarch64-linux VM, migrated off Lima; the aarch64-darwin VM.
      tart-sandbox-arm64 = tartVM "sandbox-arm64";
      tart-tahoe-vanilla = tartVM "tahoe-vanilla";
    };

  programs.zsh.enable = true; # Necessary for aliases and Starship to work.
}
