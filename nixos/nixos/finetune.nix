# Fine-tuning jobs for local models on this machine's GPU, submitted from
# libvirt guests. See ./finetune/server.py for the API. Like ollama in the
# local-LLM setup, the service binds 0.0.0.0 but the firewall only opens its
# port on virbr0, so only guests (at 192.168.122.1) can reach it.
#
# Guests never get a shell here: they send a dataset plus whitelisted
# hyperparameters, and the server runs fixed command lines in the pinned
# containers below, one job at a time.

{ pkgs, ... }:

let
  port = 11500;
  servePort = 11501;

  # Pinned by digest; bump deliberately. Axolotl trains and merges LoRAs,
  # llama.cpp converts the merged weights to GGUF and quantizes them.
  trainImage = "axolotlai/axolotl@sha256:f7d780793920fb6cfef78f761f230be7263accebf79990f27793f475c53626af";
  convertImage = "ghcr.io/ggml-org/llama.cpp@sha256:0b15a75ef8566393f1d89fb655ef51745103907cc3f376dc92ddfe38ead565ee";

  # Hugging Face repos a job may start from. Weights are cached under
  # /var/lib/finetune/hf after the first download.
  allowedModels = [
    "Qwen/Qwen3.8-27B" # dense, QLoRA fits in 48 GB
    "Qwen/Qwen3-14B-Base" # largest dense Qwen base model; cheaper runs
    "Qwen/Qwen3.5-9B-Base" # fast iteration
    # Largest ungated dense base models; the woSyn variant was pretrained
    # without synthetic instruction data. QLoRA fits in 48 GB.
    "ByteDance-Seed/Seed-OSS-36B-Base"
    "ByteDance-Seed/Seed-OSS-36B-Base-woSyn"
  ];
in
{
  # Lets Docker hand the GPU to containers via CDI (`--device nvidia.com/gpu=all`).
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker.daemon.settings.features.cdi = true;

  users.groups.finetune = { };
  users.users.finetune = {
    isSystemUser = true;
    group = "finetune";
    extraGroups = [ "docker" ];
  };

  systemd.services.finetune = {
    description = "Fine-tuning job runner for libvirt guests";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "docker.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    path = [ pkgs.docker ];
    environment = {
      FINETUNE_STATE = "/var/lib/finetune";
      FINETUNE_LISTEN = "0.0.0.0";
      FINETUNE_PORT = toString port;
      FINETUNE_SERVE_BIND = "192.168.122.1";
      FINETUNE_SERVE_PORT = toString servePort;
      FINETUNE_ALLOWED_MODELS = builtins.toJSON allowedModels;
      FINETUNE_TRAIN_IMAGE = trainImage;
      FINETUNE_CONVERT_IMAGE = convertImage;
      # Run in the training image for scoring/generation with an adapter.
      FINETUNE_FORWARD_SCRIPT = "${./finetune/forward.py}";
      # If ollama is running, its resident models are unloaded before each
      # training run so the GPU's memory is free.
      FINETUNE_OLLAMA_URL = "http://127.0.0.1:11434";
    };
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${./finetune/server.py}";
      # Containers outlive the `docker run` clients systemd kills on stop.
      ExecStopPost = "${pkgs.bash}/bin/sh -c '${pkgs.docker}/bin/docker ps -q --filter name=^finetune- | ${pkgs.findutils}/bin/xargs -r ${pkgs.docker}/bin/docker kill'";
      User = "finetune";
      Group = "finetune";
      StateDirectory = "finetune";
      Restart = "on-failure";
      # Training is long; don't let a stop wait forever on a container.
      TimeoutStopSec = 30;
    };
  };

  # servePort: llama-server for a finished job, which Docker publishes on
  # 192.168.122.1 only (Docker's own port rules bypass this firewall).
  networking.firewall.interfaces."virbr0".allowedTCPPorts = [
    port
    servePort
  ];
}
