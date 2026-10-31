{
  services.home-assistant = {
    enable = true;
    extraComponents = [
      "esphome"
      "tplink"
      "met"
      "radio_browser"
    ];
    config.default_config = { };
  };
  networking.firewall.allowedTCPPorts = [ 8123 ];
  networking.firewall.allowedUDPPorts = [ 5353 ];
}
