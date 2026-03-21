# tools/make_editor_screen.py

import sys

# SCR # 95
     
source_lines = [
    '(  STRING EDITING COMMANDS                        WFR-79MAR24 )',
    ': 1LINE       ( SCAN LINE WITH CURSOR FOR MATCH TO PAD TEXT, *)',
    '                             ( UPDATE CURSOR, RETURN BOOLEAN *)',
    '       #LAG  PAD  COUNT  MATCH  R#   +!   ;',
    '',
    ':  FIND   ( STRING AT PAD OVER FULL SCREEN RANGE, ELSE ERROR *)',
    '     BEGIN  3FF  R#  @  <',
    '         IF  TOP  PAD  HERE  C/L  1+  CMOVE  0  ERROR  ENDIF',
    '         1LINE   UNTIL   ;',
    '',
    ': DELETE                    ( BACKWARDS AT CURSOR BY COUNT-1 *)',
    '    >R  #LAG  +  FORTH  R  -  ( SAVE BLANK FILL LOCATION )',
    '    #LAG  R MINUS  R#  +!     ( BACKUP CURSOR )',
    '    #LEAD  +  SWAP  CMOVE',
    '    R>  BLANKS  UPDATE  ;   ( FILL FROM END OF TEXT )',
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

# Save as 095.FTH
filename = "095.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
