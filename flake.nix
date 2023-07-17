{
  description = "Build system & development environment for python-kidra";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, poetry2nix, ... }:
  flake-utils.lib.eachSystem
  ["x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin"]
  (system:
  let
    # import nix packages, utilities, and poetry2nix functions
    pkgs = import nixpkgs { inherit system; };
    inherit (poetry2nix.legacyPackages.${system}) mkPoetryApplication mkPoetryEnv;

    # specify general information, such as the Python version we are using
    projectDir = self;
    python = pkgs.python310;

    # generate development environment
    # for this, we can just rely on the pre-compiled sources, e.g. at PyPi
    python-env = mkPoetryEnv {
      inherit projectDir python;
      preferWheels = true;
      groups = [ "dev" ];
    };

    # build python application,
    # compiling (almost) all individual packages to ensure reproducibility
    python-app = mkPoetryApplication {
      inherit projectDir python;
      preferWheels = false;
      groups = [ ];
      # fix missing dependencies of python packages
      # this is only required because we set preferWheels = false,
      # which causes installation from source for python packages
      # rather than just pulling their binaries from PyPi or similar
      overrides = pkgs.poetry2nix.overrides.withDefaults (self: super:
        import ./overrides.nix {inherit self super; lib=nixpkgs.lib;}
      );
    };

    # download nltk-punkt, an external requirement for nltk
    nltk-punkt = pkgs.fetchurl {
      url = "https://github.com/nltk/nltk_data/raw/5db857e6f7df11eabb5e5665836db9ec8df07e28/packages/tokenizers/punkt.zip";
      sha256 = "sha256-UcMHiZSur2UL/I4Ci+T7QrSg0XfUHAErapg5eWU2YOw=";
    };

    # declare, how the docker image shall be built
    docker-img = pkgs.dockerTools.buildImage {
      name = python-app.pname;
      tag = python-app.version;
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
        paths = [ python-app ];
        pathsToLink = [ "/bin" ];
      };
    };

  in
  {
    packages = rec {
      python-kidra = python-app;
      docker = docker-img;
      default = docker;
    };
    devShells.default = pkgs.mkShell {
      buildInputs = [
        python-env                # the python development environment itself
        pkgs.poetry               # for interaction with poetry
        pkgs.nodePackages.pyright # python LSP server
        pkgs.rnix-lsp             # nix LSP server
      ];
    };
  }
  );
}
