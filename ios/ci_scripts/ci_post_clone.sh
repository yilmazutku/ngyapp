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

# ---------------------------------------------------------------------------
# Build numarası
# ---------------------------------------------------------------------------
# Xcode Cloud her koşuda CI_BUILD_NUMBER'i bir artirir. Bunu pubspec'teki
# numaranin uzerine eklersek her kosu, hem bir oncekinden hem de pubspec'teki
# degerden kesinlikle buyuk bir numara uretir. Boylece App Store Connect'in
# "build numarasi daha yuksek olmali" kurali kendiliginden saglanir ve her
# yukleme oncesi pubspec.yaml'a dokunmak gerekmez.
#
# Xcode Cloud disinda (yerel build) CI_BUILD_NUMBER tanimsizdir; o durumda
# surum oldugu gibi pubspec.yaml'dan gelir.
BUILD_NUMBER_ARG=""
if [ -n "$CI_BUILD_NUMBER" ]; then
    PUBSPEC_BUILD_NUMBER=$(grep '^version:' pubspec.yaml | sed 's/.*+//' | tr -d '[:space:]')
    case "$PUBSPEC_BUILD_NUMBER" in
        ''|*[!0-9]*)
            echo "ERROR: pubspec.yaml icindeki build numarasi okunamadi: '$PUBSPEC_BUILD_NUMBER'"
            exit 1
            ;;
    esac
    RESOLVED_BUILD_NUMBER=$((PUBSPEC_BUILD_NUMBER + CI_BUILD_NUMBER))
    echo "Build numarasi: pubspec $PUBSPEC_BUILD_NUMBER + CI_BUILD_NUMBER $CI_BUILD_NUMBER = $RESOLVED_BUILD_NUMBER"
    BUILD_NUMBER_ARG="--build-number=$RESOLVED_BUILD_NUMBER"
else
    echo "CI_BUILD_NUMBER tanimsiz (yerel build): surum pubspec.yaml'dan alinacak"
fi

echo "=== Generating iOS build configuration ==="
flutter build ios --config-only --release --no-codesign $BUILD_NUMBER_ARG

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

    # Sürümü elle yazma: pubspec.yaml tek kaynak olmalı. Sabit bir değer
    # yazıldığında App Store Connect "build numarası daha yüksek olmalı" diyerek
    # yüklemeyi reddedebiliyor. Generated.xcconfig yukarıda doğrulandı, değerleri
    # oradan oku.
    EXPORT_BUILD_NAME=$(grep '^FLUTTER_BUILD_NAME=' ios/Flutter/Generated.xcconfig | cut -d= -f2-)
    EXPORT_BUILD_NUMBER=$(grep '^FLUTTER_BUILD_NUMBER=' ios/Flutter/Generated.xcconfig | cut -d= -f2-)
    if [ -z "$EXPORT_BUILD_NAME" ] || [ -z "$EXPORT_BUILD_NUMBER" ]; then
        echo "ERROR: Generated.xcconfig içinde sürüm bilgisi bulunamadı!"
        exit 1
    fi
    echo "Sürüm pubspec'ten alındı: $EXPORT_BUILD_NAME+$EXPORT_BUILD_NUMBER"

    cat > ios/Flutter/flutter_export_environment.sh <<ENVEOF
#!/bin/sh
export FLUTTER_ROOT="$HOME/flutter"
export FLUTTER_APPLICATION_PATH="$CI_PRIMARY_REPOSITORY_PATH"
export FLUTTER_TARGET="lib/main.dart"
export FLUTTER_BUILD_DIR=build
export FLUTTER_BUILD_NAME=$EXPORT_BUILD_NAME
export FLUTTER_BUILD_NUMBER=$EXPORT_BUILD_NUMBER
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
