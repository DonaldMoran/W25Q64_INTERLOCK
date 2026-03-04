#!/usr/bin/env python3
import os

for name in os.listdir("."):
    if not os.path.isfile(name):
        continue
    upper = name.upper()
    if name != upper:
        if os.path.exists(upper):
            print(f"Skipping '{name}' → '{upper}' (target exists)")
        else:
            os.rename(name, upper)
