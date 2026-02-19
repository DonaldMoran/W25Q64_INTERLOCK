# * Examples:
# * bintomon myprog.bin
# * bintomon -v -f myprog.bin
# * bintomon -l 0x300 myprog.bin
# * bintomon -l 0x280 -r 0x300 myprog.bin
import argparse
import struct

def usage(name):
    print(f"usage: {name} [-h] [-v] [-f] [-1] [-2] [-b <Bytes>] [-l <LoadAddress>] [-r <RunAddress>] [-c <Fill>] <Filename>")

def show_help(name):
    usage(name)
    print("""
-h  Show help info and exit.
-v  Show verbose output.
-f  Get load address and length from first 4 bytes of file.
-1  Use Apple 1 Woz Monitor format.
-2  Use Apple II Monitor format.
-b <Bytes>  Specify how many data bytes per line (defaults to 8).
-l <LoadAddress>  Specify beginning load address (defaults to 0x280).
-r <RunAddress>  Specify program run/start address (defaults to load address).
-c <Fill>  Skip lines containing the specified fill character.

Addresses can be specified in decimal or hex (prefixed with 0x). A
monitor run or go command is sent at the end of the file. If run address
is - then the run command is not generated in the output.
""")

def all_fill(bytes, fill):
    return all(b == fill for b in bytes)

def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('-h', action='store_true')
    parser.add_argument('-v', action='store_true')
    parser.add_argument('-f', action='store_true')
    parser.add_argument('-1', dest='apple1', action='store_true')
    parser.add_argument('-2', dest='apple2', action='store_true')
    parser.add_argument('-b', type=int, default=8)
    parser.add_argument('-l', type=lambda x: int(x, 0), default=0x280)
    parser.add_argument('-r', type=str, default=None)
    parser.add_argument('-c', type=lambda x: int(x, 0), default=None)
    parser.add_argument('filename', nargs='?')
    args = parser.parse_args()

    if args.h:
        show_help(parser.prog)
        return

    if not args.filename:
        usage(parser.prog)
        return

    load_address = args.l
    run_address = args.r
    if run_address is not None:
        if run_address == '-':
            run_address = -1
        else:
            run_address = int(run_address, 0)
    else:
        run_address = -2

    bytes_per_line = args.b
    skip_fill = args.c is not None
    fill_char = args.c if skip_fill else 0

    with open(args.filename, 'rb') as file:
        if args.f:
            load_address = struct.unpack('<H', file.read(2))[0]
            length = struct.unpack('<H', file.read(2))[0]
        else:
            length = -1

        if run_address == -2:
            run_address = load_address

        address = load_address
        print_address = True
        printed = 0

        while True:
            bytes = file.read(bytes_per_line)
            if not bytes:
                break

            if skip_fill and all_fill(bytes, fill_char):
                address += len(bytes)
                print_address = True
            else:
                if print_address:
                    print(f"{address:04X}:", end=' ')
                print_address = False
                for b in bytes:
                    print(f"{b:02X}", end=' ')
                    address += 1
                    printed += 1
                    if printed % bytes_per_line == 0:
                        print()
                        print_address = True
                        printed = 0
                if printed % bytes_per_line != 0:
                    print()

        if run_address != -1:
            if args.apple1:
                print(f"{run_address:04X}R")
            if args.apple2:
                print(f"{run_address:04X}G")

        if args.v:
            print(f"Load address: ${load_address:04X}")
            if run_address != -1:
                print(f"Run address: ${run_address:04X}")
            else:
                print("Run address: none")
            print(f"Last address: ${address - 1:04X}")
            if skip_fill:
                print(f"Skipping fill character: ${fill_char:02X}")
            if length != -1:
                print(f"Length (from file): ${length:04X} ({length} bytes)")
            print(f"Length (calculated): ${address - load_address:04X} ({address - load_address} bytes)")

        if length != -1 and address != load_address + length:
            print(f"Note: Last address does not match load address + length: ${load_address + length:04X}")

if __name__ == "__main__":
    main()
