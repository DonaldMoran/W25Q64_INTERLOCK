import sys

# Minimal FIG-Forth Line Editor
# Fits on Screen 1.
# Usage:
#   L       - List current screen
#   n T     - Type line n
#   n P txt - Put 'txt' on line n (e.g., 0 P : HI ." HELLO" ; )
#   WIPE    - Clear screen
#   N / B   - Next / Back screen

source_lines = [
    "( MINIMAL SCREEN EDITOR )",
    "DECIMAL",
    ": TEXT ( c -- ) HERE C/L 1+ BLANKS WORD",
    "       HERE PAD C/L 1+ CMOVE ;",
    ": LINE ( n -- addr ) SCR @ (LINE) DROP ;",
    ": P ( n -- ) 1 TEXT PAD COUNT ROT LINE SWAP CMOVE UPDATE ;",
    ": T ( n -- ) LINE C/L -TRAILING TYPE CR ;",
    ": L SCR @ LIST ;",
    ": N SCR @ 1+ SCR ! L ;",
    ": B SCR @ 1- SCR ! L ;",
    ": WIPE FORTH DEFINITIONS CURRENT @ CONTEXT !",
    "       SCR @ BLOCK 1024 BLANKS UPDATE ;",
    "FORTH DEFINITIONS",
    "DECIMAL",
    ";S",
    "" 
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

# Save as 001.FTH
filename = "001.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
