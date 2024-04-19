{
  lib,
  nix-filter,
  additionalOverlays ? ([ ]),
}:
rec {
  default = python-kidra;

  # add the additional packages
  fix-nixpkgs = lib.composeManyExtensions additionalOverlays;

  # add the python-kidra itself, which includes in its runtime PATH a reference
  # to each package given by the additional inputs.
  python-kidra = lib.composeExtensions fix-nixpkgs (
    final: prev: {
      python-kidra = final.python3Packages.callPackage ./package.nix ({ inherit nix-filter; });
    }
  );
}
