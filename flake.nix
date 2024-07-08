{
  description = "A collection of NixOs Modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: {
    packages =
      nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "i686-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ] (
        system: let
          inherit (nixpkgs) lib;
          pkgs = nixpkgs.legacyPackages.${system};
        in
          universalPackages // testbedPackages
      );

    nixosModules.nix-tun = {pkgs, ...} @ inputs: {
      imports = [
        ./yubikey-gpg.nix
      ];
    };
  };
}
