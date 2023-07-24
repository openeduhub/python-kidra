#!/bin/sh 
echo "sandbox = false" >> /etc/nix/nix.conf &&
    cd /python_kidra &&
    nix build --out-link result-link &&
    cp -f $(readlink result-link) result &&
    rm result-link
