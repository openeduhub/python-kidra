#!/bin/sh 
echo "sandbox = false" >> /etc/nix/nix.conf &&
    cd /python-kidra &&
    nix build --out-link result-link &&

cp -f $(readlink result-link) result
rm result-link
