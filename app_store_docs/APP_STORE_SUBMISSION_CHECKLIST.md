# App Store Submission Checklist

## Prerequisites
- [ ] Apple Developer Program membership ($99/year) - https://developer.apple.com/programs/
- [ ] App Store Connect access configured
- [ ] Xcode installed with latest version
- [ ] Valid iOS Distribution Certificate
- [ ] Valid App Store Provisioning Profile

---

## 1. App Store Connect Metadata

### Basic Information
| Field | Character Limit | Status |
|-------|----------------|--------|
| App Name | 30 chars | [ ] |
| Subtitle | 30 chars | [ ] |
| Primary Category | - | [ ] |
| Secondary Category (optional) | - | [ ] |

**Recommended:**
- **App Name:** NGY Diyetisyen
- **Subtitle:** Kişisel Beslenme Takibi
- **Primary Category:** Health & Fitness
- **Secondary Category:** Medical (optional)

### Description & Keywords
| Field | Character Limit | Status |
|-------|----------------|--------|
| Description | 4000 chars | [ ] |
| Promotional Text | 170 chars | [ ] |
| Keywords | 100 chars total | [ ] |
| What's New (Version Notes) | 4000 chars | [ ] |

### URLs (REQUIRED)
| Field | Status | Notes |
|-------|--------|-------|
| Privacy Policy URL | [ ] | **REQUIRED** - Must be publicly accessible |
| Support URL | [ ] | **REQUIRED** |
| Marketing URL | [ ] | Optional |

---

## 2. Visual Assets

### App Icon
- [ ] 1024 x 1024 px PNG
- [ ] No transparency (alpha channel)
- [ ] No rounded corners (Apple adds them)

### Screenshots (REQUIRED)
You need screenshots for each device size you support:

#### iPhone Screenshots (Required if supporting iPhone)
- [ ] 6.7" Display (iPhone 14 Pro Max) - 1290 x 2796 px
- [ ] 6.5" Display (iPhone 11 Pro Max) - 1242 x 2688 px
- [ ] 5.5" Display (iPhone 8 Plus) - 1242 x 2208 px

#### iPad Screenshots (Required if supporting iPad)
- [ ] 12.9" Display (iPad Pro 6th Gen) - 2048 x 2732 px
- [ ] 12.9" Display (iPad Pro 2nd Gen) - 2048 x 2732 px

**Screenshot Requirements:**
- Minimum 2 screenshots, maximum 10 per device size
- PNG or JPEG format
- No alpha channel
- RGB color space
- Show actual app UI (no device frames required)

### App Preview Video (Optional)
- 15-30 seconds
- MP4 or MOV format
- Must show actual app functionality

---

## 3. Required Documents

### Privacy Policy (REQUIRED)
- [ ] Create privacy policy document
- [ ] Host on publicly accessible URL
- [ ] Must describe all data collection and usage
- [ ] See: `PRIVACY_POLICY_TR.md` and `PRIVACY_POLICY_EN.md`

### Terms of Service (Recommended)
- [ ] Create terms of service document
- [ ] See: `TERMS_OF_SERVICE_TR.md`

---

## 4. App Review Information

### Contact Information
- [ ] First Name
- [ ] Last Name
- [ ] Phone Number
- [ ] Email Address

### Demo Account (REQUIRED - App has login)
Since your app requires authentication, you MUST provide:
- [ ] Demo username/email
- [ ] Demo password
- [ ] Notes explaining how to test the app

### Review Notes
- [ ] Explain any special features
- [ ] Explain what the app does
- [ ] Provide context for reviewers

---

## 5. Age Rating Questionnaire
Answer these in App Store Connect:
- [ ] Cartoon or Fantasy Violence
- [ ] Realistic Violence
- [ ] Sexual Content or Nudity
- [ ] Profanity or Crude Humor
- [ ] Alcohol, Tobacco, or Drug Use
- [ ] Simulated Gambling
- [ ] Horror/Fear Themes
- [ ] Mature/Suggestive Themes
- [ ] Medical/Treatment Information
- [ ] Unrestricted Web Access

**For NGY App:** Most answers will be "None" except potentially "Medical/Treatment Information" which may be "Infrequent/Mild" since it's a dietitian app.

---

## 6. Export Compliance

Your `Info.plist` already has:
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```
This means you're declaring no non-exempt encryption. This is typically correct for apps using only HTTPS and standard Firebase services.

---

## 7. Build & Submit

### Build Preparation
```bash
# Clean build
flutter clean

# Get dependencies
flutter pub get

# Build iOS release
flutter build ios --release

# Open in Xcode
open ios/Runner.xcworkspace
```

### In Xcode
1. [ ] Select "Any iOS Device" as build target
2. [ ] Product → Archive
3. [ ] Window → Organizer → Distribute App
4. [ ] Select "App Store Connect"
5. [ ] Upload

### In App Store Connect
1. [ ] Create new app (if first submission)
2. [ ] Fill in all metadata
3. [ ] Upload screenshots
4. [ ] Select the uploaded build
5. [ ] Answer export compliance questions
6. [ ] Submit for review

---

## 8. Common Rejection Reasons to Avoid

1. **Incomplete Information** - Fill ALL required fields
2. **Broken Links** - Test Privacy Policy and Support URLs
3. **Login Issues** - Ensure demo account works
4. **Crashes** - Test thoroughly before submission
5. **Placeholder Content** - Remove "Lorem ipsum" or test data
6. **Misleading Screenshots** - Must show actual app functionality
7. **Missing Permissions Explanations** - Camera/Photo usage descriptions must be clear (already configured in Info.plist)

---

## Files Included in This Folder

| File | Description |
|------|-------------|
| `APP_STORE_METADATA.md` | App name, description, keywords |
| `PRIVACY_POLICY_TR.md` | Turkish privacy policy |
| `PRIVACY_POLICY_EN.md` | English privacy policy |
| `TERMS_OF_SERVICE_TR.md` | Turkish terms of service |
| `APP_REVIEW_NOTES.md` | Notes for Apple reviewers |
| `SCREENSHOT_GUIDE.md` | Screenshot requirements and suggestions |

---

## Estimated Review Time
- First submission: 24-48 hours (can be longer)
- Updates: Usually 24 hours
- Expedited review available for critical fixes
