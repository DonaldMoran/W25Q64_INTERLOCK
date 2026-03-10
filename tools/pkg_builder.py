#!/usr/bin/env python3
"""
pkg_builder.py - Collects UF2 and BIN files from specified locations,
renames BIN files to uppercase, creates a ZIP of the transient_cmds folder,
and leaves the UF2 files alongside the transient_cmds.zip in the version directory.
"""

import os
import shutil
import zipfile
from pathlib import Path

def get_version_from_user():
    """Prompt user for version number and validate input."""
    while True:
        version = input("Enter version number (e.g., 1.0, 2.1, 42): ").strip()
        if version:
            return version
        print("Version number cannot be empty. Please try again.")

def cleanup_previous_builds(pkg_build_dir, current_version):
    """
    Remove any previously created version directories,
    except the current version we're about to build.
    """
    print("\n--- Cleaning up previous builds ---")
    
    # Find all version_* directories
    version_dirs = list(pkg_build_dir.glob("version_*"))
    
    items_removed = 0
    
    # Remove old version directories
    for dir_path in version_dirs:
        if dir_path.name != f"version_{current_version}":
            try:
                shutil.rmtree(dir_path)
                print(f"✓ Removed old directory: {dir_path}")
                items_removed += 1
            except Exception as e:
                print(f"✗ Error removing directory {dir_path}: {e}")
    
    # Also check if the current version directory already exists and remove it
    current_dir = pkg_build_dir / f"version_{current_version}"
    if current_dir.exists():
        try:
            shutil.rmtree(current_dir)
            print(f"✓ Removed existing directory for version {current_version}")
            items_removed += 1
        except Exception as e:
            print(f"✗ Error removing current version directory: {e}")
    
    if items_removed == 0:
        print("! No previous builds found to clean up.")
    else:
        print(f"✓ Cleanup complete. Removed {items_removed} item(s).")

def create_output_directory(base_dir, version):
    """Create the versioned output directory."""
    output_dir = base_dir / f"version_{version}"
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir

def collect_uf2_files(output_dir):
    """Collect all .uf2 files from specified locations."""
    # Define source directories for UF2 files (relative to project root, one level up from tools)
    uf2_sources = [
        Path("../build"),
        Path("../emmulator/EMULATOR/build")  # Note: 'emmulator' spelling as provided
    ]
    
    uf2_files_copied = []
    
    for source_dir in uf2_sources:
        if source_dir.exists() and source_dir.is_dir():
            # Find all .uf2 files in the directory
            for uf2_file in source_dir.glob("*.uf2"):
                try:
                    dest_path = output_dir / uf2_file.name
                    shutil.copy2(uf2_file, dest_path)
                    uf2_files_copied.append(str(uf2_file))
                    print(f"✓ Copied UF2: {uf2_file} -> {dest_path}")
                except Exception as e:
                    print(f"✗ Error copying {uf2_file}: {e}")
        else:
            print(f"! Source directory not found: {source_dir}")
    
    return uf2_files_copied

def collect_and_zip_bin_files(output_dir):
    """
    Collect all .bin files from 6502/ca65/commands and subfolders,
    rename to uppercase, create a ZIP of the transient_cmds folder,
    then delete the source folder.
    """
    source_dir = Path("../6502/ca65/commands")
    
    # Create transient_cmds subfolder
    transient_cmds_dir = output_dir / "transient_cmds"
    transient_cmds_dir.mkdir(exist_ok=True)
    
    bin_files_copied = []
    
    if source_dir.exists() and source_dir.is_dir():
        # Recursively find all .bin files
        for bin_file in source_dir.rglob("*.bin"):
            try:
                # Create uppercase filename with uppercase extension
                uppercase_name = bin_file.stem.upper() + ".BIN"
                dest_path = transient_cmds_dir / uppercase_name
                
                # Copy and rename
                shutil.copy2(bin_file, dest_path)
                bin_files_copied.append(str(bin_file))
                print(f"✓ Copied BIN: {bin_file} -> {dest_path}")
            except Exception as e:
                print(f"✗ Error copying {bin_file}: {e}")
        
        # Now create a ZIP of the transient_cmds folder
        if bin_files_copied:
            print(f"\n--- Creating transient_cmds.zip ---")
            zip_path = output_dir / "transient_cmds.zip"
            
            try:
                with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                    for root, dirs, files in os.walk(transient_cmds_dir):
                        for file in files:
                            file_path = Path(root) / file
                            # Store files with relative path from transient_cmds_dir
                            arcname = file_path.relative_to(transient_cmds_dir)
                            zipf.write(file_path, arcname)
                
                print(f"✓ Created ZIP: {zip_path}")
                
                # Delete the transient_cmds folder
                print(f"--- Removing transient_cmds folder ---")
                shutil.rmtree(transient_cmds_dir)
                print(f"✓ Removed folder: {transient_cmds_dir}")
                
            except Exception as e:
                print(f"✗ Error creating transient_cmds.zip: {e}")
        else:
            print("! No BIN files found to zip.")
    else:
        print(f"! Source directory not found: {source_dir}")
    
    return bin_files_copied

def main():
    """Main execution function."""
    print("=" * 50)
    print("Package Builder Tool")
    print("=" * 50)
    
    # Get version from user
    version = get_version_from_user()
    
    # The script is already in the tools directory, so we just need pkg_build subfolder
    pkg_build_dir = Path("pkg_build")
    
    # Ensure pkg_build directory exists
    pkg_build_dir.mkdir(parents=True, exist_ok=True)
    
    # Clean up any previous builds (including current version if it exists)
    cleanup_previous_builds(pkg_build_dir, version)
    
    # Create fresh versioned output directory
    output_dir = create_output_directory(pkg_build_dir, version)
    print(f"\nOutput directory created: {output_dir}")
    
    # Collect UF2 files
    print("\n--- Collecting UF2 files ---")
    uf2_files = collect_uf2_files(output_dir)
    
    # Collect, rename, and zip BIN files (this will create transient_cmds.zip and delete the folder)
    print("\n--- Collecting and processing BIN files ---")
    bin_files = collect_and_zip_bin_files(output_dir)
    
    # Summary
    print("\n" + "=" * 50)
    print("Collection Summary")
    print("=" * 50)
    print(f"Version: {version}")
    print(f"Output directory: {output_dir}")
    print(f"UF2 files collected: {len(uf2_files)}")
    print(f"BIN files processed: {len(bin_files)}")
    
    # Show final directory structure
    print("\n--- Final directory contents ---")
    if output_dir.exists():
        for item in sorted(output_dir.iterdir()):
            if item.is_file():
                print(f"  📄 {item.name}")
            else:
                print(f"  📁 {item.name}/")
    
    if uf2_files or bin_files:
        print(f"\n✓ Build package version_{version} completed successfully!")
        print(f"  Files are in: {output_dir}")
    else:
        print("\n! No files were collected. Nothing to package.")
        # Remove empty directory
        try:
            output_dir.rmdir()
            print(f"Removed empty directory: {output_dir}")
        except:
            pass

if __name__ == "__main__":
    main()
