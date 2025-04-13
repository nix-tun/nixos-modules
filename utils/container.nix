{ lib
, config
, pkgs
, ...
}@host: {
  # Utils to make the configuration of NixOs Containers more streamlined, in Context of the entire flake.
  options = {
    nix-tun.utils.containers = lib.mkOption {
      type = lib.types.attrsOf
        (lib.types.submodule
          ({ options, name, ... }: {
            options = {
              config = lib.mkOption
                {
                  type = lib.types.deferredModuleWith {
                    staticModules = [
                      ({ ... }: {
                        config = {
                          networking.useHostResolvConf = lib.mkForce false;
                          systemd.network.enable = true;
                          systemd.network.networks."10-eth0" = {
                            matchConfig.Name = "eth0";
                            networkConfig.DHCP = "ipv4";
                            linkConfig.RequiredForOnline = "routable";
                          };
                        };
                      })
                    ];
                  };
                  description = ''
                    A Nixos Conifugration for the Container.
                  '';
                };
              domains = lib.mkOption {
                type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
                  options = {
                    port = lib.mkOption {
                      type = lib.types.int;
                    };
                    entryPoints = lib.mkOption {
                      type = lib.types.listOf (lib.types.str);
                      default = [ "websecure" ];
                      description = ''
                        The external entrypoint name of the reverse proxy.
                        If traefik is used this corresponds to the traefik entrypoint.
                      '';
                    };
                    domain = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                    };
                  };
                }));
                default = { };
                description = ''
                  A mapping of domains to port address.
                  This will expose the service at the internal `port`.
                '';
              };
              volumes = lib.mkOption {
                default = { };
                description = ''
                  Directories to autmatically create in persistent storage, and bind mount inside the container.
                  Directories will be created in /persist/containers/<container-name>/<directory>.
                  Where /persist/containers/<container-name> is a btrfs Subvolume that will be snapshoted daily.
                '';
                type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
                  options = {
                    owner = lib.mkOption {
                      type = lib.types.str;
                      description = ''
                        The username of the owner of the Directory (of an user declared inside the container)
                      '';
                      default = "root";
                    };
                    group = lib.mkOption {
                      type = lib.types.str;
                      description = ''
                        The name of the group of the Directory. (of a group inside the container)
                      '';
                      default = "root";
                    };
                    mode = lib.mkOption {
                      type = lib.types.str;
                      description = ''
                        The mode of the directory
                      '';
                      default = "0700";
                    };
                  };
                }));
              };
            };
          }));
      default = { };
      description = ''
        Utils to make the configuration of NixOs Containers more streamlined, in Context of the entire flake.
      '';
    };
  };

  config =
    {
      assertions = [{
        assertion = (config.nix-tun.utils.containers != { }) -> (config.nix-tun.storage.persist.enable);
        message = ''
          Nix-Tun containers require `nix-tun.storage.persist.enable` to be enabled.
          As that module is used to the store the container data.
        '';
      }];

      # The containers are assigned an ip address via DHCP.
      # Containers should be reached via their hostnames
      systemd.network.networks."80-container-ve" = {
        matchConfig.Name = "ve-*";
        networkConfig = {
          Address = "192.168.100.0/24";
          DHCPServer = true;
          IPMasquerade = "ipv4";
          IPv4Forwarding = true;
        };
      };

      nix-tun.services.traefik.services =
        (lib.mkMerge
          (lib.attrsets.mapAttrsToList
            (name: value: (lib.attrsets.mapAttrs'
              (domain-name: domain-value: {
                name = "${name}-${builtins.replaceStrings ["." "/"] ["-" "-"] domain-name}";
                value = {
                  router = {
                    rule = "Host(`${domain-value.domain}`)";
                    entryPoints = domain-value.entryPoints;
                  };
                  servers = [ "http://${name}.containers:${builtins.toString domain-value.port}" ];
                };
              })
              value.domains))
            config.nix-tun.utils.containers));

      nix-tun.storage.persist.subvolumes =
        lib.attrsets.mapAttrs'
          (name: value: {
            name = "containers/${name}";
            value.directories =
              lib.attrsets.mapAttrs
                (_: value: {
                  owner = builtins.toString config.containers."${name}".config.users.users.${value.owner}.uid;
                  group = builtins.toString config.containers."${name}".config.users.groups.${value.group}.gid;
                  mode = value.mode;
                })
                value.volumes;
          })
          config.nix-tun.utils.containers;

      containers =
        lib.attrsets.mapAttrs
          (name: value: {
            ephemeral = true;
            autoStart = true;
            privateNetwork = true;
            timeoutStartSec = "5min";
            bindMounts =
              lib.attrsets.mapAttrs
                (n: value: {
                  hostPath = "${config.nix-tun.storage.persist.path}/containers/${name}/${n}";
                  mountPoint = n;
                  isReadOnly = false;
                })
                value.volumes;
            config = value.config;
          })
          config.nix-tun.utils.containers;
    };
}
