# tools/make_editor_screen.py

import sys

# SCR # 96
     
source_lines = [
    '(  STRING EDITOR COMMANDS                         WFR-79MAR24 )',
    ': N     ( FIND NEXT OCCURANCE OF PREVIOUS TEXT *)',
    '      FIND  0  M  ;',
    '',
    ': F      ( FIND OCCURANCE OF FOLLOWING TEXT *)',
    '      1  TEXT  N  ;',
    '',
    ': B      ( BACKUP CURSOR BY TEXT IN PAD *)',
    '      PAD  C@  MINUS  M  ;',
    '',
    ': X     ( DELETE FOLLOWING TEXT *)',
    '      1  TEXT  FIND  PAD  C@  DELETE  0  M  ;',
    '',
    ': TILL      ( DELETE ON CURSOR LINE, FROM CURSOR TO TEXT END *)',
    '      #LEAD  +  1  TEXT  1LINE  0=  0  ?ERROR',
    '      #LEAD  +  SWAP  -  DELETE  0  M  ;     -->'
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

# Save as 096.FTH
filename = "096.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
