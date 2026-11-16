{ pkgs, nixpkgsUnstable, ... }:
let
  # Native Qwen3-ASR needs Transformers >= 5.13; stable currently has 5.5.
  speechPkgs = import nixpkgsUnstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
    # This host's RTX 5880 Ada; avoid compiling NCCL for every CUDA GPU.
    config.cudaCapabilities = [ "8.9" ];
  };
  runtime = speechPkgs.python313.withPackages (ps: [
    # Use the prebuilt CUDA wheel rather than compiling PyTorch.
    ps.torch-bin
    ps.transformers
    ps.librosa
    ps.soundfile
    ps.aiohttp
    ps.wyoming
  ]);
in
{
  # Useful for checking imports without starting/downloading the model.
  system.build.qwen-asr-python = runtime;
  systemd.services.wyoming-qwen-asr = {
    description = "Qwen3-ASR 1.7B speech recognition over Wyoming";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      HF_HOME = "/var/lib/qwen-asr/huggingface";
      HF_HUB_DISABLE_TELEMETRY = "1";
      TOKENIZERS_PARALLELISM = "false";
      PYTHONUNBUFFERED = "1";
    };
    serviceConfig = {
      ExecStart = "${runtime}/bin/python ${./.}/qwen-asr.py --uri tcp://127.0.0.1:10310 --beam-size 5";
      Restart = "on-failure";
      RestartSec = 10;
      DynamicUser = true;
      # systemd reads /etc/credstore/qwen-asr-home-assistant-token. Missing
      # credentials are optional: ASR still works, with no vocabulary hints.
      LoadCredential = [ "qwen-asr-home-assistant-token" ];
      StateDirectory = "qwen-asr";
      WorkingDirectory = "/var/lib/qwen-asr";
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      NoNewPrivileges = true;
      # CUDA must be able to see /dev/nvidia*.
      PrivateDevices = false;
    };
  };
}
