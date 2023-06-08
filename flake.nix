{
  description = "Basic Python Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    text_statistics.url = "github:openeduhub/text-statistics";
  };

  outputs = { self, nixpkgs, flake-utils, text_statistics }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # declare the python packages used for building & developing
        python-packages-build = python-packages:
          with python-packages; [
          ];
        
        python-packages-devel = python-packages:
          with python-packages; [
            black
            pyflakes
            isort
            ipython
            bootstrapped-pip
          ] ++ (python-packages-build python-packages);
        
        python-build = pkgs.python3.withPackages python-packages-build;
        python-devel = pkgs.python3.withPackages python-packages-devel;
        
      in {
        devShell = pkgs.mkShell {
          buildInputs = [
            text_statistics.defaultPackage.${system}
            python-devel
            # python language server
            pkgs.nodePackages.pyright
          ];
        };
      }
    );
}
