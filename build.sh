#!/bin/sh
docker run --rm -v .:/python_ki_hydra docker.nix-community.org/nixpkgs/nix-flakes sh /python_ki_hydra/scripts/build_docker_using_docker.sh
