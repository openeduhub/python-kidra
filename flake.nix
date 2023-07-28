{
  description = "Dependency and Build Process for the python_kidra";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    text-statistics = {
      url = "github:openeduhub/text-statistics/native-application";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {inherit system;};
        python = pkgs.python310;
        text-statistics = self.inputs.text-statistics.packages.${system}.text-statistics;

        # declare the python packages used for building & developing
        python-packages-build = python-packages:
          with python-packages; [
            cherrypy
            requests
          ];
        python-build = python.withPackages python-packages-build;


        python-packages-devel = python-packages:
          with python-packages; [
            black
            pyflakes
            isort
            ipython
            jupyter
          ] ++ (python-packages-build python-packages);
        python-devel = python.withPackages python-packages-devel;

        # declare, how the python application shall be built
        python-kidra = python-build.pkgs.buildPythonApplication {
            pname = "python-kidra";
            version = "1.1.0";
            # we have to disable catching conflicts here because
            # it is giving false positives due to the import of other python
            # packages that are not actually part of the python environment
            # for the kidra
            catchConflicts = false;
            propagatedBuildInputs = [
              python-build
              text-statistics
            ];
            src = ./.;
          };

        # declare, how the docker image shall be built
        docker-img = pkgs.dockerTools.buildImage {
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
            text-statistics
            python-devel
            # python language server
            pkgs.nodePackages.pyright
            # nix language server
            pkgs.rnix-lsp
          ];
        };
      }
    );
}
