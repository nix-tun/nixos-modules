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
                          system.stateVersion = lib.mkDefault config.system.stateVersion;
                          networking.useHostResolvConf = lib.mkForce false;
                          networking.firewall.allowedUDPPorts = [ 5355 ];
                          networking.firewall.allowedTCPPorts = [ 5355 ];
                          services.resolved = {
                            enable = true;
                          };
                          systemd.network.enable = true;
                          systemd.settings.Manager = {
                            DefaultLimitNOFILE = "8192:524288";
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
              secrets = lib.mkOption {
                default = [ ];
                description = ''
                  Secrets to which the container needs access to. This will autmatically setup the secrets on the host and bind-mount them as read-only inside the container.
                  The mode is always set to 0500, and owned by root (inside and outside the container).
                  A secret with the name "x" will create a secret with the name "container-x" on the host.
                  And mounted inside the container as "/secret/x".
                '';
                type = lib.types.listOf lib.types.str;
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
      assertions = [
        {
          assertion = (config.nix-tun.utils.containers != { }) -> (config.nix-tun.storage.persist.enable);
          message = ''
            Nix-Tun containers require `nix-tun.storage.persist.enable` to be enabled.
            As that module is used to the store the container data.
          '';
        }
        {
          assertion = (config.nix-tun.utils.containers != { }) -> (config.systemd.network.enable);
          message = ''
            Nix-Tun containers require `systemd.network.enable` to be enabled.
            As networkd is used to setup container networking.
          '';
        }
        {
          assertion = (config.nix-tun.utils.containers != { }) -> (config.services.resolved.enable);
          message = ''
            Nix-Tun containers require `services.resolved.enable` to be enabled.
            As resolved is used to resolve container hostnames. With the help of LLMNR.
          '';
        }
      ];

      networking.firewall.interfaces."vz-container".allowedUDPPorts = [ 53 67 5355 ];
      networking.firewall.interfaces."vz-container".allowedTCPPorts = [ 53 67 5355 ];

      sops.secrets = (lib.mkMerge
        (lib.attrsets.mapAttrsToList
          (name: value: (lib.lists.map (secret-name: { "${name}-${secret-name}" = { mode = "0500"; }; }) value.secrets)) config.nix-tun.utils.container));

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
                  servers = [ "http://${name}:${builtins.toString domain-value.port}" ];
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
                  mode = "-";
                  owner = "-";
                  group = "-";
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
            # This ensures each container uses seperate uids
            privateUsers = "pick";
            extraFlags = lib.mkMerge [
              [
                "--network-zone=container"
                "--resolv-conf=bind-stub"
              ]
              # This maps the owner of the directory inside the container to the owner of the directory outside the container
              (lib.attrsets.mapAttrsToList (n: v: "--bind=${config.nix-tun.storage.persist.path}/containers/${name}/${n}:${n}:idmap") value.volumes)
              (lib.lists.map (secret: "--bind-ro=${config.sops.secrets."${name}-${secret}".path}:${config.sops.secrets."${name}-${secret}".path}:idmap") value.secrets)
            ];
            config = lib.mkMerge
              [
                ({ ... }: {
                  config = {
                    # Set the correct owner, group and mode for the volumes 
                    systemd.tmpfiles.rules = (lib.attrsets.mapAttrsToList (n: v: "d ${v.mode} ${v.owner} ${v.group} -") value.volumes);
                    networking.firewall.allowedTCPPorts = (lib.attrsets.mapAttrsToList (domain-name: domain-value: domain-value.port) value.domains);
                  };
                })
                value.config
              ];
          })
          config.nix-tun.utils.containers;
    };
}
