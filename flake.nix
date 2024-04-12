{
  description = "Dependency and Build Process for the python-kidra";

  inputs = {
    # TODO: change this to nixos-24.05, once it has been released (~2024-06-01)
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # utilities
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
    nix2container.url = "github:nlewo/nix2container";
    openapi-checks = {
      url = "github:openeduhub/nix-openapi-checks";
      inputs = {
        nixpkgs.follows = "nixpkgs";
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
          controlling the package versions of this sub-service here,
          rather than in the service itself.
          as a result, updates to the package versions in the service
          will not actually affect anything for the service
          run within the kidra.
        */
        nixpkgs.follows = "nixpkgs";
      };
    };
    wlo-topic-assistant = {
      url = "github:joopitz/wlo-topic-assistant/plainNix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    wlo-classification = {
      url = "github:joopitz/wlo-classification/nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    text-extraction = {
      url = "github:openeduhub/text-extraction";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    its-jointprobability = {
      url = "github:openeduhub/its-jointprobability";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    topic-statistics = {
      url = "github:openeduhub/topic-statistics";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      # create an attribute set from the inputs, mapping each input name to its
      # default package.
      # we pass this onto the package build, in order to "inject" these
      # package's to the build / runtime environment
      additionalPackages =
        system:
        builtins.mapAttrs (name: value: value.packages.${system}.default) ({
          inherit (self.inputs)
            its-jointprobability
            text-extraction
            text-statistics
            topic-statistics
            wlo-classification
            wlo-topic-assistant
            ;
        });
    in
    {
      overlays = import ./overlays.nix {
        inherit additionalPackages;
        inherit (nixpkgs) lib;
        nix-filter = self.inputs.nix-filter.lib;
      };
    }
    // (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system}.extend self.outputs.overlays.default;
      in
      {
        packages =
          { }
          // (nixpkgs.lib.optionalAttrs
            # wlo-classification, a dependency of this application, only runs
            # on linux
            (!pkgs.stdenv.isDarwin)
            rec {
              inherit (pkgs) python-kidra;
              default = python-kidra;
              docker = pkgs.callPackage ./docker.nix {
                nix2container = self.inputs.nix2container.packages.${system}.nix2container;
              };
            }
          );

        devShells.default = pkgs.callPackage ./shell.nix { };
        checks =
          { }
          // (nixpkgs.lib.optionalAttrs
            # wlo-classification, a dependency of this application, only runs
            # on linux
            (!pkgs.stdenv.isDarwin)
            {
              test-service = self.inputs.openapi-checks.lib.${system}.test-service {
                service-bin = "${pkgs.python-kidra}/bin/python-kidra";
                service-port = 8080;
                openapi-domain = "/v3/api-docs";
                memory-size = 8 * 1024;
                skip-endpoints = [
                  "/link-wikipedia" # requires internet
                  "/text-extraction" # requires internet
                  "/update-data" # requires internet
                  "/topic-statistics" # requires data
                  "/bayesian-predictions" # makes ram explode; tested upstream
                ];
              };
            }
          );
      }
    ));
}
