{ pkgs, lib, ... }: {
  options = {
    nix-tun.utils.prometheus-exporter = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      description = ''
        A map of job-names to domains, under which prometheus exporter can be reached.
        Job names should be equivalent, to the scraper type.
        e.g. node-exporter for  prometheus-node-exporter
      '';
      default = { };
    };
  };

}
