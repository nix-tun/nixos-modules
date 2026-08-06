{ lib, config, ... }:
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
    { clientId ? null
    , clientIdText ? null
    , redirectUris ? null
    , redirectUrisText ? null
    , scopes ? [ "openid" "profile" "email" ]
    , scopesText ? null
    }: lib.types.submodule {
      options = {
        clientId = mkOption lib.types.str clientId clientIdText;
        redirectUris = mkOption (lib.types.listOf lib.types.str) redirectUris redirectUrisText;
        scopes = mkOption (lib.types.listOf lib.types.str) scopes scopesText;
        clientSecretOwner = mkOption lib.types.str "root" null;
        clientSecretGroup = mkOption lib.types.str "root" null;
      };
    };
  mkResponse =
    { issuer ? null
    , issuerText ? null
    , authUrl ? null
    , authUrlText ? null
    , tokenUrl ? null
    , tokenUrlText ? null
    , userInfoUrl ? null
    , userInfoUrlText ? null
    , clientSecret ? null
    , clientSecretText ? null
    }: lib.types.submodule {
      options = {
        clientSecret = mkOption lib.types.str clientSecret clientSecretText;
        clientSecretResponder = mkOption lib.types.str null null;
        issuer = mkOption lib.types.str issuer issuerText;
        authUrl = mkOption lib.types.str authUrl authUrlText;
        tokenUrl = mkOption lib.types.str tokenUrl tokenUrlText;
        userInfoUrl = mkOption lib.types.str userInfoUrl userInfoUrlText;
      };
    };
in
{
  inherit mkRequest mkResponse;
}
