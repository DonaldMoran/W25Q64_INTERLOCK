# tools/make_editor_screen.py

import sys

# SCR # 91
     
source_lines = [
    '(  LINE EDITING COMMANDS                           WFR-790105 )',
    ': R                          ( REPLACE ON LINE #-1, FROM PAD *)',
    '      PAD  1+  SWAP  -MOVE  ;',
    '',
    ': P                           ( PUT FOLLOWING TEXT ON LINE-1 *)',
    '      1  TEXT  R  ;',
    '',
    ': I                       ( INSERT TEXT FROM PAD ONTO LINE # *)',
    '      DUP  S  R  ;',
    '                            CR',
    ': TOP                    ( HOME CURSOR TO TOP LEFT OF SCREEN *)',
    '      0  R#  !  ;',
    '-->',
    '',
    '',
    ''
]

# Ensure exactly 16 lines
while len(source_lines) < 16:
    source_lines.append("")

# Format: 64 chars per line, space padded, NO newlines
data = bytearray()
for line in source_lines[:16]:
    text = line[:64]            # Truncate
    text = text.ljust(64, ' ')  # Pad with spaces
    data.extend(text.encode('ascii'))

# Save as 091.FTH
filename = "091.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
