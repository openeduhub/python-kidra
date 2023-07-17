# fix missing dependencies of python packages
{self, super, lib}:
(lib.listToAttrs (
  # packages that are missig setuptools
  lib.lists.forEach
  ["autocommand" "justext" "courlan" "htmldate" "trafilatura"]
  (x: {
    name = x;
    value = super."${x}".overridePythonAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [self.setuptools];
    });
  })
  ++
  # packages that are missing hatchling
  lib.lists.forEach
  ["annotated-types"]
  (x: {
    name = x;
    value = super."${x}".overridePythonAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [self.hatchling];
    });
  })
  ++
  # packages that should not be compiled manually
  lib.lists.forEach
  ["pydantic" "pydantic-core"]
  (x: {
    name = x;
    value = super."${x}".override {
      preferWheel = true;
    };
  })
))
