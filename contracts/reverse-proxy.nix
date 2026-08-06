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
    { domain ? null
    , domainText ? null
    , path ? "/"
    , pathText ? null
    , port ? null
    , portText ? null
    , protocol ? "https"
    , protocolText ? null
    , internalUrl ? "http://localhost:80"
    , internalUrlText ? null
    , authType ? null
    , authTypeText ? null
    , authName ? null
    , authNameText ? null
    }: lib.types.submodule (sub: {
      options = {
        domain = mkOption lib.types.str domain domainText;
        path = mkOption lib.types.str path pathText;
        protocol = mkOption (lib.types.enum [ "http" "https" "tcp" "udp" ]) protocol protocolText;
        port = mkOption lib.types.port (if (sub.config.protocol == "https") then 443 else port) portText;
        internalUrl = mkOption lib.types.str internalUrl internalUrlText;
        authType = mkOption (lib.types.nullOr lib.types.str) authType authTypeText;
        authName = mkOption (lib.types.nullOr lib.types.str) authName authNameText;
      };
    });
  defaultName = request: request.internalUrl;
  mkResponse = ({}: lib.types.submodule {
    options = {
      externalUrl = lib.mkOption {
        type = lib.types.str;
      };
    };
  });
in
{
  inherit mkResponse mkRequest defaultName;
}
