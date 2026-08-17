# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  nixpkgsUnstable,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./kokoro.nix
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
      # The assistant has to stay resident; a 30 s reload before "turn off the
      # lights" is the difference between usable and infuriating.
      OLLAMA_KEEP_ALIVE = "-1";
      # Every fresh conversation was re-running the whole system prompt: 0.65 s
      # against 0.19 s when the prefix was already cached. The cause is in
      # llama-server, which ollama runs as a subprocess. Slot selection falls to
      # LRU (--slot-prompt-similarity defaults to 0 and has no env binding), and
      # the LRU path does this:
      #
      #     ret->prompt_save(*prompt_cache);
      #     if (!ret->prompt_load(*prompt_cache, task.tokens)) {
      #         ret->prompt_clear();
      #     }
      #
      # so when the level-2 cache has no better match it *clears the slot*,
      # throwing away a prefix that ordinary common-prefix reuse would have
      # kept. That block is guarded by `update_cache && prompt_cache`, and the
      # cache is only built when cache_ram_mib != 0 — so switching it off stops
      # the clearing. llama-server inherits this environment (cmd.Env =
      # os.Environ()), so no patch is needed.
      #
      # Nothing is lost: that cache exists to restore evicted conversations when
      # serving many at once, and this host serves one.
      LLAMA_ARG_CACHE_RAM = "0";
    };
    # ~54 GB of downloads, pulled by ollama-model-loader.service after switch.
    # qwen3.8 needs ollama >= 0.32.12; 26.05 ships 0.32.3, so it's out for now.
    # The dense model is the assistant, despite being 5x slower to generate.
    # ollama 0.32.3 faults with "CUDA error: an illegal memory access was
    # encountered" when qwen35moe does constrained decoding for tool calls with
    # array/enum parameters — which is exactly what Home Assistant sends. It is
    # intermittent, poisons the runner's CUDA context, and does not reproduce on
    # the dense model. Generation speed is not the binding constraint for voice
    # anyway: a 30-token reply is under half a second either way.
    loadModels = [
      "qwen3.6:27b-mtp-q8_0" # 30 GB, index 38. The assistant.
      "qwen3.6:35b-a3b-q4_K_M" # 24 GB, index 32 — faster, but see above.
    ];
  };

  # Voice assistant. With `prefer_local_intents` on (a per-pipeline setting,
  # off by default) the built-in sentence matcher answers anything it
  # recognises without involving the model, so "turn off the kitchen light"
  # comes back in milliseconds. The exceptions are GET_STATE and media search,
  # which assist_pipeline deliberately withholds from the local path when the
  # agent has control, so that state questions go to the model and it answers
  # them with GetLiveContext. Measured: a matched command is ~0.01 s, anything
  # reaching the model is ~1-3 s.
  # Pipelines and wake words are chosen in the UI, not here; these services
  # announce themselves over zeroconf and Home Assistant discovers them.
  services.home-assistant = {
    enable = true;
    openFirewall = true; # Satellites and phones live on the LAN, not virbr0.
    extraComponents = [
      "assist_pipeline"
      "demo" # Fake lights etc, so assistant evaluations have something to control.
      "esphome" # Voice Preview Edition and any other satellites.
      "met"
      "ollama"
      "radio_browser"
      "wyoming"
    ];
    config = {
      default_config = { };
      homeassistant.time_zone = config.time.timeZone;

      # Gives lights, switches, fans and covers with realistic names, which lets
      # an evaluation grade "turn on the kitchen light" against actual state
      # rather than against the wording of a refusal. Only a chosen handful are
      # exposed to Assist — every exposed entity lands in the system prompt, so
      # exposing all of them would inflate prefill and change what is measured.
      # ("expose new entities" is off for the conversation assistant.)
      demo = { };

      # Queries the local SearXNG. Exposing the script below to Assist turns it
      # into a tool the model can call, and ActionTool hands the response back,
      # so this is how the assistant learns anything after its training cutoff.
      rest_command.web_search = {
        url = "http://127.0.0.1:${toString config.services.searx.settings.server.port}/search?q={{ query | urlencode }}&format=json";
        method = "GET";
        timeout = 20;
      };

      # The conversation agent's system prompt lives in Home Assistant's
      # storage, not here, so it is not captured by a rebuild. The wording that
      # actually works, after several that did not:
      #
      #   Your training data is out of date and your memory of current facts is
      #   wrong.
      #   Call GetDateTimeTool for the current date or time.
      #   Call GetLiveContext for the state of anything in this house,
      #   including the weather.
      #   Call search_the_web for news, current events, prices, sports, or who
      #   currently holds any office or title.
      #   If you find yourself recalling a name, number or event from memory for
      #   such a question, that recollection is stale: search instead.
      #   Never say you lack access to current information. Only say you do not
      #   know if a tool returned nothing useful.
      #
      # The last two lines matter most: an earlier version told it to say it did
      # not know, which made it decline rather than reach for the tool.
      script.search_the_web = {
        alias = "Search the web";
        # This description is the tool description the model sees.
        description = "Search the web for current information. Use this for news, current events, prices, or any question whose answer may have changed since training.";
        fields.query = {
          description = "What to search for";
          example = "current president of the united states";
          required = true;
          selector.text = { };
        };
        sequence = [
          {
            action = "rest_command.web_search";
            data.query = "{{ query }}";
            response_variable = "raw";
          }
          {
            # A script response has to be a dict: ServiceResponse is
            # JsonObjectType | None, so returning a bare list would fail.
            variables.results.snippets = ''
              {{ (raw.content.results | default([]))[:5]
                 | map(attribute='content') | select('string') | list }}'';
          }
          {
            stop = "done";
            response_variable = "results";
          }
        ];
      };
    };
  };

  # Private metasearch, so the assistant can look things up without handing the
  # query to Google. Loopback only; Home Assistant is the only client.
  # SearXNG refuses to start on the stock secret key, and it shouldn't live in
  # the world-readable Nix store, so mint one on first boot. This has to be its
  # own unit: systemd reads EnvironmentFile before any ExecStartPre of the
  # service that uses it.
  # Order against searx-init, not searx: the module gives searx-init the same
  # EnvironmentFile and searx.service requires it, so searx-init is what reads
  # the file first and what fails if it is missing.
  systemd.services.searx-secret = {
    wantedBy = [ "searx-init.service" ];
    before = [ "searx-init.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "searx";
      UMask = "0077";
    };
    script = ''
      if [ ! -s /var/lib/searx/secret.env ]; then
        printf 'SEARX_SECRET_KEY=%s\n' "$(head -c 32 /dev/urandom | base64)" \
          > /var/lib/searx/secret.env
      fi
    '';
  };

  services.searx = {
    enable = true; # Built-in HTTP server: configureUwsgi is for public instances.
    environmentFile = "/var/lib/searx/secret.env";
    settings = {
      server = {
        bind_address = "127.0.0.1";
        port = 8888;
        secret_key = "$SEARX_SECRET_KEY";
        limiter = false; # Bot detection would reject Home Assistant's requests.
      };
      search.formats = [
        "html"
        "json"
      ];
    };
  };

  # Speech to text. CPU by default: `device = "cuda"` needs ctranslate2 built
  # with CUDA, which is a much bigger rebuild than it sounds.
  services.wyoming.faster-whisper.servers.en = {
    enable = true;
    uri = "tcp://127.0.0.1:10300";
    language = "en";
    device = "cpu";
  };

  # Text to speech. Piper was archived upstream on 2025-10-06 and sounds every
  # bit its age; kept only to A/B against Kokoro, and worth deleting once that
  # comparison is settled.
  services.wyoming.piper.servers.en = {
    enable = true;
    uri = "tcp://127.0.0.1:10200";
    voice = "en-us-ryan-medium";
  };

  # Kokoro, the other text to speech engine, is big enough to live in
  # ./kokoro.nix: it is packaged there rather than pulled as a container, so
  # that it can run on the GPU. It listens on 127.0.0.1:10210, as the container
  # did, so Home Assistant's Wyoming entry for it does not change.

  # Wake word. Models are picked per-pipeline in the UI; `preloadModels` was
  # removed in wyoming-openwakeword 2.0. Unlike the faster-whisper and piper
  # modules this one has no `zeroconf` option, so Home Assistant never discovers
  # it; upstream does support the flag, so pass it directly.
  services.wyoming.openwakeword = {
    enable = true;
    uri = "tcp://127.0.0.1:10400";
    # The package has no optional-dependencies to splice the way the
    # faster-whisper module does, so take the extra from the wyoming library
    # itself; `--zeroconf` is an ImportError without it.
    package = pkgs.wyoming-openwakeword.overridePythonAttrs (old: {
      dependencies = old.dependencies ++ pkgs.python3Packages.wyoming.optional-dependencies.zeroconf;
    });
    extraArgs = [ "--zeroconf" ];
  };
  # Zeroconf enumerates network interfaces, which needs netlink. The piper and
  # faster-whisper modules add this themselves when their zeroconf option is on.
  systemd.services.wyoming-openwakeword.serviceConfig.RestrictAddressFamilies = [
    "AF_NETLINK"
  ];

  # Only needed to build custom satellite firmware; the Voice PE works without it.
  services.esphome.enable = true;

  # Only the VMs, not the whole LAN.
  networking.firewall.interfaces."virbr0".allowedTCPPorts = [
    config.services.ollama.port
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

  nixpkgs.overlays = [
    # 26.05 ships ollama 0.32.3, which predates the Muse Glimmer architecture
    # (added in 0.32.7). The unstable input is already pinned at exactly 0.32.7,
    # so take it from there rather than overriding a buildGoModule by hand.
    # Instantiating with `final.config` carries over allowUnfree and the
    # cudaCapabilities pin, so this is still an sm_89-only build.
    (final: prev: {
      inherit
        (import nixpkgsUnstable {
          inherit (final.stdenv.hostPlatform) system;
          inherit (final) config;
        })
        ollama-cuda
        ;
    })

    # Build virt-install with Ubuntu 26.04 support.
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
