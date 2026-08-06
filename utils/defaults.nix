{ lib, config, ... }: {
  options.nix-tun.defaults = {
    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = ''
        The default domain for nix-tun services. Nix-tun services will be available under
        <service-name>.<default-domain> if not configured otherwise.
      '';
      default = null;
    };
  };

  config = {
    lib.nix-tun.mkDomainOption = (service-name: lib.mkOption {
      type = lib.types.str;
      description = ''
        The domain name of this service.
      '';
      default = "${service-name}.${config.nix-tun.defaults.domain}";
    });
  };
}
