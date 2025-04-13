{ lib
, config
, pkgs
, inputs
, ...
}: {
  options.nix-tun.services.containers.nextcloud =
    let
      t = lib.types;
    in
    {
      enable = lib.mkEnableOption "setup nextcloud";
      hostname = lib.mkOption {
        type = t.str;
      };
      secretsFile = lib.mkOption {
        type = t.path;
        description = "path to the sops secret file for the adminPass";
      };
      extraApps = lib.mkOption {
        description = "nextcloud apps to install";
        type = t.listOf t.str;
        default = [ ];
      };
      extraTrustedProxies = lib.mkOption {
        type = t.listOf t.str;
        default = [ ];
      };
    };

  config =
    let
      opts = config.nix-tun.services.containers.nextcloud;
    in
    lib.mkIf opts.enable {
      sops.secrets.nextcloud_pass = {
        mode = "444";
      };
      sops.secrets.nextcloud_dbpass = {
        mode = "444";
      };

      containers.nextcloud = {
        bindMounts = {
          "secret" = {
            hostPath = config.sops.secrets.nextcloud_pass.path;
            mountPoint = config.sops.secrets.nextcloud_pass.path;
          };
        };
      };

      nix-tun.utils.containers.nextcloud = {
        domains.nextcloud = {
          domain = "${opts.hostname}";
          port = 80;
        };

        volumes = {
          "/var/lib/mysql" = {
            owner = "mysql";
          };
          "/var/lib/nextcloud" = {
            owner = "nextcloud";
            group = "nextcloud";
            mode = "0755";
          };
        };
        config = { ... }: {
          environment.systemPackages = [
            pkgs.samba
          ];
          services.nextcloud = {
            enable = true;
            package = pkgs.nextcloud31;
            https = true;
            hostName = opts.hostname;
            phpExtraExtensions = all: [ all.pdlib all.smbclient ];
            notify_push.enable = true;

            database.createLocally = true;
            settings.trusted_proxies = [ "192.168.100.10" ] ++ opts.extraTrustedProxies;
            settings.trusted_domains = [ "192.168.100.11" "192.168.100.10" opts.hostname ];
            config = {
              adminpassFile = "${config.sops.secrets.nextcloud_pass.path}";
              dbtype = "mysql";
            };

            phpOptions = {
              "opcache.jit" = "1255";
              "opcache.revalidate_freq" = "60";
              "opcache.interned_strings_buffer" = "16";
              "opcache.jit_buffer_size" = "128M";
              "apc.shm_size" = "512M";
            };

            extraApps = lib.attrsets.getAttrs opts.extraApps config.services.nextcloud.package.packages.apps;
            extraAppsEnable = true;

            configureRedis = true;
            caching.apcu = true;
            poolSettings = {
              pm = "dynamic";
              "pm.max_children" = "201";
              "pm.max_requests" = "500";
              "pm.max_spare_servers" = "150";
              "pm.min_spare_servers" = "50";
              "pm.start_servers" = "50";
            };
          };

          networking = {
            firewall = {
              enable = true;
              allowedTCPPorts = [ 80 ];
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
