# tools/make_editor_screen.py

import sys

# SCR # 88
     
source_lines = [
    '(  LINE EDITOR                                    WFR-79MAY03 )',
    'VOCABULARY  EDITOR  IMMEDIATE    HEX',
    ': WHERE                  ( PRINT SCREEN # AND IMAGE OF ERROR *)',
    '    DUP  B/SCR  /  DUP  SCR  !  ." SCR # "  DECIMAL  .',
    '    SWAP  C/L  /MOD  C/L  *  ROT  BLOCK  +  CR  C/L  TYPE',
    '    CR  HERE  C@  -  SPACES  5E EMIT  [COMPILE] EDITOR  QUIT  ;',
    '',
    'EDITOR  DEFINITIONS',
    ': #LOCATE                    ( LEAVE CURSOR OFFSET-2, LINE-1 *)',
    '        R#  @  C/L  /MOD  ;',
    ': #LEAD                 ( LINE ADDRESS-2, OFFSET-1 TO CURSOR *)',
    '        #LOCATE  LINE  SWAP  ;',
    ': #LAG              ( CURSOR ADDRESS-2, COUNT-1 AFTER CURSOR *)',
    '        #LEAD  DUP  >R  +  C/L  R>  -  ;',
    ': -MOVE      ( MOVE IN BLOCK BUFFER ADDR FROM-2,  LINE TO-1 *)',
    '        LINE  C/L  CMOVE  UPDATE  ;  -->'
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

# Save as 088.FTH
filename = "088.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
