#!/bin/sh 
echo "sandbox = false" >> /etc/nix/nix.conf &&
    cd /python_kidra &&
    nix build --out-link result-link

rm result
cp $(readlink result-link) result
rm result-link
