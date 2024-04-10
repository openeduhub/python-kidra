{
  lib,
  nix-filter,
  additionalOverlays ? [ ],
}:
rec {
  default = python-kidra;

  # add the python-kidra itself, which includes in its runtime PATH a reference
  # to each package given by the additional inputs.
  python-kidra = lib.composeManyExtensions (additionalOverlays ++ [
    (final: prev: {
      python-kidra = final.python3Packages.callPackage ./package.nix { inherit nix-filter; };
    })
  ]);
}
