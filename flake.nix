{
  description = "Basic Python Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    text_statistics = {
      url = "github:openeduhub/text-statistics";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        
        pkgs = nixpkgs.legacyPackages.${system};
        text_statistics = self.inputs.text_statistics.defaultPackage.${system};

        # declare the python packages used for building & developing
        python-packages-build = python-packages:
          with python-packages; [
            cherrypy
          ];
        python-build = pkgs.python3.withPackages python-packages-build;


        python-packages-devel = python-packages:
          with python-packages; [
            black
            pyflakes
            isort
            ipython
          ] ++ (python-packages-build python-packages);
        python-devel = pkgs.python3.withPackages python-packages-devel;

        # declare, how the python application shall be built
        python_ki_hydra = python-build.pkgs.buildPythonApplication {
            pname = "python_ki_hydra";
            version = "1.0.0";

            propagatedBuildInputs =
              (python-packages-build python-build.pkgs)
              ++ [text_statistics];

            src = ./.;
          };

        # download nltk-punkt, an external requirement for nltk
        nltk-punkt = pkgs.fetchurl {
          url = "https://github.com/nltk/nltk_data/raw/5db857e6f7df11eabb5e5665836db9ec8df07e28/packages/tokenizers/punkt.zip";
          sha256 = "sha256-UcMHiZSur2UL/I4Ci+T7QrSg0XfUHAErapg5eWU2YOw=";
        };

        # declare, how the docker image shall be built
        docker-image = pkgs.dockerTools.buildImage {
          name = python_ki_hydra.pname;
          tag = python_ki_hydra.version;

          # unzip nltk-punkt and put it into a directory that nltk considers
          config = {
            Cmd = [
              "${pkgs.bash}/bin/sh"
              (pkgs.writeShellScript "runDocker.sh" ''
                ${pkgs.coreutils}/bin/mkdir -p /nltk_data/tokenizers;
                ${pkgs.unzip}/bin/unzip ${nltk-punkt} -d /nltk_data/tokenizers;
                /bin/python_ki_hydra
              '')
            ];
            WorkingDir = "/";
          };

          # copy the binary of the application into the image
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ python_ki_hydra ];
            pathsToLink = [ "/bin" ];
          };
        };

      in {
        defaultPackage = docker-image;
        devShell = pkgs.mkShell {
          buildInputs = [
            text_statistics
            python-devel
            # python language server
            pkgs.nodePackages.pyright
          ];
        };
      }
    );
}
