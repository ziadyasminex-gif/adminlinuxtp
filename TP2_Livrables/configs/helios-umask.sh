#!/bin/bash
# umask 002 pour les membres de transport ; 027 pour les autres.
if id -nG | tr ' ' '\n' | grep -qx transport; then
    umask 002
else
    umask 027
fi
