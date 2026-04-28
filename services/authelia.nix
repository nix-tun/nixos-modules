{ lib, config, pkgs, ... }: {
  options.nix-tun.services.authelia = {
    enable = lib.mkEnableOption "Enable Authelia Authentication Service";
    domain = lib.mkOption {
      type = lib.types.str;
    };
    clients = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        freeformType = (pkgs.formats.yaml { }).type;
        options = {
          client_id = lib.mkOption {
            type = lib.types.str;
            default = name;
          };
          client_secret = lib.mkOption {
            type = lib.types.str;
            default = "{{- fileContent \"/secret/client-secret-${name}\" }}";
          };
        };
      }));
    };
  };
  config = lib.mkIf config.nix-tun.services.authelia.enable {
    nix-tun.utils.containers.authelia = {
      domains = {
        "authelia" = {
          domain = config.nix-tun.services.authelia.domain;
          port = 9091;
        };
      };
      volumes = {
        "/config" = { owner = "authelia-authelia"; group = "authelia-authelia"; };
      };
      secrets = lib.mkMerge [
        (lib.attrsets.mapAttrs'
          (name: _: {
            name = "client-secret-${name}";
            value = { owner = "authelia-authelia"; };
          })
          config.nix-tun.services.authelia.clients)
        {
          "storage-encryption-key" = {
            owner = "authelia-authelia";
          };
          "oidc-issuer-private-key" =
            {
              owner = "authelia-authelia";
            };
          "oidc-hmac-secret" = {
            owner = "authelia-authelia";
          };
          "jwt-secret" = {
            owner = "authelia-authelia";
          };
        }
      ];
      config = { ... }: {
        systemd.services.authelia-authelia.serviceConfig.ReadWritePaths = "/config";
        users.users.authelia-authelia.uid = 999;
        services.authelia.instances.authelia = {
          enable = true;
          settings = {
            server.address = "tcp://:9091/";
            webauthn = {
              enable_passkey_login = true;
            };
            authentication_backend = {
              file.path = "/config/users_database.yml";
            };
            session.cookies = [{
              domain = config.nix-tun.services.authelia.domain;
              authelia_url = "https://${config.nix-tun.services.authelia.domain}";
            }];
            storage = {
              local.path = "/config/db.sqlite3";
            };
            access_control.default_policy = "one_factor";

            notifier.filesystem.filename = "/config/notification.txt";
            identity_providers.oidc = {
              clients = lib.attrsets.mapAttrsToList (name: value: value) config.nix-tun.services.authelia.clients;
            };
          };
          secrets = {
            storageEncryptionKeyFile = "/secret/storage-encryption-key";
            oidcIssuerPrivateKeyFile = "/secret/oidc-issuer-private-key";
            oidcHmacSecretFile = "/secret/oidc-hmac-secret";
            jwtSecretFile = "/secret/jwt-secret";
          };
        };
      };
    };
  };
}
