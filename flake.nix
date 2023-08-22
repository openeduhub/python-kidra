{
  description = "Dependency and Build Process for the python-kidra";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # utilities
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
    openapi-checks = {
      url = "github:openeduhub/nix-openapi-checks";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-unstable.follows = "nixpkgs-unstable";
        flake-utils.follows = "flake-utils";
      };
    };
    # sub-services
    text-statistics = {
      url = "github:openeduhub/text-statistics";
      inputs = {
        /*
        override inputs to follow ours.
        while this causes the resulting package / image to be much smaller,
        this setting is risky and may cause breaks later, as we are now
        controlling the package versions of this sub-service here, rather than
        in the service itself.
        as a result, updates / changes to the package versions in the service
        will not actually affect anything for the service run within the kidra.
        */    
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        openapi-checks.follows = "openapi-checks";
      };
    };
    wlo-topic-assistant = {
      url = "github:joopitz/wlo-topic-assistant/plainNix";
      # see comment above
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
      # see comment above
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
        openapi-checks.follows = "openapi-checks";
      };
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # add overlays of the sub-services
          overlays = [
            self.inputs.text-statistics.overlays.default
            self.inputs.text-extraction.overlays.default
            self.inputs.wlo-topic-assistant.overlays.default
            self.inputs.wlo-classification.overlays.default
          ];
        };
        # swagger-cli is only available in nixpkgs unstable
        pkgs-unstable = import nixpkgs-unstable {inherit system;};
        # an alias for the python version we are using
        python = pkgs.python310;
        # utility to easily filter out unnecessary files from the source
        nix-filter = self.inputs.nix-filter.lib;
        openapi-checks = self.inputs.openapi-checks.lib.${system};

        ### declare the python packages used for building & developing
        python-packages-build = python-packages:
          with python-packages; [ fastapi
                                  pydantic
                                  uvicorn
                                  requests
                                ];
        
        python-packages-devel = python-packages:
          with python-packages; [ black
                                  pyflakes
                                  isort
                                  ipython
                                  jupyter
                                ]
          ++ (python-packages-build python-packages);

        ### declare how the python application shall be built
        python-kidra = python.pkgs.buildPythonApplication rec {
          pname = "python-kidra";
          version = "1.1.3";
          src = nix-filter {
            root = self;
            include = [
              "src"
              ./setup.py
              ./requirements.txt
            ];
            exclude = [ (nix-filter.matchExt "pyc") ];
          };
          propagatedBuildInputs = (python-packages-build python.pkgs);
          /*
          only make available the binaries of the sub-services to the kidra.
          if we simply included the entire packages,
          their propagated dependencies (i.e. python libraries) would also be
          included in the environment of the kidra, breaking isolation and
          likely causing version conflicts.
          */
          makeWrapperArgs =
            [ "--suffix PATH : ${
              pkgs.lib.makeBinPath
                [ pkgs.text-statistics
                  pkgs.text-extraction
                  pkgs.wlo-topic-assistant
                  pkgs.wlo-classification
                ]}"
            ];
        };

        ### declare how the docker image shall be built
        docker-spec = {
          name = python-kidra.pname;
          tag = python-kidra.version;
          config = {
            Cmd = [ "${python-kidra}/bin/python-kidra" ];
            ExposedPorts = {
              "8080/tcp" = {};
            };
          };
          maxLayers = 120;
        };
        docker-img = pkgs.dockerTools.buildLayeredImage docker-spec;
        docker-stream = pkgs.dockerTools.streamLayeredImage docker-spec;

      in {
        packages = rec {
          inherit python-kidra docker-stream;
          docker = docker-img;
          default = python-kidra;
        };
        devShells.default = pkgs.mkShell {
          buildInputs = [
            (python.withPackages python-packages-devel)
            # python language server
            pkgs.nodePackages.pyright
            # cli tool to validate OpenAPI schemas
            pkgs-unstable.swagger-cli
          ];
        };
        checks = {
          openapi-check = openapi-checks.openapi-valid {
            serviceBin = "${self.packages.${system}.python-kidra}/bin/python-kidra";
            openapiDomain = "v3/api-docs";
            memorySize = 6144;
          };
        };
      }
    );
}
