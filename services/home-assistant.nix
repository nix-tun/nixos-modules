{ pkgs, lib, config, ... }: {
  options = {
    nix-tun.services.home-assistant = {
      enable = lib.mkEnableOption "Enable Home Assitant";
      domain = lib.mkOption {
        type = lib.types.str;
      };
    };
  };

  config = lib.mkIf config.nix-tun.services.home-assistant.enable {
    contracts.oauth.responder.${config.contracts.oauth.defaultResponder}.request.home-assistant = {
      clientId = "home-assistant";
      redirectUris = [ "https://${config.nix-tun.services.home-assistant.domain}/auth/oidc/callback" ];
      authMethod = "client_secret_post";
      scopes = [ "openid profile email" ];
    };

    contracts.reverseProxy.responder.${config.contracts.reverseProxy.defaultResponder}.request.home-assistant = {
      domain = config.nix-tun.services.home-assistant.domain;
      internalUrl = "http://localhost:8123";
    };

    sops.templates."home-assistant-client-secret" = {
      uid = config.users.users.hass.uid;
      path = "/var/lib/hass/secrets.yaml";
      content = ''
        client_secret: ${config.sops.placeholder."authelia-client-secret-home-assistant"}
      '';
    };

    networking.firewall.allowedTCPPorts = [ 8123 ];
    networking.firewall.allowedUDPPorts = [ 5353 ];

    environment.systemPackages = [ pkgs.zlib pkgs.isa-l ];

    nix-tun.storage.persist.subvolumes.home-assistant = {
      bindMountDirectories = true;
      directories = {
        "/var/lib/hass" = {
          owner = "hass";
        };
      };
    };

    services.matterjs-server = {
      enable = true;
      openFirewall = true;
      extraArgs = [
        "--primary-interface=br0"
        "--ble-proxy"
      ];
      listenAddress = "br0";
      port = 5580;
      bluetoothSupport = false;
    };

    services.home-assistant = {
      enable = true;
      extraComponents = [
        "my"
        "matter"
        "mobile_app"
        "default_config"
        "thread"
        "jellyfin"
        "nextcloud"
        "homekit_controller"
        "cloudflare"
        "kodi"
        "wakeonlan"
      ];

      customComponents = with pkgs.home-assistant-custom-components; [
        auth_oidc
      ];
      config = {
        homeassistant = {
          unit_system = "metric";
          time_zone = "Europe/Berlin";
          external_url = "https://${config.nix-tun.services.home-assistant.domain}";
          internal_url = "https://${config.nix-tun.services.home-assistant.domain}";
        };
        automation = "!include automations.yaml";
        mobile_app = { };
        default_config = { };
        my = { };
        auth_oidc = {
          client_id = "home-assistant";
          client_secret = "!secret client_secret";
          discovery_url = config.contracts.oauth.responder.${config.contracts.oauth.defaultResponder}.response.home-assistant.discoveryUrl;
          display_name = "Authelia";
          features = {
            automatic_user_linking = true;
            default_redirect = true;
          };
        };
      };
    };
  };
}
