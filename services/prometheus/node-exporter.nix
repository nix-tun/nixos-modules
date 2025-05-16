{ pkgs, config, lib, ... }: {
  options = {
    nix-tun.services.prometheus.node-exporter = lib.mkEnableOption ''
      Whether to monitor this system, with Prometheus Node Exporter Endpoints.
      The default entrypoint for this is `node-exporter.$\{config.networking.fqdnOrHostName\}` at port 9100.
      Basic Auth is used to authenticate to the service.
      This uses the value of `config.sops.secrets."prometheus-node-exporter-pw"` as hashed password for the user `node-exporter`.
    '';
  };

  config = lib.mkIf config.nix-tun.services.prometheus.node-exporter {
    nix-tun.utils.prometheus-exporter.node-exporter = [
      "node-exporter.${config.networking.fqdnOrHostName}:9100"
    ];

    nix-tun.services.traefik = {
      services.node-exporter = {
        servers = [ "http://localhost:9100" ];
        router = {
          middlewares = [
            "node-exporter-auth"
          ];
          entryPoints = [ "prometheus" ];
          rule = "Host(`node-exporter.${config.networking.fqdnOrHostName}`)";
          tls.enable = false;
        };
      };
    };

    sops.secrets."prometheus-node-exporter-pw" = { };
    sops.templates."node-exporter-auth" = {
      owner = "traefik";
      content = ''
        node-exporter:${config.sops.placeholder.prometheus-node-exporter-pw}
      '';
    };

    services.traefik.dynamicConfigOptions.http = {
      middlewares."node-exporter-auth".basicAuth = {
        usersFile = config.sops.templates."node-exporter-auth".path;
      };
    };

    services.prometheus.exporters.node = {
      openFirewall = true;
      enable = true;
      enabledCollectors = [
        "systemd"
        "network_route"
      ];
    };
  };
} 
