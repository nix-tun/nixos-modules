{ pkgs, config, lib, ... }: {
  options.nix-tun.services.headscale = {
    enable = lib.mkEnableOption "Enable Headscale Server";
    domain = lib.mkOption {
      type = lib.types.str;
      description = ''
        The domain from which headscale should be reached.
        The base domain for magic dns will be tailnet.$${config.nix-tun.services.headscale.domain}.
      '';
    };
  };

  config = lib.mkIf config.nix-tun.services.headscale.enable {
    nix-tun.utils.containers.headscale = {
      domains = {
        headscale = {
          domain = config.nix-tun.services.headscale.domain;
          port = 8080;
        };
        headplane = {
          domain = config.nix-tun.services.headscale.domain;
          path = "/admin";
          port = 3000;
        };
      };
      volumes = {
        "/var/lib/headscale" = { };
        "/var/lib/headplane" = { };
      };
      secrets = [
        "headplane-cookie-secret"
      ];
      config = { ... }: {
        services.headscale = {
          enable = true;
          address = "0.0.0.0";
          port = 8080;
          settings = {
            serverUrl = config.nix-tun.services.headscale.domain;
            dns = {
              magic_dns = true;
              override_local_dns = true;
              nameservers.global = [
                "9.9.9.9"
                "149.112.112.112"
                "2620:fe::fe"
                "2620:fe::9"
              ];
              base_domain = "tailnet.${config.nix-tun.services.headscale.domain}";
            };
          };
        };
        services.headplane = {
          enable = true;
          settings = {
            headscale = {
              config_path = config.services.headscale.config_path;
              url = config.nix-tun.services.headscale.domain;
            };
            integration = {
              agent.enabled = true;
            };
            server = {
              cookie_secret_path = "/secret/headplane-cookie-secret";
            };
          };
        };
      };
    };
  };
}
