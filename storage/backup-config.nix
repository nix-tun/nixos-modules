{
  config,
  pkgs,
  lib,
  ...
}: let
  server = [
    {
      server = "samba-fs.ad.astahhu.de";
      btrfs_base = "/share";
      subvolumes = [
        "."
        "home"
        "intern/IT-Referat"
        "intern/Vorstand"
        "intern/Kulturreferat"
        "intern/NaMo"
        "intern/Politische Bildung"
        "intern/AntiFaRaDis"
        "intern/Finanzreferat"
        "intern/Sozialreferat"
        "intern/Presse Oeffentlichkeitsarbeit"
        "intern/autonom/Fachschaftenreferat"
        "intern/autonom/LesBi"
        "intern/autonom/BiSchwu"
        "intern/autonom/Internationales"
        "intern/autonom/Barrierefreiheit"
        "intern/autonom/Tinby"
        "public"
        "profile"
        "software"
      ];
    }
  ];
in {
  options.nix-tun.storage.backup = {
    enable = lib.mkEnableOption "Enable Backup System";
    nixosConfigs = lib.mkOption {
      type = lib.types.unspecified;
      default = {};
      description = ''
	The list of nixos configurations from the systems to bakups. Evaluates the nix-tun.storage.persist.profile for backups
      '';
      server = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({ ... } : {
	  options = {
	    host = {
	      type = lib.types.str;
	      default = null;
	      description = ''
	        The hostName or ip address of the server, if null uses the name
	      '';
	    };
	    btrfs_base = lib.mkOption {
	      type = lib.types.str;
	      default = "/";
	      description = ''
	        The base btrfs mount point on the server.
	      '';
	    };
	    subvolumes = lib.mkOption {
	      type = lib.types.listOf lib.types.str;
	      default = [];
	      description = ''
	        The subvolumes on server to backup
	      '';
	    };
	  };
	}));
      };
    };
  };

  config = lib.mkIf config.nix-tun.storage.backup.enable {
    nix-tun.storage.backup.server = lib.attrsets.mapAttrs (name: value: {
      host = value.options.networking.host.value;
      btrfs_base = value.options.nix-tun.storage.persist.path.value;
      subvolumes = lib.attrs.mapAttrsToList (name: value: 
        value
      ) (lib.attrsets.filterAttrs (n: v: v.backup) value.options.nix-tun.storage.persist.subvolumes.value);
    }) config.nix-tun.storage.backup.nixosConfigs;

    systemd.tmpfiles.rules = builtins.concatList (lib.attrsets.mapAttrsToList (name: value: [
      "v /backup/${name}${value.btrfs_base} 0700 btrbk btrbk"
    ] ++ (lib.lists.map (v: 
      "d /backup/${name}${value.btrfs_base}/${v} 0700 btrbk btrbk"
    ) value.subvolumes)) config.nix-tun.storage.server);

    services.btrbk.instances = lib.attrsets.mapAttrs (name: value: {
        settings = {
          backend_remote = "btrfs-progs";
          snapshot_preserve = "7d";
          snapshot_preserve_min = "7d";
          target_preserve_min = "2m 21d";
          target_preserve = "6m 30d";
          ssh_identity = "/etc/btrbk/id_ed25519";
          volume = {
            "ssh://${value.host}${value.btrfs_base}" = {
              subvolume = lib.mapAttrs (n: v: {
                snapshot_create = "always";
                snapshot_dir = "${n}/.snapshots";
                target = "/backup/${name}${value}/${n}";
              })
              value.options.nix-tun.storage.persist.subvolumes.value;
            };
          };
        };
      }) config.nix-tun.storage.backup.server;
  };
}
