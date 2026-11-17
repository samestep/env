{ config, ... }:

{
  imports = [
    ./kokoro.nix
    ./ollama.nix
    ./qwen-asr.nix
    ./zigbee.nix
  ];

  services.home-assistant = {
    enable = true;
    extraComponents = [
      "esphome"
      "tplink"
      "ollama"
      "met"
      "mqtt"
      "radio_browser"
      "wyoming"
    ];
    config = {
      default_config = { };
      automation = "!include automations.yaml";
    };
  };
  # The UI owns this file; create it only if it does not already exist.
  systemd.services.home-assistant.preStart = ''
    if [ ! -e "${config.services.home-assistant.configDir}/automations.yaml" ]; then
      echo '[]' > "${config.services.home-assistant.configDir}/automations.yaml"
    fi
  '';
  services.wyoming.faster-whisper.servers.assist = {
    enable = true;
    sttLibrary = "sherpa";
    model = "auto";
    language = "en";
    device = "cpu";
    uri = "tcp://127.0.0.1:10300";
    zeroconf.enable = false;
  };
  services.wyoming.piper.servers.assist = {
    enable = true;
    voice = "en_US-lessac-medium";
    uri = "tcp://127.0.0.1:10200";
    zeroconf.enable = false;
  };
  networking.firewall.allowedTCPPorts = [ 8123 ];
  networking.firewall.allowedUDPPorts = [ 5353 ];
}
