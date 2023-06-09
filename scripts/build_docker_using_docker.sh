#!/bin/sh 
echo "sandbox = false" >> /etc/nix/nix.conf &&
    cd /python_kidra &&
    nix build &&
    mkdir results
rm results/image
cp $(readlink result) results/image
rm result
