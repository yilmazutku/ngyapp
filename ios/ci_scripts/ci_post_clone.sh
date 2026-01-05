#!/bin/sh

# Xcode Cloud post-clone script
# This script runs after the repository is cloned but before the build starts

set -e

echo "=== Running ci_post_clone.sh ==="

# Navigate to the project root (parent of ios folder)
cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "=== Installing Flutter ==="
# Clone Flutter SDK if not present
if [ ! -d "$HOME/flutter" ]; then
    git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
fi

export PATH="$PATH:$HOME/flutter/bin"

echo "=== Flutter version ==="
flutter --version

echo "=== Flutter pub get ==="
flutter pub get

echo "=== Generating iOS files ==="
flutter precache --ios
flutter build ios --config-only

echo "=== Installing CocoaPods dependencies ==="
cd ios
pod install --repo-update

echo "=== ci_post_clone.sh completed ==="

