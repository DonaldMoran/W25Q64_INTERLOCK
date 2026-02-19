#!/usr/bin/env bash
set -euo pipefail

# Clean and rebuild
rm -rf build
mkdir build
cd build

cmake ..
make -j4

# Give the system a moment after the build completes
sleep 2

# Flash the Pico
picotool load 6522_smart_device.uf2

# Optional: small delay before reboot
sleep 1
picotool reboot
