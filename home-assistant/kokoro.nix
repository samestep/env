# Kokoro TTS over Wyoming, using the George voice.
{
  lib,
  pkgs,
  utils,
  ...
}:

let
  espeak = lib.getLib pkgs.espeak-ng;

  kokoro-onnx = pkgs.python3Packages.buildPythonPackage {
    pname = "kokoro-onnx";
    version = "0.5.0-unstable-2026-07-05";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "thewh1teagle";
      repo = "kokoro-onnx";
      rev = "98ea02a5692534c2ba496708e2f19de25028412b";
      hash = "sha256-wF9nvk8j/mSQTIipBZP7UxI2VxIAt+lo2bdPrRLiF6c=";
    };

    build-system = [ pkgs.python3Packages.hatchling ];

    # espeakng-loader exists to ship a bundled espeak-ng inside a wheel, and
    # phonemizer-fork exists to make phonemizer accept that bundled copy.
    # Neither is wanted here: nixpkgs' phonemizer is already patched to point at
    # pkgs.espeak-ng and already carries the upstream commit that adds
    # set_data_path. python3Packages.misaki drops the same two dependencies the
    # same way.
    #
    postPatch = ''
      substituteInPlace pyproject.toml \
        --replace-fail '"espeakng-loader>=0.2.4",' "" \
        --replace-fail '"phonemizer-fork>=3.3.2",' '"phonemizer",'
      substituteInPlace src/kokoro_onnx/tokenizer.py \
        --replace-fail "import espeakng_loader" "" \
        --replace-fail "espeakng_loader.get_data_path()" \
          '"${espeak}/share/espeak-ng-data"' \
        --replace-fail "espeakng_loader.get_library_path()" \
          '"${espeak}/lib/libespeak-ng${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}"'
    '';

    dependencies = [
      pkgs.python3Packages.onnxruntime
      pkgs.python3Packages.numpy
      pkgs.python3Packages.phonemizer
    ];

    pythonImportsCheck = [ "kokoro_onnx" ];

    meta = {
      description = "TTS with Kokoro and ONNX Runtime";
      homepage = "https://github.com/thewh1teagle/kokoro-onnx";
      license = lib.licenses.mit;
    };
  };

  # Weights and voice embeddings, from the same release the container's
  # Dockerfile pins, with the same checksums.
  model = pkgs.fetchurl {
    url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx";
    hash = "sha256-fV347PfUsYeAFaMmhgU/0O6+K8N3I0YIdkzA7zY2psU=";
  };
  voices = pkgs.fetchurl {
    url = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin";
    hash = "sha256-vKYQuDCOjZnzLm/kGX5+wBZ5Jk7+0MrJFA/pwp8fv30=";
  };

  # The Wyoming server is one file with no packaging of its own, so install it
  # as a script with a Python that has its imports. nordwestt's fork rather than
  # relvacode's upstream because it takes the model paths as arguments instead
  # of reading them from the working directory, and because it caches repeated
  # phrases and strips the markdown the LLM sprinkles into its replies.
  python = pkgs.python3.withPackages (ps: [
    kokoro-onnx
    ps.numpy
    ps.wyoming
  ]);

  kokoro-wyoming =
    let
      src = pkgs.fetchFromGitHub {
        owner = "nordwestt";
        repo = "kokoro-wyoming";
        tag = "v1.0.2";
        hash = "sha256-IUgchZ3gYSQtZNB23hYPRcJZ+mrW5WcLLnJ0SOevt1E=";
      };
    in
    # The SIGTERM handler stops the asyncio server, which surfaces as a
    # CancelledError out of asyncio.run and a traceback with status 1. Docker
    # swallowed that; systemd would call every `systemctl stop` a failure.
    pkgs.runCommandLocal "kokoro-wyoming-1.0.2"
      { }
      ''
        mkdir -p src $out/bin
        cp ${src}/src/main.py src/main.py
        chmod +w src/main.py

        substitute src/main.py $out/bin/kokoro-wyoming \
          --replace-fail "#!/usr/bin/env python3" "#!${python.interpreter}" \
          --replace-fail "except KeyboardInterrupt:" \
            "except (KeyboardInterrupt, asyncio.CancelledError):"
        chmod +x $out/bin/kokoro-wyoming
      '';
in
{
  # So the server can be built and run by hand, without a rebuild:
  # nix build .#nixosConfigurations.nixos.config.system.build.kokoro-wyoming
  system.build.kokoro-wyoming = kokoro-wyoming;

  systemd.services.kokoro-tts = {
    description = "Kokoro text to speech over the Wyoming protocol";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      ONNX_PROVIDER = "CPUExecutionProvider";
      LOG_LEVEL = "INFO";
    };

    serviceConfig = {
      Type = "exec";
      ExecStart = utils.escapeSystemdExecArgs [
        "${kokoro-wyoming}/bin/kokoro-wyoming"
        "--uri"
        "tcp://127.0.0.1:10210"
        "--voice"
        "bm_george"
        "--model"
        "${model}"
        "--voices"
        "${voices}"
      ];
      Restart = "on-failure";

      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };
}
