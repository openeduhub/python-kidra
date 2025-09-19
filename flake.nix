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
      # see comment on the overlays for potential consequences of making the
      # nixpkgs version of this service follow the kidra's. this is useful to
      # do in addition to using the overlays because this way, additional
      # dependencies such as `its-data` or `its-prep`, will also be built using
      # the same nixpkgs version
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wlo-topic-assistant = {
      url = "github:joopitz/wlo-topic-assistant/plainNix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wlo-classification = {
      url = "github:joopitz/wlo-classification/nix";
    };
    text-extraction = {
      url = "github:openeduhub/text-extraction";
    };
    its-jointprobability = {
      url = "github:openeduhub/its-jointprobability";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    topic-statistics = {
      url = "github:openeduhub/topic-statistics";
      inputs.nixpkgs.follows = "nixpkgs";
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
      # we add the packages provided by these external projects through nixpkgs
      # overlays. this is more convenient than simply using their packages
      # because it lets us configure nixpkgs settings globally here -- e.g.
      # whether we want to build the kidra and all of its dependencies with
      # CUDA support.
      # do note that this also causes the service to use (by default) the exact
      # same dependencies as all other services. while this can significantly
      # reduce the size of the final application, it can also cause issues due
      # to breaking changes in some dependencies. as a result, adding the
      # services this way may cause some breakage and trial-and-error. the way
      # of providing them below is always going to be safe.
      additionalOverlays =
        # save being overly verbose by mapping over the input names
        (map (inp: inp.overlays.default) (
          with self.inputs;
          [
            its-jointprobability
            text-extraction
            text-statistics
            topic-statistics
            wlo-topic-assistant
          ]
        ))
        ++
        # if a service does not provide an overlay, we can still proceed by
        # manually defining an overlay that adds said package here.
        # however, the packages that were added this way will not respect the
        # configuration options we define here. for instance, they may always /
        # never be built with CUDA support.
        # adding them this way may also be necessary if a service requires
        # specific versions of its dependencies, since the versions enforced by
        # the flake.lock of the service are not respected when using overlays
        # (see comment above).
        [
          # this service does not work on the current version of nixpkgs, due
          # to an issue in `keras`, which causes a runtime dependency to not be
          # found
          (final: prev: {
            wlo-classification = self.inputs.wlo-classification.packages.${final.system}.default;
          })
        ];
    in
    {
      # provide the overlays defined in overlays.nix
      overlays = import ./overlays.nix {
        inherit additionalOverlays;
        inherit (nixpkgs) lib;
        nix-filter = self.inputs.nix-filter.lib;
      };
    }
    // (flake-utils.lib.eachDefaultSystem (
      system:
      let
        # build packages with or without CUDA support
        get-pkgs =
          cudaSupport:
          import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              inherit cudaSupport;
            };
            overlays = [ self.outputs.overlays.default ];
          };

        pkgs-without-cuda = get-pkgs false;
        pkgs-with-cuda = get-pkgs true;
      in
      {
        packages =
          { }
          // (nixpkgs.lib.optionalAttrs
            # wlo-classification, a dependency of this application, only runs
            # on linux
            (!pkgs-without-cuda.stdenv.isDarwin)
            rec {
              # packages without CUDA
              inherit (pkgs-without-cuda) python-kidra;
              default = python-kidra;
              python-kidra-without-browsers = python-kidra.override { includeBrowsers = false; };
              without-browsers = python-kidra-without-browsers;
              docker = pkgs-without-cuda.callPackage ./docker.nix {
                nix2container = self.inputs.nix2container.packages.${system}.nix2container;
              };
              docker-without-browsers = docker.override { python-kidra = python-kidra-without-browsers; };

              # packages with CUDA
              python-kidra-with-cuda = pkgs-with-cuda.python-kidra;
              with-cuda = python-kidra-with-cuda;
              docker-with-cuda = pkgs-with-cuda.callPackage ./docker.nix {
                nix2container = self.inputs.nix2container.packages.${system}.nix2container;
              };
            }
          );

        # provide the development environment defined in shell.nix
        devShells = {
          default = pkgs-without-cuda.callPackage ./shell.nix { };
          with-cuda = pkgs-with-cuda.callPackage ./shell.nix { };
        };

        checks =
          { }
          // (nixpkgs.lib.optionalAttrs
            # wlo-classification, a dependency of this application, only runs
            # on linux
            (!pkgs-without-cuda.stdenv.isDarwin)
            {
              # run an automatic integration test through `nix flake check`
              test-service = self.inputs.openapi-checks.lib.${system}.test-service {
                service-bin = "${pkgs-without-cuda.python-kidra}/bin/python-kidra";
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

  nixConfig = {
    # additional caches for CUDA packages.
    # packages built with CUDA support are not included in the normal NixOS
    # cache, as they require dependencies distributed under unfree licenses.
    # note that, depending on the specific version of nixpkgs being used,
    # this cache may be more or less complete. the state of this cache can be
    # checked under https://hercules-ci.com/github/SomeoneSerge/nixpkgs-cuda-ci
    # (click on a particular job)
    trusted-substituters = [ "https://cuda-maintainers.cachix.org" ];
    trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };
}
