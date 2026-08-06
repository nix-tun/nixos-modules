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
  };

  config =
    let
      opts = config.nix-tun.services.containers.onlyoffice;
    in
    lib.mkIf opts.enable {
      nix-tun.utils.containers.onlyoffice = {
        secrets.jwt = {
          mode = "444";
        };
        domains.onlyoffice = {
          port = 8000;
          domain = config.containers.onlyoffice.config.networking.hostName;
          healthcheck = "/";
        };

        config = { ... }: {
          nixpkgs.config.allowUnfree = true;
          services.onlyoffice = {
            enable = true;
            hostname = "https://${opts.hostname}";
            jwtSecretFile = "/secret/jwt";
          };
        };
      };
    };
}
