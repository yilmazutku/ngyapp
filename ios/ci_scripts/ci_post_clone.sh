#!/bin/sh

# Xcode Cloud post-clone script for Flutter
# Downloads the Flutter SDK, generates Xcode build config, and installs pods.

set -e

echo "=== ci_post_clone.sh ==="
echo "CI_PRIMARY_REPOSITORY_PATH: $CI_PRIMARY_REPOSITORY_PATH"

cd "$CI_PRIMARY_REPOSITORY_PATH"
echo "Working directory: $(pwd)"

# ---------------------------------------------------------------------------
# 1. Install Flutter SDK (download pre-built archive – avoids git clone bugs)
# ---------------------------------------------------------------------------
FLUTTER_VERSION="3.41.0"

if [ ! -d "$HOME/flutter" ]; then
    echo "=== Downloading Flutter $FLUTTER_VERSION ==="

    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        ARCHIVE_NAME="flutter_macos_arm64_${FLUTTER_VERSION}-stable.zip"
    else
        ARCHIVE_NAME="flutter_macos_${FLUTTER_VERSION}-stable.zip"
    fi
    FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/${ARCHIVE_NAME}"

    echo "Downloading $FLUTTER_URL ..."
    curl -sLO "$FLUTTER_URL"
    echo "Extracting Flutter SDK..."
    unzip -oq "$ARCHIVE_NAME" -d "$HOME"
    rm -f "$ARCHIVE_NAME"
    echo "Flutter SDK installed to $HOME/flutter"
else
    echo "Flutter SDK already exists at $HOME/flutter"
fi

export PATH="$PATH:$HOME/flutter/bin"
export FLUTTER_ROOT="$HOME/flutter"

echo "=== Flutter version ==="
flutter --version

echo "=== Disabling analytics ==="
flutter config --no-analytics 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Fetch packages and generate Xcode build configuration
# ---------------------------------------------------------------------------
echo "=== flutter pub get ==="
flutter pub get

echo "=== Precaching iOS artifacts ==="
flutter precache --ios

echo "=== Generating iOS build configuration ==="
flutter build ios --config-only --release --no-codesign

# Verify Generated.xcconfig
if [ -f "ios/Flutter/Generated.xcconfig" ]; then
    echo "Generated.xcconfig OK"
    cat ios/Flutter/Generated.xcconfig
else
    echo "ERROR: Generated.xcconfig was not created!"
    exit 1
fi

# Verify flutter_export_environment.sh
if [ -f "ios/Flutter/flutter_export_environment.sh" ]; then
    echo "flutter_export_environment.sh OK"
else
    echo "WARNING: flutter_export_environment.sh missing – creating manually"
    cat > ios/Flutter/flutter_export_environment.sh <<ENVEOF
#!/bin/sh
export FLUTTER_ROOT="$HOME/flutter"
export FLUTTER_APPLICATION_PATH="$CI_PRIMARY_REPOSITORY_PATH"
export FLUTTER_TARGET="lib/main.dart"
export FLUTTER_BUILD_DIR=build
export FLUTTER_BUILD_NAME=1.0.1
export FLUTTER_BUILD_NUMBER=8
export DART_OBFUSCATION=false
export TRACK_WIDGET_CREATION=true
export TREE_SHAKE_ICONS=true
export PACKAGE_CONFIG="$CI_PRIMARY_REPOSITORY_PATH/.dart_tool/package_config.json"
ENVEOF
    chmod +x ios/Flutter/flutter_export_environment.sh
fi

# ---------------------------------------------------------------------------
# 3. Install CocoaPods
# ---------------------------------------------------------------------------
echo "=== Installing CocoaPods dependencies ==="
cd ios

rm -rf Pods
rm -f Podfile.lock

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

pod install --repo-update

if [ -f "Podfile.lock" ] && [ -d "Pods" ]; then
    echo "Pods installed successfully"
else
    echo "ERROR: Pods installation failed!"
    exit 1
fi

echo "=== ci_post_clone.sh completed ==="
