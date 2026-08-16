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

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

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

  # Keep the driver loaded so the first request to a cold GPU isn't slow.
  hardware.nvidia.nvidiaPersistenced = true;

  # The RTX 5880 Ada is compute capability 8.9; only build CUDA kernels for it.
  nixpkgs.config.cudaCapabilities = [ "8.9" ];

  # Models small enough to sit entirely in VRAM.
  # https://wiki.nixos.org/wiki/Ollama
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "0.0.0.0"; # So libvirt guests can reach it at 192.168.122.1.
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "32768"; # Otherwise it's tiered off total VRAM.
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KEEP_ALIVE = "30m"; # Don't evict a 30 GB model after five minutes.
    };
    # ~54 GB of downloads, pulled by ollama-model-loader.service after switch.
    # qwen3.8 needs ollama >= 0.32.12; 26.05 ships 0.32.3, so it's out for now.
    loadModels = [
      "qwen3.6:27b-mtp-q8_0" # 30 GB, index 38 — best quality that fits.
      "qwen3.6:35b-a3b-q4_K_M" # 24 GB, index 32 — 3B active, ~3x the speed.
    ];
  };

  # DeepSeek-V4-Flash is 284B parameters but only ~13B active, and 97% of it is
  # expert weights, so `fit = "on"` parks those in system RAM and keeps
  # attention and the KV cache on the GPU. That buys a much stronger model than
  # anything that fits in VRAM alone, but measures 5.2 tok/s rather than the ~65
  # the ollama models get: the CPU-side experts are bound by unpacking 3-bit
  # weights, not by RAM bandwidth. Needs the sandbox VM shut down for its ~100 GB.
  services.llama-cpp = {
    enable = true;
    package = (pkgs.llama-cpp.override { cudaSupport = true; }).overrideAttrs (
      finalAttrs: prev: {
        # nixpkgs ships b9190; DSpark speculative decoding landed in b10231.
        version = "10448";
        src = pkgs.fetchFromGitHub {
          owner = "ggml-org";
          repo = "llama.cpp";
          tag = "b${finalAttrs.version}";
          hash = "sha256-MFfSD/lewA6k7th+sTr0a5qSOEtSG5y2Zr5lP/15XGA=";
          leaveDotGit = true;
          postFetch = ''
            git -C "$out" rev-parse --short HEAD > $out/COMMIT
            find "$out" -name .git -print0 | xargs -0 rm -rf
          '';
        };
        npmDepsHash = "sha256-2Q7XhaLAArmviOLdQsNbYTfdyDE5pW9lR26cRHEVl9k=";
      }
    );
    host = "0.0.0.0";
    port = 8081; # 8080 is Open WebUI.
    # Router mode: nothing is loaded until the first request names the alias,
    # so this service starting at boot costs nothing.
    modelsPreset."DeepSeek-V4-Flash" = {
      hf-repo = "unsloth/DeepSeek-V4-Flash-0731-GGUF";
      hf-file = "UD-Q3_K_XL/DeepSeek-V4-Flash-0731-UD-Q3_K_XL-00001-of-00004.gguf";
      alias = "deepseek-v4-flash";
      fit = "on"; # Works out the CPU/GPU expert split itself.
      # `fit` can't measure a dspark drafter's memory, so it would hand all the
      # VRAM to the experts and leave the 10.4 GB draft model with nowhere to go.
      fit-target = "13312";
      spec-type = "draft-dspark"; # Also fetches DeepSeek's 11 GB drafter sidecar.
      ctx-size = "32768";
      jinja = "on";
    };
  };

  # Only the VMs, not the whole LAN.
  networking.firewall.interfaces."virbr0".allowedTCPPorts = [
    config.services.ollama.port
    config.services.llama-cpp.port
  ];

  # Chat UI at http://localhost:8080
  services.open-webui = {
    enable = true;
    environment = {
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      OLLAMA_API_BASE_URL = "http://127.0.0.1:${toString config.services.ollama.port}";
      WEBUI_AUTH = "False"; # Single-user machine.
    };
  };

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
