{ lib, config, ... }: {
  options.nix-tun.services.sops = {
    enable = lib.mkEnableOption "Enable Sops as Secret Respoder";
  };

  config = {
    contracts.secret.defaultResponder = "sops";
    contracts.secret.responder.sops.response = lib.attrsets.mapAttrs
      (name: value: {
        path = config.sops.secrets."${name}".path;
      })
      config.contracts.secret.responder.sops.request;

    sops.secrets = lib.attrsets.mapAttrs
      (name: value: {
        mode = value.mode;
        key = value.key;
      } // (lib.optionalAttrs (lib.types.str.check value.owner) {
        owner = value.owner;
      }) // (lib.optionalAttrs (lib.types.int.check value.owner) {
        uid = value.owner;
      }) // (lib.optionalAttrs (lib.types.str.check value.group) {
        group = value.group;
      }) // (lib.optionalAttrs (lib.types.int.check value.group) {
        gid = value.group;
      }))
      config.contracts.secret.responder.sops.request;
  };
}
