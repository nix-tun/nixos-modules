{ pkgs, lib, ... }: {
  options = {
    nix-tun.metrics.prometheus-exporter = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ ... }: { }));
      description = ''
        An interface to advertise prometheus exporters this system exposes.
      '';
    };
  };

  config = { };
}
