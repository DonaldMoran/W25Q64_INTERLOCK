#!/bin/bash

for f in *; do
    [ -f "$f" ] || continue
    upper=$(printf "%s" "$f" | tr '[:lower:]' '[:upper:]')
    if [ "$f" != "$upper" ]; then
        if [ -e "$upper" ]; then
            echo "Skipping '$f' → '$upper' (target exists)"
        else
            mv -- "$f" "$upper"
        fi
    fi
done
