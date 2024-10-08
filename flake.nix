{
  description = "A collection of NixOS Modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    rust-overlay.url = "github:oxalica/rust-overlay";
    authentik-nix.url = "github:nix-community/authentik-nix";
  };

  outputs = {
    nixpkgs,
    self,
    ...
  } @ inputs: let
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

    documentation = import ./documentation {inherit forAllSystems lib inputs;};

    nixosModules.nix-tun = {...}: {
      imports = [
        ./modules
	inputs.impermanence.nixosModules.impermanence
      ];
    };
  };
}
