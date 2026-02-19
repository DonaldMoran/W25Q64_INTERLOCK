import os
import configparser

# Function to prompt user for yes/no input
def get_yes_no_input(prompt):
    while True:
        choice = input(prompt + " [y/n]: ").lower()
        if choice == "y" or choice == "yes":
            return True
        elif choice == "n" or choice == "no":
            return False
        else:
            print("Invalid input. Please enter 'y' or 'n'.")

# Function to save user settings to the configuration file
def save_settings(config, array_name, header_file, relative_path):
    config["Settings"] = {
        "ArrayName": array_name,
        "HeaderFile": header_file,
        "RelativePath": relative_path
    }

    with open("settings.ini", "w") as configfile:
        config.write(configfile)

# Function to load saved settings from the configuration file
def load_settings(config):
    array_name = config["Settings"]["ArrayName"]
    header_file = config["Settings"]["HeaderFile"]
    relative_path = config["Settings"]["RelativePath"]
    return array_name, header_file, relative_path

config = configparser.ConfigParser()

# Check if the configuration file exists
if os.path.isfile("settings.ini"):
    use_saved_settings = get_yes_no_input("Would you like to use the previously saved settings?")
    if use_saved_settings:
        config.read("settings.ini")
        array_name, header_file, relative_path = load_settings(config)
    else:
        array_name = input("Enter the name for the array: ")
        header_file = input("Enter the header file name (without extension .h): ")
        if not header_file.endswith(".h"):
            header_file += ".h"
        relative_path = input("Enter the relative path to the binary file: ")

        save_settings(config, array_name, header_file, relative_path)
else:
    array_name = input("Enter the name for the array: ")
    header_file = input("Enter the header file name (without extension .h): ")
    if not header_file.endswith(".h"):
        header_file += ".h"
    relative_path = input("Enter the relative path to the binary file: ")

    save_settings(config, array_name, header_file, relative_path)

with open(header_file, "w") as f:
    f.write(f"unsigned char {array_name}[] = {{\n")
    with open(relative_path, "rb") as binary_file:
        byte = binary_file.read(12)  # Read 12 bytes at a time
        while byte:
            hex_values = ', '.join([f'0x{b:02X}' for b in byte])  # Convert bytes to hex strings with "0x" prefix
            f.write(hex_values + ",\n")
            byte = binary_file.read(12)  # Read next 12 bytes
    f.write("};\n")
    f.write(f"unsigned int {array_name}_len = 32768;")

