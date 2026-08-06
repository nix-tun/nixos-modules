{ lib, config, pkgs, ... }: {
  options.nix-tun.services.authelia = {
    enable = lib.mkEnableOption "Enable Authelia Authentication Service";
    domain = lib.mkOption {
      type = lib.types.str;
    };
    secretResponder = lib.mkOption {
      default = config.contracts.secret.defaultResponder;
      type = lib.types.str;
    };
  };
  config = lib.mkIf (config.nix-tun.services.authelia.enable)
    (
      let url = config.contracts.reverseProxy.responder."${config.contracts.reverseProxy.defaultResponder}".response.container-authelia-authelia.externalUrl;
      in {
        #services.traefik.dynamicConfigOptions.http.middlewares.authelia-auth.forwardAuth.address = "https://${config.nix-tun.services.authelia.domain}";

        contracts.oauth.defaultResponder = "authelia";
        contracts.oauth.responder.authelia.response = lib.mapAttrs
          (name: value: {
            issuer = url;
            clientSecret = "client-secret-${value.clientId}";
            clientSecretResponder = config.nix-tun.services.authelia.secretResponder;
            authUrl = "${url}/api/oidc/authorization";
            userInfoUrl = "${url}/api/oidc/userinfo";
            tokenUrl = "${url}/api/oidc/token";
          })
          config.contracts.oauth.responder.authelia.request;
        contracts.secret.responder."${config.nix-tun.services.authelia.secretResponder}".request = lib.mapAttrs'
          (name: value: {
            name = "oauth-client-secret-${value.clientId}";
            value = {
              owner = value.clientSecretOwner;
              group = value.clientSecretGroup;
              mode = "440";
              key = "authelia-client-secret-${value.clientId}";
            };
          })
          config.contracts.oauth.responder.authelia.request;

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
              (_: value: {
                name = "client-secret-${value.clientId}";
                value = { owner = "authelia-authelia"; };
              })
              config.contracts.oauth.responder.authelia.request)
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
                  experimental_enable_passkey_uv_two_factors = true;
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
                  clients = lib.attrsets.mapAttrsToList
                    (name: value: {
                      client_id = value.clientId;
                      client_secret = "{{- fileContent \"/secret/client-secret-${value.clientId}\" }}";
                      redirect_uris = value.redirectUris;
                    })
                    config.contracts.oauth.responder.authelia.request;
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
      }
    );
}
