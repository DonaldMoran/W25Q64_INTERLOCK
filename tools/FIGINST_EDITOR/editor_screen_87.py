# tools/make_editor_screen.py

import sys


#                                  LINE EDITOR


#     This is a sample editor, compatible with the fig-FORTH model and 
#     simple terminal devices.  The line and screen editing functions are 
#     portable.  The code definition for the string MATCH could be written 
#     high level or translated.
     
source_lines = [
    ' (  TEXT,  LINE                                    WFR-79MAY01 )',
    ' FORTH  DEFINITIONS   HEX',
    ' : TEXT                        ( ACCEPT FOLLOWING TEXT TO PAD *)',
    '      HERE  C/L  1+   BLANKS  WORD  HERE  PAD  C/L  1+  CMOVE  ;',
    '',
    ' : LINE              ( RELATIVE TO SCR, LEAVE ADDRESS OF LINE *)',
    '       DUP  FFF0  AND  17  ?ERROR   ( KEEP ON THIS SCREEN )',
    '       SCR  @  (LINE)  DROP  ;',
    ' -->',
    '',
    '',
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

# Save as 087.FTH
filename = "087.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
