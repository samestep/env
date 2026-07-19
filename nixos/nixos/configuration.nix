# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Disable Wi-Fi power saving. The default lets the card sleep between packets,
  # which added ~60-110 ms to every LAN round-trip here — enough that Tailscale
  # rated this box's local DERP (below) as no faster than its cloud DERP and
  # refused to use it. Off, the LAN hop is ~5 ms and the local DERP wins.
  networking.networkmanager.wifi.powersave = false;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.sam = {
    isNormalUser = true;
    description = "Sam Estep";
    extraGroups = [
      "docker" # https://wiki.nixos.org/wiki/Docker#System_setup
      "libvirtd" # https://wiki.nixos.org/wiki/Virt-manager#Installation
      "networkmanager"
      "wheel"
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Local Tailscale DERP relay. My sandbox VMs are on the tailnet but each sits
  # behind per-VM NAT, and both physical machines are behind T-Mobile 5G CGNAT,
  # so Tailscale can never punch a direct path and relays everything through a
  # distant cloud DERP — up over the slow 5G uplink and back (~1 MB/s). Running a
  # DERP here, on the always-on LAN box, keeps that relay on the local network:
  # the VMs prefer it (lowest latency) at home and fall back to Tailscale's cloud
  # DERPs when away. This host does NOT join the tailnet — derper only forwards
  # already-encrypted WireGuard traffic, so it can neither read nor reach the VMs.
  #
  # Self-signed and cert-pinned in the tailnet DERP map, so no domain or ACME is
  # involved. Given an IP-address -hostname, derper mints its own cert on first
  # start and logs the exact DERPMap node JSON (including the `sha256-raw:` pin)
  # to paste into the tailnet policy. Read it after deploying with:
  #   journalctl -u derper | grep -A1 'Configure it in DERPMap'
  #
  # NB: the pinned IP below must stay put, or the cert/DERP-map pin will drift.
  # This gateway (Arcadyan TMO-G4AR) has no DHCP settings to reserve one, so the
  # box holds 192.168.12.10 as a static IP on its Wi-Fi connection (set once with
  # `nmcli con mod`, below the gateway's DHCP pool so it can never collide).
  networking.firewall.allowedTCPPorts = [ 443 ]; # derper HTTPS (the DERP itself)
  networking.firewall.allowedUDPPorts = [ 3478 ]; # derper STUN (netcheck latency probe)
  systemd.services.derper = {
    description = "Tailscale DERP relay (self-signed, LAN-only)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      # -c holds derper's own private key (created on first start). derper only
      # defaults this path when run as root; under DynamicUser it must be explicit.
      ExecStart = "${pkgs.tailscale.derper}/bin/derper -c /var/lib/derper/derper.key -a :443 -http-port -1 -certmode manual -certdir /var/lib/derper -hostname 192.168.12.10";
      DynamicUser = true;
      StateDirectory = "derper"; # persists the self-signed cert, so the pin is stable
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ]; # bind :443 as the dynamic user
      Restart = "on-failure";
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

  # https://wiki.nixos.org/wiki/Flakes#NixOS
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # https://wiki.nixos.org/wiki/NVIDIA#Kernel_modules_from_NVIDIA
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = true;

  # https://wiki.nixos.org/wiki/Virt-manager#Installation
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # https://libvirt.org/nss.html
  virtualisation.libvirtd.nss.enable = true;
  virtualisation.libvirtd.onShutdown = "shutdown"; # Else DHCP leases disappear.

  # Build virt-install with Ubuntu 26.04 support.
  nixpkgs.overlays = [
    (final: prev: {
      osinfo-db = prev.osinfo-db.overrideAttrs (old: {
        src = final.fetchFromGitLab {
          owner = "libosinfo";
          repo = "osinfo-db";
          rev = "6f01a968803a30c7e5da631b0205c5982b20b842";
          hash = "sha256-bG2fOBepSJebxrz07+FKwhmbu98IXesuLMaE6Np5f4M=";
        };
        installPhase = ''
          osinfo-db-import --dir "$out/share/osinfo" "osinfo-db-19800101.tar.xz"
        '';
      });
    })
  ];

  # https://wiki.nixos.org/wiki/Docker#System_setup
  virtualisation.docker.enable = true;

  # https://wiki.nixos.org/wiki/Steam#System_setup
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # https://wiki.nixos.org/wiki/OpenRGB#Basic
  services.hardware.openrgb.enable = true;

  # Use Ghostty instead of muscle memory.
  environment.gnome.excludePackages = [
    pkgs.gnome-console
  ];
}
