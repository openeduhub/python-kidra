#!/bin/sh
# create a docker container that hosts the nix-based builder.
# make it persistent so that future build tasks do not start from scratch again
# create the container if it does not exist
docker run -d \
       -it \
       --mount src="$(pwd)",target=/python_kidra,type=bind \
       --name kidra-builder \
       docker.io/nixpkgs/nix-flakes:nixos-23.05

# start the container if it was stopped
docker start kidra-builder

# execute the build command
docker exec kidra-builder \
       sh /python_kidra/scripts/build_docker_using_docker.sh

# stop the builder container
docker stop kidra-builder
