{ pkgs, config, lib, ... }: {
  options = {
    nix-tun.services.grafana = {
      enable = lib.mkEnableOption "Enable grafana on this server";
      domain = lib.mkOption {
        description = "The domain from which grafana should be reached";
        type = lib.types.str;
      };
      oauth = lib.mkOption {
        type = lib.types.attrs;
        description = ''
          The o-auth options for grafana. For reference: https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/
        '';
      };
      prometheus = {
        nixosConfigs = lib.mkOption {
          type = lib.types.unspecified;
          description = ''
            A list of nixos config from which the prometheus exporters will be read.
            The scrapers will be extracted from their `config.nix-tun.utils.prometheus-exporter` key.
          '';
        };
        domain = lib.mkOption {
          description = "The domain from which prometheus should be reached";
          type = lib.types.str;
        };
      };
    };
  };

  config = lib.mkIf config.nix-tun.services.grafana.enable {
    containers.grafana = {
      autoStart = true;
      privateNetwork = true;
      timeoutStartSec = "5min";
      bindMounts = lib.attrsets.mapAttrs'
        (job-name: targets:
          {
            name = config.sops.secrets."prometheus-${job-name}-pass".path;
            value.hostPath = config.sops.secrets."prometheus-${job-name}-pass".path;
          }
        )
        (lib.attrsets.foldAttrs (n: a: n ++ a) [ ]
          (lib.attrsets.mapAttrsToList
            (host: config: config.config.nix-tun.utils.prometheus-exporter)
            config.nix-tun.services.grafana.prometheus.nixosConfigs));
    };

    nix-tun.services.traefik.services."grafana-grafana" = {
      router.tls.enable = false;
    };

    sops.secrets = lib.attrsets.mapAttrs'
      (job-name: targets:
        {
          name = "prometheus-${job-name}-pass";
          value.uid = config.containers.grafana.config.users.users.prometheus.uid;
        }
      )
      (lib.attrsets.foldAttrs (n: a: n ++ a) [ ]
        (lib.attrsets.mapAttrsToList
          (host: config: config.config.nix-tun.utils.prometheus-exporter)
          config.nix-tun.services.grafana.prometheus.nixosConfigs));

    nix-tun.utils.containers.grafana = {
      volumes = {
        "/var/lib/grafana" = {
          owner = "grafana";
        };
        "/var/lib/prometheus2" = {
          owner = "prometheus";
        };
      };
      domains = {
        grafana = {
          domain = config.nix-tun.services.grafana.domain;
          port = 3000;
        };
      };
      config = { ... }: {
        boot.isContainer = true;
        services.prometheus = {
          enable = true;
          port = 9000;
          scrapeConfigs = lib.attrsets.mapAttrsToList
            (job-name: targets:
              {
                job_name = job-name;
                basic_auth = {
                  username = job-name;
                  password_file = config.sops.secrets."prometheus-${job-name}-pass".path;
                };
                scheme = "http";
                static_configs = [{
                  targets = targets;
                }];
              }
            )
            (lib.attrsets.foldAttrs (n: a: n ++ a) [ ]
              (lib.attrsets.mapAttrsToList
                (host: config: config.config.nix-tun.utils.prometheus-exporter)
                config.nix-tun.services.grafana.prometheus.nixosConfigs));
        };

        services.grafana = {
          enable = true;
          settings = {
            server = {
              domain = config.nix-tun.services.grafana.domain;
              http_addr = "0.0.0.0";
              root_url = "https://${config.nix-tun.services.grafana.domain}";
            };
            "auth.basic".enable = false;
            auth.disable_login_form = true;
            "auth.generic_oauth" = config.nix-tun.services.grafana.oauth;
          };
        };
        networking.firewall.allowedTCPPorts = [ 3000 ];
      };
    };
  };
}
