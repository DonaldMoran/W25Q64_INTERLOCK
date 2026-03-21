# tools/make_editor_screen.py

import sys

# SCR # 93
     
source_lines = [
    '(  DOUBLE NUMBER SUPPORT                          WFR-80APR24 )',
    '(  OPERATES ON 32 BIT DOUBLE NUMBERS   OR TWO 16-BIT INTEGERS )',
    'FORTH DEFINITIONS',
    '',
    ': 2DROP   DROP    DROP  ;  ( DROP DOUBLE NUMBER )',
    '',
    ': 2DUP    OVER    OVER  ;  ( DUPLICATE A DOUBLE NUMBER )',
    '',
    ': 2SWAP   ROT     >R    ROT   R>  ;',
    '        ( BRING SECOND DOUBLE TO TOP OF STACK )',
    'EDITOR DEFINITIONS  -->',
    '',
    '',
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

# Save as 093.FTH
filename = "093.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
