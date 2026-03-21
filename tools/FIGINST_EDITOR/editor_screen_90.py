# tools/make_editor_screen.py

import sys

# SCR # 90
     
source_lines = [
    '(  LINE EDITING COMMANDS                          WFR-79MAY03 )',
    '',
    ': M    ( MOVE CURSOR BY SIGNED AMOUNT-1, PRINT ITS LINE *)',
    '     R#  +!  CR  SPACE  #LEAD  TYPE  5F  EMIT',
    '                        #LAG   TYPE  #LOCATE  .  DROP  ;',
    '',
    ': T    ( TYPE LINE BY #-1,  SAVE ALSO IN PAD *)',
    '     DUP  C/L  *  R#  !  DUP  H  0  M  ;',
    '',
    ': L     ( RE-LIST SCREEN *)',
    '        SCR  @  LIST  0  M  ;',
    '-->',
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

# Save as 090.FTH
filename = "090.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
