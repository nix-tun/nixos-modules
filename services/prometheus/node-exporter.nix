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
        servers = [ "http://node-exporter:9100" ];
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

    containers.node-exporter = {
      autoStart = true;
      timeoutStartSec = "5min";
      privateNetwork = true;
      bindMounts = {
        "/host" = {
          hostPath = "/";
          isReadOnly = true;
        };
      };
    };


    nix-tun.utils.containers.node-exporter = {
      config = {
        systemd.services.prometheus-node-exporter.serviceConfig.BindPaths = "/host/run/dbus:/run/dbus";
        services.prometheus.exporters.node = {
          openFirewall = true;
          enable = true;
          enabledCollectors = [
            "systemd"
            "network_route"
          ];
          extraFlags = [
            "--path.rootfs=/host/"
            "--path.sysfs=/host/sys"
            "--path.procfs=/host/proc"
            "--path.udev.data=/host/run/udev/data"
          ];
        };
      };
    };
  };
} 
