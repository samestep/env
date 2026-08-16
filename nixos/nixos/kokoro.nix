# Kokoro text to speech, spoken over the Wyoming protocol so Home Assistant can
# use it as a TTS provider. Kokoro is an 82M StyleTTS2 model under Apache 2.0
# and markedly more natural than Piper. Voices are listed at
# https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md
#
# This ran as a Docker container until now, because nothing in nixpkgs speaks
# Wyoming for Kokoro. The container was CPU-only and cost ~0.4 s of every reply,
# and the one published GPU image is a dead end: `kokoro-onnx[gpu]` asks for
# both `onnxruntime` and `onnxruntime-gpu`, which install over each other under
# the same import name, and the CPU one wins — that image reports only the Azure
# and CPU providers.
#
# nixpkgs' onnxruntime does build the CUDA execution provider, so the whole
# thing is packaged natively instead, with no Docker at all: kokoro-onnx (a thin
# pure-Python wrapper around the ONNX model) on top of a CUDA onnxruntime, plus
# upstream's Wyoming server, which is a single file.
{
  lib,
  pkgs,
  utils,
  ...
}:

let
  # onnxruntime with the CUDA execution provider. `nixpkgs.config.cudaSupport`
  # would turn this on globally and rebuild half the system, so override the one
  # package. NCCL is for multi-GPU collectives; there is one GPU here, and
  # dropping it avoids building nccl for nothing.
  onnxruntime = pkgs.onnxruntime.override {
    cudaSupport = true;
    ncclSupport = false;
  };

  onnxruntime-python = pkgs.python3Packages.onnxruntime.override { inherit onnxruntime; };

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
    # The CUDA execution provider defaults to cudnn_conv_algo_search=EXHAUSTIVE,
    # which benchmarks every convolution algorithm the first time it sees a
    # shape. Kokoro's tensors are as long as the sentence, so nearly every
    # request is a new shape and the search would be paid over and over.
    # HEURISTIC picks an algorithm from cuDNN's model instead.
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
      substituteInPlace src/kokoro_onnx/__init__.py \
        --replace-fail "providers = [env_provider]" \
          'providers = [(env_provider, {"cudnn_conv_algo_search": "HEURISTIC"})] if env_provider == "CUDAExecutionProvider" else [env_provider]'
    '';

    dependencies = [
      onnxruntime-python
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
    pkgs.runCommandLocal "kokoro-wyoming-1.0.2" { } ''
      mkdir -p $out/bin
      substitute ${src}/src/main.py $out/bin/kokoro-wyoming \
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
      # kokoro-onnx asks onnxruntime for exactly this provider; onnxruntime
      # always keeps the CPU provider behind it, so an operator with no CUDA
      # kernel still runs, just off the GPU. Of the 2464 nodes in this model
      # only the single STFT has no CUDA kernel in onnxruntime 1.24.
      ONNX_PROVIDER = "CUDAExecutionProvider";
      # Without this the server logs nothing at all: kokoro-onnx's logger
      # defaults to WARNING and the Wyoming server is a child of it. At INFO
      # every request prints its synthesis time, which is how you check that the
      # GPU is doing what it is supposed to. `--debug` would also work, but it
      # adds a line of phonemes per request.
      LOG_LEVEL = "INFO";
    };

    serviceConfig = {
      Type = "exec";
      # Prefixed with `-` so a missing provider is a log line, not a dead voice
      # assistant. This is the check that the nordwestt image would have failed.
      ExecStartPre = "-${python.interpreter} -c 'import onnxruntime; print(\"onnxruntime providers:\", onnxruntime.get_available_providers())'";
      ExecStart = utils.escapeSystemdExecArgs [
        "${kokoro-wyoming}/bin/kokoro-wyoming"
        "--uri"
        "tcp://127.0.0.1:10210"
        "--model"
        "${model}"
        "--voices"
        "${voices}"
      ];
      Restart = "on-failure";

      DynamicUser = true;
      CapabilityBoundingSet = [ "" ];
      # Same set services.ollama uses to reach the GPU, minus the ROCm and WSL
      # entries. PrivateDevices would hide all of it.
      DeviceAllow = [
        "char-nvidiactl"
        "char-nvidia-caps"
        "char-nvidia-frontend"
        "char-nvidia-uvm"
      ];
      DevicePolicy = "closed";
      PrivateDevices = false;
      LockPersonality = true;
      MemoryDenyWriteExecute = false; # required for onnxruntime
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProcSubset = "all"; # onnxruntime reads /proc/cpuinfo
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RemoveIPC = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service @resources"
        "~@privileged"
      ];
      UMask = "0077";
    };
  };
}
