{
  description = "A collection of NixOS Modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = {nixpkgs, ...} @ inputs: let
    systems = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ];

    lib = nixpkgs.lib;

    forAllSystems = lib.genAttrs systems;
  in {
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    nixosModules.nix-tun = {pkgs, ...}: {
      imports = [
        ./yubikey-gpg.nix
        inputs.impermanence.nixosModules.impermanence
        ./storage/persist.nix
	./services/containers/nextcloud.nix
        #./services/matrix.nix
        ./services/traefik.nix
      ];
    };
  };
}
