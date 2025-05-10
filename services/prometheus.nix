{ pkgs, config, lib, ... }: {
  options = { };

  config = {
    nix-tun.utils.containers.prometheus = { };
  };
}
