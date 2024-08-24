{
  lib,
  config,
  pkgs,
  ...
}: {
  # Utils to make the configuration of NixOs Containers more streamlined, in Context of the entire flake.
  options = {
    nix-tun.utils.containers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({...}: {
        options = {
          volumes = lib.mkOption {
            description = ''
              Directories to autmatically create in persistent storage, and bind mount inside the container.
	      Directories will be created in /persist/containers/<container-name>/<directory>.
	      Where /persist/containers/<container-name> is a btrfs Subvolume that will be snapshoted daily.
            '';
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
            };
            mode = lib.mkOption {
              type = lib.types.str;
              description = ''
                The mode of the directory
              '';
              default = "0700";
            };
          };
        };
      }));
      default = {};
      description = ''
        Utils to make the configuration of NixOs Containers more streamlined, in Context of the entire flake.
      '';
    };
  };

  config = {
    nix-tun.storage.persist.subvolumes =
      lib.attrsets.mapAttrs' (name: value: {
        name = "containers/${name}";
        value.directories =
          lib.attrsets.mapAttrs (_: value: {
            owner = builtins.toString config.containers."${name}".config.users.users.${value.owner}.uid;
            group = builtins.toString config.containers."${name}".config.users.group.${value.group}.gid;
            mode = value.mode;
          })
          value.volumes;
      })
      config.nix-tun.utils.containers;

    containers =
      lib.attrsets.mapAttrs (name: value: {
        bindMounts =
          lib.attrsets.mapAttrs (n: value: {
            hostPath = "${config.nix-tun.storage.persist.path}/containers/${name}/${n}";
            mountPoint = n;
            isReadOnly = false;
          })
          value.volumes;
      })
      config.nix-tun.utils.containers;
  };
}
