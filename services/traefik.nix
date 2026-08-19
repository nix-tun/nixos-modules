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
  };

  config = lib.mkIf config.nix-tun.services.traefik.enable {
    contracts.reverseProxy.defaultResponder = "traefik";
    contracts.reverseProxy.responder.traefik.response = lib.attrsets.mapAttrs
      (name: value: {
        externalUrl = "${value.protocol}://${value.domain}";
      })
      config.contracts.reverseProxy.responder.traefik.request;

    environment.etc."alloy/traefik-metrics.alloy" = lib.mkIf (config.nix-tun.alloy.prometheus-host != null && config.nix-tun.services.traefik.enable_prometheus) {
      text = ''
        prometheus.scrape "traefik" {
          scrape_interval = "15s"
          targets    = [
            { "__address__" = "127.0.0.1:9100", "instance" = "constants.hostname"},
          ]
          job_name = "traefik"
          forward_to = [prometheus.remote_write.default.receiver]
        }
      '';
    };

    networking.firewall.allowedTCPPorts = lib.attrsets.mapAttrsToList (name: value: value.port)
      (lib.attrsets.filterAttrs (name: value: value.protocol == "tcp" || value.protocol == "http" || value.protocol == "https") config.contracts.reverseProxy.responder.traefik.request);

    networking.firewall.allowedUDPPorts = lib.attrsets.mapAttrsToList (name: value: value.port)
      (lib.attrsets.filterAttrs (name: value: value.protocol == "udp") config.contracts.reverseProxy.responder.traefik.request);

    users.users.traefik.extraGroups = lib.mkIf config.nix-tun.services.traefik.enable_docker [ "docker" ];
    systemd.services.traefik.environment.LD_LIBRARY_PATH = config.system.nssModules.path;
    systemd.services.traefik.serviceConfig.LimitNPROC = lib.mkForce 8192;

    services.traefik = {
      enable = true;
      dynamicConfigOptions = {
        http = {
          middlewares = lib.mkMerge [
            (lib.mapAttrs'
              (name: value: {
                name = "${name}-basic-auth";
                value = {
                  userFile = "";
                };
              })
              (lib.filterAttrs (n: v: v.authType == "basicAuth" && (v.protocol == "http" || v.protocol == "https")) config.contracts.reverseProxy.responder.traefik.request))
          ];
          routers = lib.mkMerge [
            (lib.attrsets.mapAttrs
              (name: value:
                lib.mkMerge [
                  {
                    rule = "Host(`${value.domain}`) && PathPrefix(`${value.path}`)";
                    service = name;
                    entryPoints = "tcp-${toString value.port}";
                  }
                  (lib.mkIf (value.protocol == "https") {
                    tls.certResolver = "letsencrypt";
                  })
                  (lib.mkIf (value.authType == "basicAuth") {
                    middlewares = [ "${name}-basic-auth" ];
                  })
                ])
              (lib.attrsets.filterAttrs
                (n: v: (v.protocol == "http" || v.protocol == "https"))
                config.contracts.reverseProxy.responder.traefik.request))
            (lib.mkIf config.nix-tun.services.traefik.enable_prometheus {
              prometheus-traefik = {
                rule = "ClientIP(`127.0.0.1`)";
                entryPoints = "prometheus";
                service = "prometheus@internal";
              };
            })
          ];

          services =
            lib.attrsets.mapAttrs
              (name: value: {
                loadBalancer.servers = [{
                  url = value.internalUrl;
                }];
              })
              (lib.attrsets.filterAttrs
                (n: v: (v.protocol == "http" || v.protocol == "https"))
                config.contracts.reverseProxy.responder.traefik.request);
        };
        tcp = lib.mkIf
          ({ } != (lib.attrsets.filterAttrs
            (n: v: v.protocol == "tcp")
            config.contracts.reverseProxy.responder.traefik.request))
          {
            routers = (lib.attrsets.mapAttrs
              (
                name: value:
                  lib.mkMerge [
                    {
                      service = name;
                      entryPoints = "tcp-${value.port}";
                    }
                    (lib.mkIf (value.domain != null) {
                      rule = "HostSNI(`${value.domain}`)";
                    })
                    (lib.mkIf (value.domain != null) {
                      tls = value.domain;
                    })
                  ]
              )
              (lib.attrsets.filterAttrs
                (n: v: v.protocol == "tcp")
                config.contracts.reverseProxy.responder.traefik.request));

            services = lib.attrsets.mapAttrs
              (name: value: {
                loadBalancer.servers = [{
                  url = value.internalUrl;
                }];
              })
              (lib.attrsets.filterAttrs
                (n: v: v.protocol == "tcp")
                config.contracts.reverseProxy.responder.traefik.request);

          };
        udp = lib.mkIf
          ({ } != (lib.attrsets.filterAttrs
            (n: v: v.protocol == "udp")
            config.contracts.reverseProxy.responder.traefik.request))
          {
            routers = (lib.attrsets.mapAttrs
              (name: value: {
                service = name;
                entryPoints = "udp-${toString value.port}";
              })
              (lib.attrsets.filterAttrs
                (n: v: v.protocol == "udp")
                config.contracts.reverseProxy.responder.traefik.request));

            services = lib.attrsets.mapAttrs
              (name: value: {
                loadBalancer.servers = [{
                  url = value.internalUrl;
                }];
              })
              (lib.attrsets.filterAttrs
                (n: v: v.protocol == "udp")
                config.contracts.reverseProxy.responder.traefik.request);

          };
      };

      staticConfigOptions = lib.mkMerge
        [
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

            entryPoints = lib.mapAttrs'
              (name: value: {
                name = "${if value.protocol == "udp" then "udp" else "tcp"}-${toString value.port}";
                value = {
                  address = ":${toString value.port}/${if value.protocol == "udp" then "udp" else "tcp"}";
                };
              })
              config.contracts.reverseProxy.responder.traefik.request;


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
