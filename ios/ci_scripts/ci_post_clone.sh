#!/bin/sh

# Xcode Cloud post-clone script
# This script runs after the repository is cloned but before the build starts

set -e

echo "=== Running ci_post_clone.sh ==="
echo "Current directory: $(pwd)"
echo "CI_PRIMARY_REPOSITORY_PATH: $CI_PRIMARY_REPOSITORY_PATH"

# Navigate to the project root (parent of ios folder)
cd "$CI_PRIMARY_REPOSITORY_PATH"
echo "Changed to: $(pwd)"

echo "=== Installing Flutter ==="
# Clone Flutter SDK if not present
if [ ! -d "$HOME/flutter" ]; then
    echo "Cloning Flutter SDK..."
    git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
else
    echo "Flutter SDK already exists at $HOME/flutter"
fi

# Export Flutter to PATH
export PATH="$PATH:$HOME/flutter/bin"

# Also export FLUTTER_ROOT for Xcode build phases
export FLUTTER_ROOT="$HOME/flutter"

echo "=== Flutter version ==="
flutter --version

echo "=== Flutter doctor ==="
flutter doctor -v

echo "=== Disabling Flutter analytics ==="
flutter config --no-analytics

echo "=== Flutter pub get ==="
flutter pub get

echo "=== Precaching iOS artifacts ==="
flutter precache --ios

echo "=== Generating iOS build configuration ==="
flutter build ios --config-only --release --no-codesign

echo "=== Verifying Generated.xcconfig ==="
if [ -f "ios/Flutter/Generated.xcconfig" ]; then
    echo "Generated.xcconfig contents:"
    cat ios/Flutter/Generated.xcconfig
    echo ""
    
    # Verify FLUTTER_ROOT is set correctly
    if grep -q "FLUTTER_ROOT=" ios/Flutter/Generated.xcconfig; then
        echo "✓ FLUTTER_ROOT is configured"
    else
        echo "✗ WARNING: FLUTTER_ROOT not found in Generated.xcconfig"
    fi
else
    echo "✗ ERROR: Generated.xcconfig not found!"
    exit 1
fi

echo "=== Installing CocoaPods dependencies ==="
cd ios

# Clean any previous pod state
rm -rf Pods
rm -f Podfile.lock

# Set locale for CocoaPods
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Install pods
pod install --repo-update --verbose

echo "=== Verifying Pods installation ==="
if [ -f "Podfile.lock" ] && [ -d "Pods" ]; then
    echo "✓ Pods installed successfully"
else
    echo "✗ ERROR: Pods installation failed!"
    exit 1
fi

echo "=== ci_post_clone.sh completed successfully ==="
