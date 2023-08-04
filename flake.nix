{
  description = "Dependency and Build Process for the python-kidra";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    # utilities
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
    # sub-services
    text-statistics = {
      url = "github:openeduhub/text-statistics/native-application";
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
      };
    };
    wlo-topic-assistant = {
      url = "github:joopitz/wlo-topic-assistant/plainNix";
      # see comment above
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # add overlays of the sub-services
          overlays = [
            self.inputs.text-statistics.overlays.default
            self.inputs.wlo-topic-assistant.overlays.default
          ];
        };
        # an alias for the python version we are using
        python = pkgs.python310;
        # utility to easily filter out unnecessary files from the source
        nix-filter = self.inputs.nix-filter.lib;

        ### declare the python packages used for building & developing
        python-packages-build = python-packages:
          with python-packages; [ cherrypy
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
          version = "1.1.2";
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
          makeWrapperArgs = [
            "--prefix PATH : ${pkgs.lib.makeBinPath [pkgs.text-statistics]}"
            "--prefix PATH : ${pkgs.lib.makeBinPath [pkgs.wlo-topic-assistant]}"
          ];
        };

        ### declare how the docker image shall be built
        docker-img = pkgs.dockerTools.buildLayeredImage {
          name = python-kidra.pname;
          tag = python-kidra.version;
          config = {
            Cmd = [ "${python-kidra}/bin/python-kidra" ];
          };
        };

      in {
        packages = rec {
          inherit python-kidra;
          docker = docker-img;
          default = python-kidra;
        };
        devShells.default = pkgs.mkShell {
          buildInputs = [
            (python-packages-devel python.pkgs)
            # python language server
            pkgs.nodePackages.pyright
          ];
        };
      }
    );
}
