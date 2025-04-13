{ pkgs, config, lib, ... }: {
  options = {
    nix-tun.services.prometheus = { };
  };

  config = {
    nix-tun.utils.containers.prometheus = { };
  };
}
