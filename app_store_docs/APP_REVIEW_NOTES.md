# App Review Information

## For Apple App Review Team

### App Description

NGY Dietitian is a private client management app designed exclusively for registered clients of Dietitian Nilay Göktepe Yılmaz. The app enables dietitian-client communication, appointment scheduling, personalized diet plan access, meal tracking, and progress monitoring.

**Important:** This is NOT a public app. Users must be pre-registered by the dietitian to access the app. The app serves as a companion tool for clients who are receiving in-person dietitian consultation services.

---

## Demo Account Credentials

**Please use the following test account for review:**

| Field | Value |
|-------|-------|
| Email | `[TEST_EMAIL_HERE]` |
| Password | `[TEST_PASSWORD_HERE]` |

> ⚠️ **Note to Developer:** Before submission, create a test account with sample data including:
> - Sample diet plan
> - Sample appointments (past and future)
> - Sample measurements
> - Sample messages
> - Sample payment records

---

## How to Test the App

### 1. Login
- Launch the app
- Enter the demo credentials above
- Tap "Giriş Yap" (Login)

### 2. Main Features to Test

**Appointments (Randevular)**
- View upcoming appointments
- View available time slots
- Book a new appointment

**Diet Plans (Diyet)**
- View assigned diet plan
- Browse daily meal recommendations

**Meal Tracking (Öğünler)**
- Tap camera icon to take/upload meal photo
- View previously uploaded meals

**Measurements (Ölçümler)**
- View recorded measurements
- See progress over time

**Chat (Mesajlar)**
- Send test message
- View message history

**Payments (Ödemeler)**
- View payment history


**Profile (Profil)**
- View user information
- Change password option

### 3. Notifications
- The app uses push notifications for:
  - Appointment reminders
  - New messages
  - Important announcements
- To test, send a message from the admin panel (not available in client app)

---

## Technical Notes

### Permissions Used

| Permission | Purpose | When Requested |
|------------|---------|----------------|
| Camera | Taking meal photos | When user taps to take photo |
| Photo Library | Selecting meal photos and receipts | When user taps to select from gallery |
| Push Notifications | Reminders and messages | On first launch / login |

### Backend Services
- Firebase Authentication (email/password)
- Cloud Firestore (database)
- Firebase Storage (photos/files)
- Firebase Cloud Messaging (push notifications)

### Encryption
- The app uses standard HTTPS/TLS encryption
- No custom encryption algorithms
- ITSAppUsesNonExemptEncryption is set to NO

---

## Content Rating Questionnaire Guidance

| Category | Answer |
|----------|--------|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use | None |
| Simulated Gambling | None |
| Horror/Fear Themes | None |
| Mature/Suggestive Themes | None |
| Medical/Treatment Information | No |
| Unrestricted Web Access | No |


---

## Special Circumstances

### Why Login is Required
This app is designed for a private practice. Only pre-registered clients of the dietitian can access the app. This is similar to a patient portal for healthcare providers.

### Turkish Language
The primary language of the app is Turkish, as it serves clients in Turkey. The demo account data is also in Turkish.

### No In-App Purchases
The app is free to download and use. Dietitian consultation services are paid separately outside the app.

---

## Contact for Review Questions

If you have any questions during the review process:

| Field | Value |
|-------|-------|
| First Name | utku |
| Last Name | yılmaz |
| Phone | +90 534 077 5179 |
| Email | utkuyy97@gmail.com |

---

## Potential Review Concerns & Responses

### "App requires login to function"
**Response:** This is intentional. The app is a private client portal for registered dietitian clients. A demo account has been provided for review purposes.

### "Limited functionality without active subscription"
**Response:** The app's value comes from personalized content (diet plans, appointments, messages) created by the dietitian. The demo account includes sample content to demonstrate all features.

### "App collects health information"
**Response:** Yes, this is a health/fitness app that tracks nutrition data. All data collection is disclosed in the Privacy Policy, users provide explicit consent, and data is handled in compliance with GDPR and local privacy regulations (KVKK).
