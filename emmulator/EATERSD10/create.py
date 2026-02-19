import os
import subprocess
import shutil
import time

# Get the directory where the script is located
script_dir = os.path.dirname(os.path.abspath(__file__))

# Define the base directory relative to the script location
base_dir = os.path.join(script_dir, "four-bit-mode-msbasic")
tmp_dir = os.path.join(base_dir, "tmp")

# Change to the base directory
os.chdir(base_dir)

# Run the make.sh script
subprocess.run(["./make.sh"])

# Wait for 3 seconds to ensure the make.sh script completes
time.sleep(3)

# Define the files to copy and their destinations
files_to_copy = ["eater.bin", "eater.map"]

for filename in files_to_copy:
    source_file = os.path.join(tmp_dir, filename)
    destination_file = os.path.join(script_dir, filename)
    shutil.copy(source_file, destination_file)

# Change back to the script directory
os.chdir(script_dir)

# Open the READ_BINARY.PY process with `stdin` input
process = subprocess.Popen(["python", "read_binary.py"], stdin=subprocess.PIPE, text=True)

# Send the desired input to the process
process.communicate(input="y\n")

print("Operation completed successfully.")
