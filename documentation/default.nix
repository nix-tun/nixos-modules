{
  self,
  forAllSystems,
  lib,
  inputs,
}:
forAllSystems (system: let
  overlays = [(import inputs.rust-overlay)];
  pkgs = import inputs.nixpkgs {inherit system overlays;};
  generateModuleDoc = (options: 
    lib.makeOptionsDoc {
      inherit options;
    }.optionsCommonMark
  );
in
  pkgs.stdenv.mkDerivation {
    buildInputs = with pkgs; [
      mdbook
      mdbook-katex
      mdbook-emojicodes
      mdbook-d2
      mdbook-pdf
      mdbook-plantuml
      d2
      rust-bin.stable.latest.default
    ];
    name = "nix-tun Documentation";
    src = self;
    buildPhase = ''
      mkdir book
      mdbook build -d book
    '';
    installPhase = "mdbook build -d $out/book";
  })
