{ config
, pkgs
, lib
, ...
}: {
  options.nix-tun.services.traefik = {
    enable = lib.mkEnableOption "Enable the Traefik Reverse Proxy";
    enable_prometheus = lib.mkEnableOption ''
      Enable Prometheus metrics.
      The default entrypoint for this is `traefik.$\{config.networking.fqdnOrHostName\}` at port 9100.
      Basic Auth is used to authenticate to the service.
      This uses the value of `config.sops.secrets."prometheus-traefik-pw"` as hashed password for the user `traefik`.
    '';
    enable_docker = lib.mkEnableOption "Enable Docker Discovery";
    letsencryptMail = lib.mkOption {
      type = lib.types.str;
      default = null;
      description = ''
        The email address used for letsencrypt certificates
      '';
    };
    dashboardUrl = lib.mkOption {
      type = lib.types.str;
      default = null;
      description = ''
        The url to which the dashboard should be published to
      '';
    };
    entrypoints = lib.mkOption {
      type = lib.types.attrs;
      default = {
        web = {
          port = 80;
          http = {
            redirections = {
              entryPoint = {
                to = "websecure";
                scheme = "https";
              };
            };
          };
        };
        websecure = {
          port = 443;
        };
        "prometheus" = {
          port = 9100;
        };
      };
      description = ''
        The entrypoints of the traefik reverse proxy default are 80 (web) and 443 (websecure)
      '';
    };
    redirects =
      lib.mkOption { };
    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
        options = {
          router = {
            rule = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = ''
                The routing rule for this service. The rules are defined here: https://doc.traefik.io/traefik/routing/routers/
              '';
            };
            priority = lib.mkOption {
              type = lib.types.int;
              default = 0;
            };
            tls = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = ''
                  Enable tls for router, default = true;
                '';
              };
              options = lib.mkOption {
                type = lib.types.attrs;
                default = {
                  certResolver = "letsencrypt";
                };
                description = ''
                  Options for tls, default is to use the letsencrypt certResolver
                '';
              };
            };
            middlewares = lib.mkOption {
              type = lib.types.listOf (lib.types.str);
              default = [ ];
              description = ''
                The middlewares applied to the router, the middlewares are applied in order.
              '';
            };
            entryPoints = lib.mkOption {
              type = lib.types.listOf (lib.types.str);
              default = [ "websecure" ];
              description = ''
                The Entrypoint of the service, default is 443 (websecure)
              '';
            };
          };
          servers = lib.mkOption {
            type = lib.types.listOf (lib.types.str);
            default = [ ];
            description = ''
              The hosts of the service
            '';
          };
          healthcheck = {
            enable = lib.mkEnableOption ''
              Enables healthcheck of this service from traefik.
              Traefik expects a status code of 2xx or 3xx at path.
              If the healthcheck fails the service will not be reachable.
            '';
            path = lib.mkOption {
              type = lib.types.str;
              default = "/";
              description = ''
                The path for the healthcheck.
              '';
            };
            interval = lib.mkOption {
              type = lib.types.str;
              default = "10s";
              description = ''
                How often the service is HealthChecked.
              '';
            };
            timeout = lib.mkOption {
              type = lib.types.str;
              default = "3s";
              description = ''
                How long traefik waits for an response, before it deems the server unreachable.
              '';
            };
          };
        };
      }));
      default = { };
      description = ''
        A simple setup to configure http loadBalancer services and routers.
      '';
    };
  };

  config = lib.mkIf config.nix-tun.services.traefik.enable {

    networking.firewall.allowedTCPPorts = lib.attrsets.mapAttrsToList (name: value: value.port) config.nix-tun.services.traefik.entrypoints;
    users.users.traefik.extraGroups = lib.mkIf config.nix-tun.services.traefik.enable_docker [ "docker" ];
    systemd.services.traefik.environment.LD_LIBRARY_PATH = config.system.nssModules.path;
    nix-tun.utils.prometheus-exporter = lib.mkIf config.nix-tun.services.traefik.enable_prometheus { "traefik" = [ "traefik.${config.networking.fqdnOrHostName}:9100" ]; };

    sops.secrets."prometheus-traefik-pw" = lib.mkIf config.nix-tun.services.traefik.enable_prometheus { };
    sops.templates."prometheus-traefik-auth" = lib.mkIf config.nix-tun.services.traefik.enable_prometheus {
      owner = "traefik";
      content = ''
        traefik:${config.sops.placeholder.prometheus-node-exporter-pw}
      '';
    };

    services.traefik = {
      enable = true;
      dynamicConfigOptions = {
        http = {
          middlewares."prometheus-traefik-auth" = lib.mkIf config.nix-tun.services.traefik.enable_prometheus {
            basicAuth.usersFile = config.sops.templates."prometheus-traefik-auth".path;
          };
          routers = lib.mkMerge [
            (lib.attrsets.mapAttrs
              (
                name: value:
                  lib.mkMerge [
                    {
                      rule = value.router.rule;
                      priority = value.router.priority;
                      middlewares = value.router.middlewares;
                      service = name;
                      entryPoints = value.router.entryPoints;
                    }
                    (lib.mkIf value.router.tls.enable {
                      tls = value.router.tls.options;
                    })
                  ]
              )
              config.nix-tun.services.traefik.services)
            (lib.mkIf config.nix-tun.services.traefik.enable_prometheus {
              prometheus-traefik = {
                rule = "Host(`traefik.${config.networking.fqdnOrHostName}`)";
                entryPoints = "prometheus";
                service = "prometheus@internal";
                middlewares = [ "prometheus-traefik-auth" ];
              };
            })
          ];
          services =
            lib.attrsets.mapAttrs
              (name: value: {
                loadBalancer = lib.mkMerge [{
                  servers = builtins.map (value: { url = value; }) value.servers;
                }
                  (lib.mkIf value.healthcheck.enable {
                    healthCheck = {
                      path = value.healthcheck.path;
                      interval = value.healthcheck.interval;
                      timeout = value.healthcheck.timeout;
                    };
                  })];
              })
              config.nix-tun.services.traefik.services;
        };
      };

      staticConfigOptions = lib.mkMerge [
        {

          providers.docker = lib.mkIf config.nix-tun.services.traefik.enable_docker {
            exposedByDefault = false;
            watch = true;
          };
          certificatesResolvers = {
            letsencrypt = {
              acme = {
                email = config.nix-tun.services.traefik.letsencryptMail;
                storage = "/var/lib/traefik/acme.json";
                tlsChallenge = { };
              };
            };
          };

          entryPoints =
            (lib.attrsets.mapAttrs
              (name: value:
                lib.attrsets.mergeAttrsList [
                  {
                    address = ":${toString value.port}";
                  }
                  (lib.attrsets.filterAttrs (n: v: n != "port") value)
                ])
              config.nix-tun.services.traefik.entrypoints);

          api = {
            dashboard = true;
          };
        }
        (lib.mkIf config.nix-tun.services.traefik.enable_prometheus {
          metrics = {
            prometheus = {
              addEntryPointsLabels = true;
              addRoutersLabels = true;
              addServicesLabels = true;
              manualRouting = true;
            };
          };
        })
      ];
    };
  };
}
