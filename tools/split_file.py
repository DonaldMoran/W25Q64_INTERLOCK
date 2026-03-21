# split_file.py
#
# Usage:
#   python split_file.py main.c 5000
#
# This will split main.c into chunks of 5000 characters each:
#   part1.txt, part2.txt, part3.txt, ...

import sys
import os

def split_file(filename, chunk_size):
    with open(filename, "r", encoding="utf-8", errors="ignore") as f:
        data = f.read()

    total = len(data)
    part = 1
    start = 0

    while start < total:
        end = start + chunk_size
        chunk = data[start:end]

        outname = f"part{part}.txt"
        with open(outname, "w", encoding="utf-8") as out:
            out.write(chunk)

        print(f"Wrote {outname} ({len(chunk)} chars)")
        part += 1
        start = end

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python split_file.py <filename> <chunk_size>")
        sys.exit(1)

    filename = sys.argv[1]
    chunk_size = int(sys.argv[2])

    if not os.path.exists(filename):
        print("File not found:", filename)
        sys.exit(1)

    split_file(filename, chunk_size)
