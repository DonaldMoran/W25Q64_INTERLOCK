#!/bin/bash
python create.py
cp eater.h ../EMULATOR/src
rm -f *.bin *.map *.h
cd ../EMULATOR
rm -fR build
mkdir build
cd build
cmake ..
make -j4
picotool info -F
picotool load 6502emu.uf2 -f
picotool reboot
echo "Waiting for 5 seconds..."
sleep 5
echo "Done waiting!"
minicom -D /dev/ttyACM0 -b 115200
#cp 6502emu.uf2 /media/noneya/RPI-RP2/
