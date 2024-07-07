{
  description = "A collection of NixOs Modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs: {

    packages = nixpkgs.lib.genAttrs [
      "aarch64-darwin"
      "aarch64-linux"
      "i686-linux"
      "x86_64-darwin"
      "x86_64-linux"
    ] (system: 
        let
          inherit (nixpkgs) lib;
          pkgs = nixpkgs.legacyPackages.${system};

          universalPackages = {
            docs = import ./docs { inherit pkgs inputs lib; };
            palette-generator = pkgs.callPackage ./palette-generator { };
          };

          # Testbeds are virtual machines based on NixOS, therefore they are
          # only available for Linux systems.
          testbedPackages = lib.optionalAttrs
            (lib.hasSuffix "-linux" system)
            (import ./stylix/testbed.nix { inherit pkgs inputs lib; });
        in
          universalPackages // testbedPackages
      );

      nixosModules.stylix = { pkgs, ... }@inputs: {
        imports = [
	  ./yubikey-gpg.nix
        ];
      };
  };
}
