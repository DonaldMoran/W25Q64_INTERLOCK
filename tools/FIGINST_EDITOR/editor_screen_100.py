# tools/make_editor_screen.py

import sys

# SCR # 100
     
source_lines = [
    'FORTH DEFINITIONS',
    'HEX 6 USER S0 8 USER R0 DECIMAL',
    'SP! VARIABLE SPV',
    ': .S',
    '   SP@ SPV !',
    '   CR ." <"',
    '   S0 @ SPV @ - ABS 2 / DUP .',                                        
    '   ." > "',
    '   DUP 0= IF DROP ELSE',
    '      S0 @ SPV @ DO',
    '         I @ . SPACE',
    '      2 +LOOP DROP',
    '   THEN',
    ';',
    'DECIMAL',
    'SP! .S'
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

# Save as 100.FTH
filename = "100.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
