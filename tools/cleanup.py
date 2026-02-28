import serial
import sys
import time

def delete_hex(port, hex_name):
    try:
        # Convert hex string to bytes
        filename = bytes.fromhex(hex_name)
        print(f"Targeting filename: {filename}")
        
        ser = serial.Serial(port, 115200, timeout=1)
        
        # Clear buffer
        ser.read_all()
        
        # Construct CMD_FS_REMOVE (0x16) packet
        # Format: [CMD] [LEN] [DATA...]
        cmd_id = b'\x16'
        length = len(filename).to_bytes(1, 'little')
        packet = cmd_id + length + filename
        
        print(f"Sending packet: {packet.hex()}")
        ser.write(packet)
        
        # Read response: [STATUS] [LEN_LO] [LEN_HI]
        resp = ser.read(3)
        if len(resp) == 3:
            status = resp[0]
            print(f"Status: 0x{status:02X} ({'OK' if status == 0 else 'FAIL'})")
        else:
            print("No response from Pico")
            
        ser.close()
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 cleanup.py <port> <hex_filename>")
        print("Example: python3 cleanup.py /dev/ttyACM0 224142432E5322")
    else:
        delete_hex(sys.argv[1], sys.argv[2])
