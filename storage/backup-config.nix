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
    };
  };

  config = lib.mkIf config.nix-tun.storage.backup.enable {
    systemd.tmpfiles.rules = builtins.concatList (lib.attrsets.mapAttrsToList (name: value: [
      "v /backup/${value.options.networking.hostName.value} 0700 btrbk btrbk"
    ] ++ (lib.attrsets.mapAttrsToList (n: v: 
      "d /backup/${value.options.networking.hostName.value}/${n} 0700 btrbk btrbk"
    ) (lib.attrsets.filterAttrs (n: v: v.backup) value.options.nix-tun.storage.persist.subvolumes.value))) config.nix-tun.storage.backup.nixosConfigs);

    services.btrbk.instances = lib.attrsets.mapAttrs' (name: value: {
        name = value.options.networking.hostName.value;
        value = {
          settings = {
            backend_remote = "btrfs-progs";
            snapshot_preserve = "7d";
            snapshot_preserve_min = "7d";
            target_preserve_min = "2m 21d";
            target_preserve = "6m 30d";
            ssh_identity = "/etc/btrbk/id_ed25519";
            volume = {
              "ssh://${value.options.networking.hostName.value}${value.options.nix-tun.storage.persist.path.value}" = {
                subvolume = lib.mapAttrs (n: v: {
                    snapshot_create = "always";
                    snapshot_dir = "${n}/.snapshots";
                    target = "/backup/${value.options.networking.hostName.value}/${n}";
                  })
                  value.options.nix-tun.storage.persist.subvolumes.value;
              };
            };
          };
        };
      }) config.nix-tun.storage.backup.nixosConfigs;
  };
}
