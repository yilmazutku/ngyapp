# Windows Installer Creation Guide

This directory contains scripts and configuration files to create a Windows installer for your Flutter application.

## Prerequisites

1. **Flutter SDK**: Make sure you have Flutter SDK installed and configured for Windows development.
   - Run `flutter doctor` to check your setup.
   - Run `flutter config --enable-windows-desktop` to enable Windows desktop support if not already enabled.

2. **NSIS (Nullsoft Scriptable Install System)**: You need NSIS to create the installer.
   - Download and install NSIS from [https://nsis.sourceforge.io/Download](https://nsis.sourceforge.io/Download)
   - Add the NSIS installation directory to your PATH environment variable.

3. **Visual Studio**: Make sure Visual Studio with C++ desktop development tools is installed.

## Files in this Directory

- `installer.nsi`: The NSIS script that defines how the installer will be created.
- `license.txt`: The license agreement displayed during installation.
- `build_installer.bat`: A batch script that automates the build and installer creation process.
- `setup_build_env.ps1`: A PowerShell script to set up the build environment and fix network issues.

## Network Issues

If you're experiencing network problems during the build process (especially with Firebase dependencies), run the PowerShell script as administrator:

1. Right-click on `setup_build_env.ps1` and select "Run as Administrator".
2. The script will:
   - Check for internet connectivity
   - Set up proxy configuration if needed
   - Configure Flutter for better network reliability
   - Fix Firebase connectivity issues

## How to Create the Installer

### Option 1: Using the Batch Script (Recommended)

1. Open a Command Prompt or PowerShell window.
2. Navigate to the installer directory.
3. Run the `build_installer.bat` script:
   ```
   build_installer.bat
   ```
   This script will:
   - Build the Flutter application for Windows in release mode
   - Create the installer using NSIS

### Option 2: Manual Process

1. Build the Flutter application:
   ```
   flutter clean
   flutter build windows --release
   ```

2. Run NSIS to create the installer:
   ```
   cd installer
   makensis installer.nsi
   ```

## Customizing the Installer

You can customize the installer by editing the `installer.nsi` file:

- Change application details like name, version, and publisher.
- Modify the installation directory.
- Add or remove installer pages.
- Change shortcut creation settings.

## Troubleshooting

- If you encounter errors during the Flutter build, make sure all Flutter dependencies are properly installed.
- If NSIS reports errors, check that your `installer.nsi` file is correctly formatted.
- Make sure all paths in the NSIS script are correct relative to the script location.
- For network-related issues, run the `setup_build_env.ps1` script as administrator.

## Custom Branding

To customize the installer with your branding:

1. Create a bitmap image (493x312 pixels) for the installer welcome/finish pages.
2. Name it `installer_welcome.bmp` and place it in this directory.
3. Replace the app icon in `..\windows\runner\resources\app_icon.ico` with your own icon. 