{ lib, pkgs, config, ... }:
let
  importContract = contract: defaultResponder:
    let
      c = pkgs.callPackage contract { };
      mkResponder = {
        request = lib.mkOption {
          type = lib.types.attrsOf (c.mkRequest { });
          default = { };
        };
        response = lib.mkOption {
          type = lib.types.attrsOf (c.mkResponse { });
          default = { };
        };
      };
      mkRequester = requestCfg: lib.types.submodule (sub: {
        options = {
          request = lib.mkOption {
            type = c.mkRequest requestCfg;
          };
          provider = lib.mkOption {
            type = lib.types.str;
            default = defaultResponder;
          };
          getResponse = lib.mkOption {
            type = lib.types.anything;
            default = getResponse sub.config;
          };
        };
      });
      mapResponse = requests: f: lib.attrsets.mapAttrs (name: v: f name (v.getResponse name)) requests;
      setRequests = requests: lib.attrsets.foldlAttrs (acc: name: v: (lib.attrsets.recursiveUpdate acc (lib.attrsets.setAttrByPath (v.provider ++ [ "request" name ]) v.request))) { } requests;
      getResponse = request: name: lib.attrsets.getAttrFromPath (request.provider ++ [ "response" name ]) config;
    in
    {
      defaultResponder = lib.mkOption {
        type = lib.types.str;
      };
      responder = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = mkResponder;
        });
        default = { };
      };
      mkResponder = lib.mkOption {
        type = lib.types.anything;
        default = mkResponder;
      };
      mkRequester = lib.mkOption {
        type = lib.types.anything;
        default = mkRequester;
      };
      mapResponse = lib.mkOption {
        type = lib.types.anything;
        default = mapResponse;
      };
      setRequests = lib.mkOption {
        type = lib.types.anything;
        default = setRequests;
      };
    };
in
{
  options.contracts = {
    reverseProxy = importContract ./reverse-proxy.nix config.contracts.reverseProxy.defaultResponder;
    oauth = importContract ./oauth.nix config.contracts.reverseProxy.defaultResponder;
    secret = importContract ./secrets.nix config.contracts.reverseProxy.defaultResponder;
  };
}
