{
  description = "Build system & development environment for python-kidra";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, poetry2nix }:
    let
      # only support the x86 architecture, running on linux
      # TODO: also support MacOS
      system = "x86_64-linux";

      # import nix packages, utilities, and poetry2nix functions
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      l = nixpkgs.lib;
      inherit (poetry2nix.legacyPackages.${system}) mkPoetryApplication mkPoetryEnv;

      # specify general information, such as the Python version we are using
      projectDir = self;
      python = pkgs.python310;

      # generate development environment
      # for this, we can just rely on the pre-compiled sources, e.g. at PyPi
      poetry-env = mkPoetryEnv {
        inherit projectDir python;
        preferWheels = true;
        groups = [ "dev" ];
      };

      # build python application,
      # compiling (almost) all individual packages to ensure reproducibility
      poetry-app = mkPoetryApplication {
        inherit projectDir python;
        preferWheels = false;
        groups = [ ];
        # fix missing dependencies of external packages
        # this is only required if we set preferWheels = false;
        overrides = pkgs.poetry2nix.overrides.withDefaults (self: super:
          (l.listToAttrs (
            # packages that are missig setuptools
            l.lists.forEach
              ["autocommand" "justext" "courlan" "htmldate" "trafilatura"]
              (x: {
                name = x;
                value = super."${x}".overridePythonAttrs (old: {
                  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [self.setuptools];
                });
              })
            ++
            # packages that are missing hatchling
            l.lists.forEach
              ["annotated-types"]
              (x: {
                name = x;
                value = super."${x}".overridePythonAttrs (old: {
                  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [self.hatchling];
                });
              })
            ++
            # packages that should not be compiled manually
            l.lists.forEach
              ["pydantic" "pydantic-core"]
              (x: {
                name = x;
                value = super."${x}".override {
                  preferWheel = true;
                };
              })
          )));
      };
      
      # download nltk-punkt, an external requirement for nltk
      nltk-punkt = pkgs.fetchurl {
        url = "https://github.com/nltk/nltk_data/raw/5db857e6f7df11eabb5e5665836db9ec8df07e28/packages/tokenizers/punkt.zip";
        sha256 = "sha256-UcMHiZSur2UL/I4Ci+T7QrSg0XfUHAErapg5eWU2YOw=";
      };

      # declare, how the docker image shall be built
      docker-image = pkgs.dockerTools.buildImage {
        name = poetry-app.pname;
        tag = poetry-app.version;
        # unzip nltk-punkt and put it into a directory that nltk searches
        config = {
          Cmd = [
            "${pkgs.bash}/bin/sh" (pkgs.writeShellScript "runDocker.sh" ''
                ${pkgs.coreutils}/bin/mkdir -p /nltk_data/tokenizers;
                ${pkgs.unzip}/bin/unzip ${nltk-punkt} -d /nltk_data/tokenizers;
                /bin/python-kidra
              '')
          ];
          WorkingDir = "/";
        };
        # copy the binary of the application into the image
        copyToRoot = pkgs.buildEnv {
          name = "image-root";
          paths = [ poetry-app ];
          pathsToLink = [ "/bin" ];
        };
      };
      
    in
      {
        packages.${system} = rec {
          python-kidra = poetry-app;
          docker = docker-image;
          default = docker;
        };
        devShells.${system}.default = pkgs.mkShell {
          buildInputs = [
            poetry-env
            # external packages
            pkgs.poetry
            pkgs.nodePackages.pyright
          ];
        };
      };
}
