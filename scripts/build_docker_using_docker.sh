#!/bin/sh 
echo "sandbox = false" >> /etc/nix/nix.conf &&
    cd /python_ki_hydra &&
    nix build &&
    mkdir results &&
    cp $(readlink result) results/image &&
    rm result
