{
  lib,
  nix-filter,
  buildPythonApplication,
  fastapi,
  pydantic,
  uvicorn,
  requests,
  its-jointprobability,
  text-extraction,
  text-statistics,
  topic-statistics,
  wlo-classification,
  wlo-topic-assistant,
}:
buildPythonApplication {
  pname = "python-kidra";
  version = "1.3.0";

  src = nix-filter {
    root = ./.;
    include = [
      "src"
      ./setup.py
      ./requirements.txt
    ];
    exclude = [ (nix-filter.matchExt "pyc") ];
  };

  # this package has no tests
  doCheck = false;

  propagatedBuildInputs = [
    fastapi
    pydantic
    uvicorn
    requests
  ];

  /*
    only make available the binaries of the sub-services to the kidra. if we
    simply included the entire packages, their propagated dependencies (i.e.
    python libraries) would also be included in the environment of the kidra,
    breaking isolation and likely causing version conflicts.
  */
  makeWrapperArgs = [
    "--suffix PATH : ${
      lib.makeBinPath [
        its-jointprobability
        text-extraction
        text-statistics
        topic-statistics
        wlo-classification
        wlo-topic-assistant
      ]
    }"
  ];
}
