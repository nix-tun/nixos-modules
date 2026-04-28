{ pkgs, config, lib, inputs, ... }: {
  options.nix-tun.services.headscale = {
    enable = lib.mkEnableOption "Enable Headscale Server";
    domain = lib.mkOption {
      type = lib.types.str;
      description = ''
        The domain from which headscale should be reached.
        The base domain for magic dns will be tailnet.$${config.nix-tun.services.headscale.domain}.
      '';
    };
    headplane-openid = {
      client = lib.mkOption {
        type = lib.types.str;
      };
    };
    openid = {
      client = lib.mkOption {
        type = lib.types.str;
      };
    };
  };

  config =
    let
      cfg = config.nix-tun.services.headscale;
      authelia = config.nix-tun.services.authelia;
    in
    lib.mkIf cfg.enable {
      nix-tun.services.authelia.clients.headscale-headplane = {
        redirect_uris = [ "https://${cfg.domain}/admin/oidc/callback" ];
      };

      nix-tun.services.authelia.clients.headscale = {
        redirect_uris = [ "https://${cfg.domain}/oidc/callback" ];
      };

      nix-tun.utils.containers.headscale = {
        domains = {
          headscale = {
            domain = config.nix-tun.services.headscale.domain;
            port = 8080;
          };
          headplane = {
            domain = config.nix-tun.services.headscale.domain;
            path = "/admin";
            port = 3000;
          };
        };
        volumes = {
          "/var/lib/headscale" = { owner = "headscale"; group = "headscale"; };
          "/var/lib/headplane" = { owner = "headscale"; group = "headscale"; };
        };
        secrets = {
          "headplane-cookie-secret" = { owner = "headscale"; group = "headscale"; };
          "headplane-oidc-client-secret" = { owner = "headscale"; group = "headscale"; };
          "oidc-client-secret" = { owner = "headscale"; group = "headscale"; };
          "headplane-preauth-key" = { owner = "headscale"; group = "headscale"; };
          "headplane-headscale-api" = { owner = "headscale"; group = "headscale"; };
        };
        config = { config, ... }: {
          imports = [ inputs.headplane.nixosModules.headplane ];
          nixpkgs.overlays = [ inputs.headplane.overlays.default ];

          users.users.headscale.uid = 994;
          users.groups.headscale.gid = 994;

          services.headscale = {
            enable = true;
            address = "0.0.0.0";
            port = 8080;
            settings = {
              policy.mode = "database";
              #policy.path = "";
              server_url = "https://${cfg.domain}";
              #tls_key_path = "";
              #tls_cert_path = "";
              oidc = {
                client_id = "headscale";
                client_secret_path = "/secret/oidc-client-secret";
                issuer = "https://${authelia.domain}";
                pkce.enabled = true;
              };
              dns = {
                magic_dns = true;
                override_local_dns = true;
                nameservers.global = [
                  "9.9.9.9"
                  "149.112.112.112"
                  "2620:fe::fe"
                  "2620:fe::9"
                ];
                base_domain = "tailnet.${cfg.domain}";
                extra_records = [ ];
              };
            };
          };
          services.headplane = {
            enable = true;
            settings = {
              oidc = {
                client_id = "headscale-headplane";
                disable_api_key_login = true;
                headscale_api_key_path = "/secret/headplane-headscale-api";
                client_secret_path = "/secret/headplane-oidc-client-secret";
                issuer = "https://${authelia.domain}";
                token_endpoint_auth_method = "client_secret_basic";
              };
              headscale = {
                config_path = config.services.headscale.configFile;
                url = "https://${cfg.domain}";
              };
              integration = {
                proc.enabled = true;
                agent.enabled = true;
                agent.pre_authkey_path = "/secret/headplane-preauth-key";
              };
              server = {
                cookie_secure = true;
                cookie_domain = cfg.domain;
                base_url = "https://${cfg.domain}";
                host = "0.0.0.0";
                cookie_secret_path = "/secret/headplane-cookie-secret";
              };
            };
          };
        };
      };
    };
}
