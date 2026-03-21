# tools/make_editor_screen.py

import sys

# SCR # 89
     
source_lines = [
    '(  LINE EDITING COMMANDS                          WFR-79MAY03 )',
    ': H                              ( HOLD NUMBERED LINE AT PAD *)',
    '      LINE  PAD  1+  C/L  DUP  PAD  C!  CMOVE  ;',
    '',
    ': E                               ( ERASE LINE-1 WITH BLANKS *)',
    '      LINE  C/L  BLANKS  UPDATE  ;',
    '',
    ': S                             ( SPREAD MAKING LINE # BLANK *)',
    '      DUP  1  -  ( LIMIT )  0E ( FIRST TO MOVE )',
    '      DO  I  LINE  I  1+  -MOVE  -1  +LOOP  E  ;',
    '',
    ': D                         ( DELETE LINE-1, BUT HOLD IN PAD *)',
    '      DUP  H  0F  DUP  ROT',
    '      DO  I  1+  LINE  I  -MOVE  LOOP  E  ;',
    '',
    '-->'
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

# Save as 089.FTH
filename = "089.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
