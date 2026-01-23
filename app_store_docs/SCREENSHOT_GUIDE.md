# Screenshot Requirements & Guide

## Required Screenshot Sizes

### iPhone Screenshots (Required)

| Device | Resolution | Required |
|--------|------------|----------|
| 6.7" Display (iPhone 14 Pro Max, 15 Pro Max) | 1290 x 2796 px | ✅ Yes |
| 6.5" Display (iPhone 11 Pro Max, XS Max) | 1242 x 2688 px | ✅ Yes |
| 5.5" Display (iPhone 8 Plus, 7 Plus, 6s Plus) | 1242 x 2208 px | Optional (if supporting older devices) |

### iPad Screenshots (If your app supports iPad)

| Device | Resolution | Required |
|--------|------------|----------|
| 12.9" Display (iPad Pro 6th Gen) | 2048 x 2732 px | ✅ Yes (if iPad supported) |
| 12.9" Display (iPad Pro 2nd Gen) | 2048 x 2732 px | ✅ Yes (if iPad supported) |

---

## Screenshot Requirements

- **Quantity:** Minimum 2, Maximum 10 per device size
- **Format:** PNG or JPEG
- **Color Space:** sRGB or P3
- **No Alpha Channel:** Transparency not allowed
- **No Device Frames:** Apple adds them automatically
- **Accurate Representation:** Must show actual app UI

---

## Recommended Screenshots for NGY Diyetisyen

Based on your app's features, here are the recommended screenshots in order of importance:

### Screenshot 1: Login / Welcome Screen
**Purpose:** First impression, show branding
**Screen:** Login page with app logo
**Caption (TR):** "Diyetisyeninizle bağlantıda kalın"
**Caption (EN):** "Stay connected with your dietitian"

### Screenshot 2: Main Dashboard / Home
**Purpose:** Show app overview
**Screen:** Main menu or dashboard after login
**Caption (TR):** "Tüm özellikler bir arada"
**Caption (EN):** "All features in one place"

### Screenshot 3: Diet Plan View
**Purpose:** Core feature demonstration
**Screen:** Diet plan with meals listed
**Caption (TR):** "Kişisel diyet programınız"
**Caption (EN):** "Your personalized diet plan"

### Screenshot 4: Appointment Booking
**Purpose:** Show scheduling feature
**Screen:** Calendar with available time slots
**Caption (TR):** "Kolayca randevu alın"
**Caption (EN):** "Book appointments easily"

### Screenshot 5: Meal Tracking / Photo Upload
**Purpose:** Show meal tracking feature
**Screen:** Meal upload interface or meal history
**Caption (TR):** "Öğünlerinizi takip edin"
**Caption (EN):** "Track your meals"

### Screenshot 6: Measurements/Progress
**Purpose:** Show progress tracking
**Screen:** Measurement history or chart
**Caption (TR):** "İlerlemenizi görün"
**Caption (EN):** "See your progress"

### Screenshot 7: Chat / Messaging
**Purpose:** Show communication feature
**Screen:** Chat interface with sample conversation
**Caption (TR):** "Diyetisyeninizle mesajlaşın"
**Caption (EN):** "Message your dietitian"

### Screenshot 8: Profile / Settings
**Purpose:** Show personalization
**Screen:** Profile page
**Caption (TR):** "Profilinizi yönetin"
**Caption (EN):** "Manage your profile"

---

## Screenshot Tips

### Do's ✅
- Use real app screenshots (from demo account)
- Ensure clean, professional appearance
- Remove any test/debug indicators
- Use consistent styling across all screenshots
- Show actual Turkish content as your primary audience is Turkish
- Include meaningful sample data

### Don'ts ❌
- Don't include status bar time "9:41" unless it's the default
- Don't show personal/real user data
- Don't include placeholder text like "Lorem ipsum"
- Don't use device frames in the image itself
- Don't include debug banners or dev indicators
- Don't show error states

---

## How to Capture Screenshots

### Method 1: iOS Simulator (Recommended)
```bash
# Build and run in simulator
flutter run -d "iPhone 14 Pro Max"

# In Simulator: File > Save Screen (or Cmd+S)
```

### Method 2: Physical Device
1. Connect device to Mac
2. Open Xcode
3. Window > Devices and Simulators
4. Select device > Take Screenshot

### Method 3: Xcode Organizer
When archiving for distribution, Xcode can help capture screenshots.

---

## Screenshot Localization

Since your app is primarily in Turkish, consider:

### Option A: Turkish Only
- Submit all screenshots in Turkish
- App targets Turkish market
- Simpler to maintain

### Option B: Turkish + English
- Turkish for Turkey App Store
- English for international (if expanding)
- Requires maintaining two sets

---

## Tools for Screenshot Enhancement (Optional)

While Apple doesn't require it, you can enhance screenshots with:

1. **AppScreens.com** - Web-based screenshot generator
2. **Sketch/Figma** - Add promotional text overlays
3. **RocketSim** - Simulator recording and screenshots
4. **Previewed** - App Store screenshot templates

### Professional Enhancement Template

```
+------------------------+
|   Promotional Text     |
|   (2-3 words max)      |
|                        |
|   +----------------+   |
|   |                |   |
|   |  App Screen    |   |
|   |  (actual UI)   |   |
|   |                |   |
|   +----------------+   |
|                        |
+------------------------+
```

---

## Checklist Before Submission

- [ ] Screenshots taken at correct resolution
- [ ] Minimum 2 screenshots per required device size
- [ ] No alpha channel / transparency
- [ ] No device frames (Apple adds them)
- [ ] Demo data looks professional
- [ ] No debug/test indicators visible
- [ ] Screenshots accurately represent app functionality
- [ ] Consistent visual style across all screenshots
- [ ] Turkish text is correct and professional
- [ ] Status bar shows appropriate time (or default)
