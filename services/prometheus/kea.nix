{ pkgs, config, lib, ... }: {
  options = {
    nix-tun.services.prometheus.kea-exporter = lib.mkEnableOption ''
      Whether to monitor this system, with Kea Exporter Endpoints.
      The default entrypoint for this is `kea-exporter.$\{config.networking.fqdnOrHostName\}` at port 9100.
      Basic Auth is used to authenticate to the service.
      This uses the value of `config.sops.secrets."prometheus-kea-exporter-pw"` as hashed password for the user `kea-exporter`.
    '';
  };

  config = lib.mkIf config.nix-tun.services.prometheus.node-exporter {
    nix-tun.utils.prometheus-exporter.kea = [
      "kea-exporter.${config.networking.fqdnOrHostName}:9100"
    ];

    nix-tun.services.traefik = {
      services.prometheus-kea = {
        servers = [ "http://localhost:9547" ];
        router = {
          middlewares = [
            "kea-exporter-auth"
          ];
          entryPoints = [ "prometheus" ];
          rule = "Host(`kea-exporter.${config.networking.fqdnOrHostName}`)";
          tls.enable = false;
        };
      };
    };

    sops.secrets."prometheus-kea-exporter-pw" = { };
    sops.templates."kea-exporter-auth" = {
      owner = "traefik";
      content = ''
        kea-exporter:${config.sops.placeholder.prometheus-node-exporter-pw}
      '';
    };

    services.traefik.dynamicConfigOptions.http = {
      middlewares."kea-exporter-auth".basicAuth = {
        usersFile = config.sops.templates."kea-exporter-auth".path;
      };
    };

    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
  };
} 
