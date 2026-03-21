# tools/make_editor_screen.py

import sys

# SCR # 92
     
# ~ source_lines = [
    # ~ '(  SCREEN EDITING COMMANDS                        WFR-79APR27 )',
    # ~ ': CLEAR                           ( CLEAR SCREEN BY NUMBER-1 *)',
    # ~ '      SCR  !  10  0  DO  FORTH  I  EDITOR  E  LOOP  ;',
    # ~ '',
    # ~ ': FLUSH                   ( WRITE ALL UPDATED BLOCKS TO DISC *)',  << This flush is faster but neglidgeable and it is also less robust than the default.
    # ~ '    [  LIMIT  FIRST  -  B/BUF  4  +  /  ]  ( NUMBER OF BUFFERS)',
    # ~ '    LITERAL  0  DO  7FFF  BUFFER  DROP  LOOP  ;',
    # ~ '',
    # ~ ': COPY                   ( DUPLICATE SCREEN-2, ONTO SCREEN-1 *)',
    # ~ '   B/SCR  *  OFFSET  @  +  SWAP  B/SCR  *  B/SCR  OVER  +  SWAP',
    # ~ '   DO  DUP  FORTH  I  BLOCK  2  -  !  1+   UPDATE  LOOP',
    # ~ '   DROP  FLUSH  ;',
    # ~ '-->',
    # ~ '',
    # ~ '',
    # ~ ''
# ~ ]

source_lines = [
    '(  SCREEN EDITING COMMANDS                        WFR-79APR27 )',
    ': CLEAR                           ( CLEAR SCREEN BY NUMBER-1 *)',
    '      SCR  !  10  0  DO  FORTH  I  EDITOR  E  LOOP  ;',
    '',
    '',
    '',
    '',
    '',
    ': COPY                   ( DUPLICATE SCREEN-2, ONTO SCREEN-1 *)',
    '   B/SCR  *  OFFSET  @  +  SWAP  B/SCR  *  B/SCR  OVER  +  SWAP',
    '   DO  DUP  FORTH  I  BLOCK  2  -  !  1+   UPDATE  LOOP',
    '   DROP  FLUSH  ;',
    '-->',
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

# Save as 092.FTH
filename = "092.FTH"
with open(filename, "wb") as f:
    f.write(data)

print(f"Created {filename} (1024 bytes). Ready to transfer.")
