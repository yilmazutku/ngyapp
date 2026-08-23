# Google Play Store Submission Checklist

## Prerequisites

- [ ] Google Play Developer account ($25 one-time fee) — https://play.google.com/console/signup
- [ ] Google account linked to the developer console
- [ ] Privacy policy hosted online (already done: https://utkuyilmaz.github.io/ngyapp/privacy-policy.html)
- [ ] App icon 512x512 PNG
- [ ] Feature graphic 1024x500 PNG/JPG
- [ ] At least 2 phone screenshots

---

## Phase 1: Generate Upload Keystore

- [ ] Run keytool to generate a `.jks` keystore (see commands below)
- [ ] Create `android/key.properties` with keystore details
- [ ] Verify `build.gradle` references `key.properties` (already configured)
- [ ] **BACK UP** the keystore and passwords securely — if lost, you can never update the app

### Keytool Command
```bash
keytool -genkey -v -keystore ngy-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ngy-key
```

### key.properties Format
```
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=ngy-key
storeFile=../ngy-release-key.jks
```

---

## Phase 2: Build the App Bundle

- [ ] Bump version in `pubspec.yaml` if needed (currently 1.0.2+9)
- [ ] Run `flutter clean`
- [ ] Run `flutter build appbundle --release`
- [ ] Verify the `.aab` file at `build/app/outputs/bundle/release/app-release.aab`

---

## Phase 3: Google Play Console Setup

### 3a. Create the App
- [ ] Go to Google Play Console → "Create app"
- [ ] App name: "Uzman Dyt. Nilay G. Yılmaz" (or full name if it fits at the time)
- [ ] Default language: Turkish (tr-TR)
- [ ] App type: App (not Game)
- [ ] Free or Paid: Free
- [ ] Accept declarations

### 3b. Store Listing
- [ ] Upload app icon (512x512)
- [ ] Upload feature graphic (1024x500)
- [ ] Upload phone screenshots (min 2)
- [ ] Fill in short description (from GOOGLE_PLAY_METADATA.md)
- [ ] Fill in full description (from GOOGLE_PLAY_METADATA.md)

### 3c. Content Rating
- [ ] Complete the content rating questionnaire (answers in GOOGLE_PLAY_METADATA.md)

### 3d. Pricing & Distribution
- [ ] Set as Free
- [ ] Select target countries (Turkey at minimum)

### 3e. Data Safety
- [ ] Complete the Data Safety form (answers in GOOGLE_PLAY_METADATA.md)

### 3f. App Content
- [ ] Privacy policy URL: https://utkuyilmaz.github.io/ngyapp/privacy-policy.html
- [ ] Ads declaration: No ads
- [ ] Target audience: Not designed for children
- [ ] Content rating: Complete questionnaire
- [ ] COVID-19 contact tracing / status apps: No
- [ ] Government apps: No
- [ ] Financial features: No (payment tracking is internal, not real transactions)

---

## Phase 4: App Signing & Upload

- [ ] Enable Google Play App Signing (recommended, on by default for new apps)
- [ ] Upload the `.aab` file to the Production track (or Internal Testing first)
- [ ] Review the pre-launch report after upload

---

## Phase 5: Testing (Recommended Before Production)

- [ ] Create an Internal Testing track release first
- [ ] Add test emails (your own, the dietitian's)
- [ ] Test the app via Play Store internal link
- [ ] Verify push notifications work
- [ ] Verify Firebase connectivity
- [ ] Test login flow
- [ ] Test all major features

---

## Phase 6: Production Release

- [ ] Promote Internal Testing release to Production (or upload directly)
- [ ] Select rollout percentage (100% for full release)
- [ ] Add release notes (version 1.0.1 notes from GOOGLE_PLAY_METADATA.md)
- [ ] Submit for review

---

## Post-Submission

- [ ] Monitor review status (typically 1-7 days for first submission)
- [ ] Check for policy violation emails
- [ ] Once approved, verify the listing on Google Play
- [ ] Share the Play Store link with users

---

## Important Reminders

1. **NEVER lose the keystore** — without it, you cannot push updates
2. Google Play review can take longer for first-time apps (up to 7 days)
3. If rejected, read the rejection reason carefully and fix the specific issue
4. The app ID (`com.utkuyilmaz.ngy_app`) cannot be changed after first upload
5. Version code must increase with every upload (currently at 8)
