# iOS Build & Upload Guide for TestFlight / App Store

---

## 🔥 NUCLEAR CLEAN BUILD (Use This!)

This clears EVERYTHING - Flutter, Xcode, Pods, caches, archives. Run this before every upload:

```bash
cd /Users/nilaygoktepe/Documents/ngyapp

# 1. Kill Xcode if running
killall Xcode 2>/dev/null

# 2. Clean Flutter completely
flutter clean

# 3. Delete ALL Xcode caches and derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/*
rm -rf ~/Library/Caches/com.apple.dt.Xcode

# 4. Delete local build artifacts
rm -rf build/
rm -rf ios/build/
rm -rf ios/.symlinks/
rm -rf ios/Pods/
rm -rf ios/Podfile.lock

# 5. Get fresh dependencies
flutter pub get

# 6. Fresh pod install
cd ios
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
pod install --repo-update
cd ..

# 7. Verify build number
echo "=== BUILD INFO ==="
grep "version:" pubspec.yaml
cat ios/Flutter/Generated.xcconfig | grep FLUTTER_BUILD
echo "================="
```

### One-Liner (Copy & Paste This):

```bash
cd /Users/nilaygoktepe/Documents/ngyapp && killall Xcode 2>/dev/null; flutter clean && rm -rf ~/Library/Developer/Xcode/DerivedData/* && rm -rf ~/Library/Caches/com.apple.dt.Xcode && rm -rf build/ ios/build/ ios/.symlinks/ ios/Pods/ ios/Podfile.lock && flutter pub get && cd ios && export LANG=en_US.UTF-8 && export LC_ALL=en_US.UTF-8 && pod install --repo-update && cd .. && echo "=== BUILD INFO ===" && grep "version:" pubspec.yaml && cat ios/Flutter/Generated.xcconfig | grep FLUTTER_BUILD
```

---

## After Nuclear Clean - Archive in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode (fresh start)
2. Wait for indexing to complete
3. Select **Any iOS Device (arm64)** as destination
4. **Product → Clean Build Folder** (Shift+Cmd+K)
5. **Product → Archive**
6. In Organizer: **Distribute App → App Store Connect → Upload**

---

## Version/Build Number Updates

### Edit `pubspec.yaml`:

```yaml
version: 1.0.0+5
#        │     │
#        │     └── Build number (increment for each upload)
#        └── Version name
```

**⚠️ After changing version, ALWAYS run the Nuclear Clean Build!**

---

## Why Organizer Shows Wrong Version

The Organizer shows **old cached archives**. The actual upload uses the correct version. To fix:
1. In Organizer, right-click old archives → **Delete**
2. Run Nuclear Clean Build
3. Archive fresh

---

## Signing Settings

In Xcode → Runner → Signing & Capabilities:
- ✅ Automatically manage signing
- Team: Your Apple Developer account  
- Signing Certificate: **Apple Development**

**DO NOT manually change to Distribution!**

---

## TestFlight Not Working?

1. Go to **App Store Connect → TestFlight**
2. Check which build number is there (should be latest)
3. Click the build → Complete **Export Compliance** if needed
4. Go to **Internal Testing** → Your group
5. Make sure the **latest build has a checkmark** ✅
6. On iPhone: Open TestFlight → Pull down to refresh → Install

---

## Troubleshooting

### Any weird error
Run the Nuclear Clean Build above.

### "Sandbox not in sync"
Run the Nuclear Clean Build above.

### Build number wrong
Run the Nuclear Clean Build above.

### Xcode acting weird
Run the Nuclear Clean Build above.

---

## Quick Reference

| Task | Command |
|------|---------|
| Check version | `grep "version:" pubspec.yaml` |
| Check iOS build number | `cat ios/Flutter/Generated.xcconfig \| grep FLUTTER_BUILD` |
| Increment build | Edit `pubspec.yaml`, then Nuclear Clean Build |
