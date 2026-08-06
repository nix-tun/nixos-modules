{ lib, config, ... }: {
  options = {
    nix-tun.services.samba-dc = {
      enable = lib.mkEnableOption "Enable Samba DC Service";
    };
  };

  config = lib.mkIf config.nix-tun.services.samba-dc.enable {
    nix-tun.utils.containers.samba-dc = { };
  };
}
