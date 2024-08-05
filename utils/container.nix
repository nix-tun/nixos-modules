{ config, lib, ... } : {
  options.nix-tun.container = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ config, lib, name, ... } : {
      options = {
        network-zone = lib.mkOption {
	  type = lib.str;
	  default = name;
	};
	volume = lib.mkOption {
	  type = lib.str;
	  default = {}
	  description = ''
	    Bind mound
	  ''
	};
      };
    }));

  };

  config = {

    containers = lib.attrs.mapAttrs (name: value: {
      extraFlags = [
        "--network-zone=${value.network-zone}"
      ];
    });
  };
}
