{ lib, ... }:
let
  mkOption = type: default: defaultText: (lib.mkOption
    {
      type = type;
    } // lib.attrsets.optionalAttrs (default != null) {
    default = default;
  } // lib.attrsets.optionalAttrs (defaultText != null) {
    defaultText = lib.literalMD defaultText;
  });
  mkRequest =
    { owner ? "root"
    , ownerText ? null
    , group ? "root"
    , groupText ? null
    , mode ? "400"
    , modeText ? null
    , key ? null
    , keyText ? null
    }: lib.types.submodule ({ name ? key, ... }: {
      options = {
        owner = mkOption (lib.types.either lib.types.str lib.types.int) owner ownerText;
        group = mkOption (lib.types.either lib.types.str lib.types.int) group groupText;
        mode = mkOption lib.types.str mode modeText;
        key = mkOption lib.types.str name keyText;
      };
    });
  mkResponse =
    {}: lib.types.submodule {
      options = {
        path = lib.mkOption {
          type = lib.types.str;
        };
      };
    };
in
{
  inherit mkRequest mkResponse;
}
