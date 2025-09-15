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
      loki = {
        domain = lib.mkOption {
          type = lib.types.str;
          description = "The domain under which loki should be reached";
        };
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
    nix-tun.services.traefik.services."grafana-loki" = {
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
        "/var/lib/loki" = {
          owner = "loki";
        };
      };
      domains = {
        grafana = {
          domain = config.nix-tun.services.grafana.domain;
          port = 3000;
        };
        loki = {
          domain = config.nix-tun.services.grafana.loki.domain;
          port = 3100;
        };
      };
      config = { ... }: {
        boot.isContainer = true;
        services.loki = {
          enable = true;
          configuration = {
            auth_enabled = true;
            server = {
              http_listen_port = 3100;
            };
            # The Ammount of Virtual Memory to reserve as ballast 
            # A higher ammount will reduce Garbage Collection Overhead
            ballast_bytes = 1024 * 1024;
            ingester = {
              lifecycler = {
                address = "0.0.0.0";
                ring = {
                  kvstore = {
                    store = "inmemory";
                  };
                  replication_factor = 1;
                };
                final_sleep = "0s";
              };
              chunk_idle_period = "1h"; # Any chunk not receiving new logs in this time will be flushed
              max_chunk_age = "1h"; # All chunks will be flushed when they hit this age, default is 1h
              chunk_target_size = 1048576; # Loki will attempt to build chunks up to 1.5MB, flushing first if chunk_idle_period or max_chunk_age is reached first
              chunk_retain_period = "30s"; # Must be greater than index read cache TTL if using an index cache (Default index read cache TTL is 5m)
            };
            schema_config = {
              configs = [
                {
                  from = "1970-01-01";
                  store = "boltdb-shipper";
                  object_store = "filesystem";
                  schema = "v13";
                  index = {
                    prefix = "index/";
                    period = "24h";
                  };
                }
              ];
            };
            storage_config = {
              boltdb_shipper = {
                active_index_directory = "/var/lib/loki/boltdb-shipper-active";
                cache_location = "/var/lib/loki/boltdb-shipper-cache";
                cache_ttl = "24h";
              };
              filesystem = {
                directory = "/var/lib/loki/chunks";
              };
            };
            limits_config = {
              reject_old_samples = true;
              reject_old_samples_max_age = "168h";
            };
            table_manager = {
              retention_deletes_enabled = false;
              retention_period = "0s";
            };
          };
        };
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
        networking.firewall.allowedTCPPorts = [ 3000 3100 ];
      };
    };
  };
}
