#!/usr/bin/env python3
"""
Cross-Platform Build Script for CodeFlow Companion Executable
Bundles codeflow_streamer.py into a standalone zero-dependency executable
using PyInstaller for Windows, Linux, and macOS.
"""

import os
import platform
import shutil
import subprocess
import sys
import tarfile
import zipfile


def get_platform_info():
    system = platform.system().lower()
    machine = platform.machine().lower()
    if machine in ['x86_64', 'amd64']:
        arch = 'x64'
    elif machine in ['arm64', 'aarch64']:
        arch = 'arm64'
    else:
        arch = machine
    return system, arch


def build():
    system, arch = get_platform_info()
    print("=" * 60)
    print(f"Building CodeFlow Companion Standalone Executable")
    print(f"Target Platform: {system}-{arch}")
    print("=" * 60)

    # Change to script directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    # Check PyInstaller availability
    try:
        import PyInstaller
        print(f"Using PyInstaller v{PyInstaller.__version__}")
    except ImportError:
        print("PyInstaller not found in current environment. Installing...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pyinstaller"])

    # Run PyInstaller
    spec_path = os.path.join(script_dir, "codeflow_companion.spec")
    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--clean",
        "--noconfirm",
        spec_path,
    ]
    print(f"Running command: {' '.join(cmd)}")
    subprocess.check_call(cmd)

    dist_dir = os.path.join(script_dir, "dist")
    binary_name = "codeflow-companion.exe" if system == "windows" else "codeflow-companion"
    source_binary = os.path.join(dist_dir, binary_name)

    if not os.path.exists(source_binary):
        raise FileNotFoundError(f"Expected output executable not found: {source_binary}")

    # Create release bundle archive
    release_dir = os.path.join(script_dir, "release")
    os.makedirs(release_dir, exist_ok=True)

    bundle_base_name = f"codeflow-companion-{system}-{arch}"
    if system == "windows":
        archive_path = os.path.join(release_dir, f"{bundle_base_name}.zip")
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(source_binary, arcname="codeflow-companion.exe")
            readme_path = os.path.join(script_dir, "README.md")
            if os.path.exists(readme_path):
                z.write(readme_path, arcname="README.txt")
        print(f"\n[SUCCESS] Windows ZIP bundle created: {archive_path}")
        # Also copy direct .exe for users who want single-click download
        direct_exe = os.path.join(release_dir, f"{bundle_base_name}.exe")
        shutil.copyfile(source_binary, direct_exe)
        print(f"[SUCCESS] Standalone EXE copied: {direct_exe}")

    else:
        archive_path = os.path.join(release_dir, f"{bundle_base_name}.tar.gz")
        with tarfile.open(archive_path, "w:gz") as tar:
            tar.add(source_binary, arcname="codeflow-companion")
            readme_path = os.path.join(script_dir, "README.md")
            if os.path.exists(readme_path):
                tar.add(readme_path, arcname="README.txt")
        print(f"\n[SUCCESS] Linux/macOS Tarball created: {archive_path}")
        # Also keep raw binary
        direct_bin = os.path.join(release_dir, bundle_base_name)
        shutil.copyfile(source_binary, direct_bin)
        os.chmod(direct_bin, 0o755)
        print(f"[SUCCESS] Standalone executable copied: {direct_bin}")

    print("\nBuild completed successfully!")


if __name__ == "__main__":
    try:
        build()
    except Exception as e:
        print(f"\n[ERROR] Build failed: {e}", file=sys.stderr)
        sys.exit(1)
