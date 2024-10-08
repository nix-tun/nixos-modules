{
  forAllSystems,
  lib,
  inputs,
} : forAllSystems (system: let
  overlays = [(import inputs.rust-overlay)];
  pkgs = import inputs.nixpkgs {inherit system overlays;};
  eval = lib.evalModules {
    check = false;
    modules = [
      ../modules
    ];
  };
  generateModuleDoc = 
    (pkgs.nixosOptionsDoc {
      options = eval.options;
      warningsAreErrors = false;
    });
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
    name = "nix-tun documentation";
    src = ../.;
    buildPhase = "mkdir $out";
    #''
    #  mkdir book
    #  mdbook build -d book
    #'';
    installPhase = ''
      cat ${generateModuleDoc} >> $out/doc.md
    ''; #"mdbook build -d $out/book";
})
