{ lib
, config
, inputs
, pkgs
, ...
}: {
  options.nix-tun.services.containers.onlyoffice = {
    enable = lib.mkEnableOption "setup authentik";
    hostname = lib.mkOption {
      type = lib.types.str;
    };
    jwtSecretFile = lib.mkOption {
      type = lib.types.path;
      description = "path to the sops secret file for jwt secret website Server";
    };
  };

  config =
    let
      opts = config.nix-tun.services.containers.onlyoffice;
    in
    lib.mkIf opts.enable {
      sops.secrets.onlyoffice_jwt = {
        sopsFile = opts.jwtSecretFile;
        format = "binary";
        mode = "444";
      };

      nix-tun.services.traefik.services."onlyoffice" = {
        router.rule = "Host(`${opts.hostname}`)";
        servers = [ "http://${config.containers.onlyoffice.config.networking.hostName}:8000" ];
      };

      containers.onlyoffice = {
        ephemeral = true;
        autoStart = true;
        privateNetwork = true;
        hostAddress = "192.168.131.10";
        localAddress = "192.168.131.11";

        bindMounts = {
          "secret" = {
            hostPath = config.sops.secrets.onlyoffice_jwt.path;
            mountPoint = config.sops.secrets.onlyoffice_jwt.path;
          };
          "resolv" = {
            hostPath = "/etc/resolv.conf";
            mountPoint = "/etc/resolv.conf";
          };
        };

        config = { ... }: {
          imports = [
            inputs.authentik-nix.nixosModules.default
          ];

          nixpkgs.config.allowUnfree = true;

          networking.hostName = "onlyoffice";

          services.onlyoffice = {
            enable = true;
            hostname = opts.hostname;
            jwtSecretFile = config.sops.secrets.onlyoffice_jwt.path;
          };
          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [ 8000 ];
            };
            # Use systemd-resolved inside the container
            # Workaround for bug https://github.com/NixOS/nixpkgs/issues/162686
            useHostResolvConf = lib.mkForce false;
          };

          services.resolved.enable = true;

          system.stateVersion = "23.11";
        };

      };
    };
}
