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
                  type = lib.mkOptionType {
                    name = "Toplevel NixOs config";
                    merge = loc: defs: (import "${pkgs.path}/nixos/lib/eval-config.nix" {
                      modules = ([
                        ({ ... }: {
                          nixpkgs.localSystem = host.pkgs.stdenv.hostPlatform;
                          networking.useHostResolvConf = lib.mkForce false;
                          services.resolved.enable = true;
                        })
                      ] ++ (map (x: x.value) defs));
                      prefix = [ "nix-tun" "containers" name ];

                      system = null;
                    }).config;
                  };

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
