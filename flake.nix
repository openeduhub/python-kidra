{
  description = "Dependency and Build Process for the python-kidra";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    flake-utils.url = "github:numtide/flake-utils";
    text-statistics = {
      url = "github:openeduhub/text-statistics/native-application";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-filter.url = "github:numtide/nix-filter";
    nix2container.url = "github:nlewo/nix2container";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # add text-statistics to our collection of nix packages
          overlays = [self.inputs.text-statistics.overlays.default];
        };
        # an alias for the python version we are using
        python = pkgs.python310;

        nix2container = self.inputs.nix2container.packages.${system}.nix2container;
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
          version = "1.1.0";
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
          only make available the binary of text-statistics to the kidra.
          if we simply included the entire package,
          its propagated dependencies (i.e. python libraries) would also be
          included in the environment of the kidra, breaking isolation and
          likely causing version conflicts.
          */
          makeWrapperArgs = [
            "--prefix PATH : ${pkgs.lib.makeBinPath [pkgs.text-statistics]}"
          ];
        };

        ### declare how the docker image shall be built
        docker-img = nix2container.buildImage {
          name = python-kidra.pname;
          tag = python-kidra.version;
          config = {
            Cmd = [ "${python-kidra}/bin/python-kidra" ];
          };
          layers = [
            (nix2container.buildLayer
              { deps = [pkgs.text-statistics]; maxLayers = 20;})
          ];
          maxLayers = 20;
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
