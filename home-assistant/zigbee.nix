{ lib, pkgs, ... }:

{
  # Both clients run on this host, so MQTT needs no LAN listener or credentials.
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        settings.allow_anonymous = true;
        omitPasswordAuth = true;
        acl = [ "topic readwrite #" ];
      }
    ];
  };

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      mqtt.server = "mqtt://127.0.0.1:1883";
      homeassistant.enabled = true;
      serial = {
        adapter = "zstack";
        port = "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_36fcb3e6c5a3ef11b7c64fbd61ce3355-if00-port0";
      };
      frontend = {
        enabled = true;
        host = "127.0.0.1";
        port = 8080;
      };
      advanced = {
        channel = 25;
        network_key = "!network-secret.yaml network_key";
      };
    };
  };

  systemd.services.zigbee2mqtt = {
    requires = [ "mosquitto.service" ];
    after = [ "mosquitto.service" ];
    # NixOS replaces configuration.yaml on every start. Keep the random key in
    # a separate, persistent file so rebuilding never changes the network key.
    preStart = ''
      if [ ! -e network-secret.yaml ]; then
        ${lib.getExe pkgs.python3} -c 'import json, secrets; print(json.dumps({"network_key": list(secrets.token_bytes(16))}))' > network-secret.yaml
      fi
    '';
  };
}
