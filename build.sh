#!/bin/sh
docker run \
       --rm \
       -v .:/python_kidra \
       docker.nix-community.org/nixpkgs/nix-flakes:nixos-22.11 \
       sh /python_kidra/scripts/build_docker_using_docker.sh
