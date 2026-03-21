# tools/make_editor_screen.py

import sys

# SCR # 97
     
source_lines = [
    "(  STRING EDITOR COMMANDS                         WFR-79MAR23 )",
    ": C        ( SPREAD AT CURSOR AND COPY IN THE FOLLOWING TEXT *)",
    "    1  TEXT  PAD  COUNT",
    "    #LAG  ROT  OVER  MIN  >R",
    "    FORTH  R  R#  +!  ( BUMP CURSOR )",
    "    R  -  >R          ( CHARS TO SAVE )",
    "    DUP  HERE  R  CMOVE  ( FROM OLD CURSOR TO HERE )",
    "    HERE  #LEAD  +  R>  CMOVE  ( HERE TO CURSOR LOCATION )",
    "    R>  CMOVE  UPDATE   ( PAD TO OLD CURSOR )",
    "    0  M  ( LOOK AT NEW LINE )  ;",
    "FORTH  DEFINITIONS   DECIMAL",
    "LATEST   12  +ORIGIN  !   ( TOP NFA )",
    "HERE     28  +ORIGIN  !   ( FENCE )",
    "HERE     30  +ORIGIN  !   ( DP )",
    "'  EDITOR  6  +   32  +ORIGIN  !  ( VOC-LINK )",
    "HERE  FENCE   !      ;S"
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

# Save as 097.FTH
filename = "097.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
