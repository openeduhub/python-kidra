{
  description = "Dependency and Build Process for the python-kidra";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    # utilities
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
    nix2container.url = "github:nlewo/nix2container";
    openapi-checks = {
      url = "github:openeduhub/nix-openapi-checks";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
    # sub-services
    text-statistics = {
      url = "github:openeduhub/text-statistics";
      inputs = {
        /* override inputs to follow ours.
           while this causes the resulting package / image to be much smaller,
           this setting is risky and may cause breaks later, as we are now
           controlling the package versions of this sub-service here,
           rather than in the service itself.
           as a result, updates to the package versions in the service
           will not actually affect anything for the service
           run within the kidra.
        */
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        openapi-checks.follows = "openapi-checks";
      };
    };
    wlo-topic-assistant = {
      url = "github:joopitz/wlo-topic-assistant/plainNix";
      inputs = {
        flake-utils.follows = "flake-utils";
        openapi-checks.follows = "openapi-checks";
      };
    };
    wlo-classification = {
      url = "github:joopitz/wlo-classification/nix";
      inputs = {
        flake-utils.follows = "flake-utils";
        openapi-checks.follows = "openapi-checks";
      };
    };
    text-extraction = {
      url = "github:openeduhub/text-extraction";
      inputs = {
        # see comment above
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        openapi-checks.follows = "openapi-checks";
      };
    };
    its-jointprobability = {
      url = "github:openeduhub/its-jointprobability";
      inputs = {
        flake-utils.follows = "flake-utils";
        openapi-checks.follows = "openapi-checks";
      };
    };
    topic-statistics = {
      url = "github:openeduhub/topic-statistics";
      inputs = {
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            # add overlays of the sub-services
            overlays = [
              self.inputs.text-statistics.overlays.default
              self.inputs.topic-statistics.overlays.default
              self.inputs.text-extraction.overlays.default
              self.inputs.wlo-topic-assistant.overlays.default
              self.inputs.wlo-classification.overlays.default
              self.inputs.its-jointprobability.overlays.default
            ];
          };
          # an alias for the python version we are using
          python = pkgs.python310;

          nix2container =
            self.inputs.nix2container.packages.${system}.nix2container;
          # utility to easily filter out unnecessary files from the source
          nix-filter = self.inputs.nix-filter.lib;
          openapi-checks = self.inputs.openapi-checks.lib.${system};

          ### declare the python packages used for building & developing
          python-packages-build = python-packages:
            with python-packages; [
              fastapi
              pydantic
              uvicorn
              requests
            ];

          python-packages-devel = python-packages:
            with python-packages;
            [ black pyflakes isort ipython jupyter ]
            ++ (python-packages-build python-packages);

          ### declare how the python application shall be built
          python-kidra = python.pkgs.buildPythonApplication rec {
            pname = "python-kidra";
            version = "1.2.2";
            src = nix-filter {
              root = self;
              include = [ "src" ./setup.py ./requirements.txt ];
              exclude = [ (nix-filter.matchExt "pyc") ];
            };
            doCheck = false;
            propagatedBuildInputs = (python-packages-build python.pkgs);
            /* only make available the binaries of the sub-services to the kidra.
             if we simply included the entire packages,
             their propagated dependencies (i.e. python libraries) would also be
             included in the environment of the kidra, breaking isolation and
             likely causing version conflicts.
            */
            makeWrapperArgs = [
              "--suffix PATH : ${
              pkgs.lib.makeBinPath [
                pkgs.text-statistics
                pkgs.topic-statistics
                pkgs.text-extraction
                pkgs.wlo-topic-assistant
                pkgs.wlo-classification
                pkgs.its-jointprobability
              ]
            }"
            ];
          };

          ### declare how the docker image shall be built
          docker-img = nix2container.buildImage {
            name = python-kidra.pname;
            tag = python-kidra.version;
            config = {
              Cmd = [ "${python-kidra}/bin/python-kidra" ];
              ExposedPorts = { "8080/tcp" = { }; };
            };
            layers =
              (map
                ({ pkg, maxLayers }:
                  nix2container.buildLayer {
                    deps = [ pkg ]; inherit maxLayers;
                  })
                [
                  { pkg = pkgs.text-statistics; maxLayers = 5; }
                  { pkg = pkgs.topic-statistics; maxLayers = 5; }
                  { pkg = pkgs.text-extraction; maxLayers = 5; }
                  { pkg = pkgs.wlo-topic-assistant; maxLayers = 30; }
                  { pkg = pkgs.wlo-classification; maxLayers = 30; }
                  { pkg = pkgs.its-jointprobability; maxLayers = 30; }
                ]);
            maxLayers = 5;
          };

        in
        {
          packages = { } // (nixpkgs.lib.optionalAttrs
            /* wlo-classification, a dependency of this application,
               only runs on x86_64-linux */
            (system == "x86_64-linux")
            {
              inherit python-kidra;
              docker = docker-img;
              default = python-kidra;
            });

          devShells.default = pkgs.mkShell {
            buildInputs = [
              (python.withPackages python-packages-devel)
              # python language server
              pkgs.nodePackages.pyright
              # cli tool to validate OpenAPI schemas
              pkgs.swagger-cli
            ];
          };
          checks = { } // (nixpkgs.lib.optionalAttrs
            /* wlo-classification, a dependency of this application,
               only runs on x86_64-linux */
            (system == "x86_64-linux")
            {
              test-service = openapi-checks.test-service {
                service-bin = "${python-kidra}/bin/python-kidra";
                service-port = 8080;
                openapi-domain = "/v3/api-docs";
                memory-size = 8 * 1024;
                skip-endpoints = [
                  "/link-wikipedia" # requires internet
                  "/text-extraction" # requires internet
                  "/update-data" # requires internet
                  "/topic-statistics" # requires data
                ];
              };
            });
        });
}
