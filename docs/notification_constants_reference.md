firebase deploy --only functions
flutter build apk --release --target-platform=android-arm64
# Notification & App Constants Reference

This document lists all locations where notification text, icons, and app name are defined.
Use this as a reference when you need to change any of these values.

---

## Table of Contents

1. [Application Name](#application-name)
2. [Meal Notifications (Local)](#meal-notifications-local)
3. [Chat Message Notifications (Push)](#chat-message-notifications-push)
4. [News/Announcement Notifications (Push)](#newsannouncement-notifications-push)
5. [In-App Notification Banner](#in-app-notification-banner)

---

## Application Name

The app name "untitled" is defined in **4 locations**. You must change ALL of them:

### 1. Flutter Constants (for Dart code reference)
**File:** `lib/constants/app_constants.dart`
```dart
static const String appName = 'untitled';
```

### 2. pubspec.yaml (Flutter package name)
**File:** `pubspec.yaml`
```yaml
name: untitled
```
**Note:** This is the Dart package name. Changing this may require updating imports if the package name is used in import statements.

### 3. Android App Label
**File:** `android/app/src/main/AndroidManifest.xml`
```xml
android:label="untitled"
```
**Line:** ~8

### 4. iOS App Name
**File:** `ios/Runner/Info.plist`
```xml
<key>CFBundleDisplayName</key>
<string>Untitled</string>
...
<key>CFBundleName</key>
<string>untitled</string>
```
**Lines:** ~8 and ~15

---

## Meal Notifications (Local)

Meal reminder notifications are **local notifications** scheduled by Flutter.
They remind users to upload meal photos 30 minutes after meal time.

### Flutter Constants
**File:** `lib/constants/app_constants.dart`

| Constant | Current Value | Description |
|----------|---------------|-------------|
| `mealReminderTitle` | `'Öğün Hatırlatması'` | Notification title |
| `mealReminderBodyTemplate` | `'{mealLabel} öğününüzü yüklediniz mi? Fotoğraf eklemeyi unutmayın!'` | Body template. `{mealLabel}` is replaced with actual meal name |
| `mealReminderChannelId` | `'meal_reminders'` | Android notification channel ID |
| `mealReminderChannelName` | `'Öğün Hatırlatmaları'` | Channel name shown in Android settings |
| `mealReminderChannelDescription` | `'Öğün fotoğrafı yükleme hatırlatmaları'` | Channel description |
| `mealReminderDelayMinutes` | `30` | Minutes after meal time to send reminder |

### Services Using These Constants
- `lib/services/meal_reminder_service.dart`
- `lib/services/notification_service.dart`

### Notification Icon (Android)
**File:** `lib/constants/app_constants.dart`
```dart
static const String androidNotificationIcon = '@mipmap/ngy';
```

**To change the notification icon:**

1. **Add your icon files** with your chosen name (e.g., `my_icon.png`) to:
   - `android/app/src/main/res/mipmap-hdpi/my_icon.png`
   - `android/app/src/main/res/mipmap-mdpi/my_icon.png`
   - `android/app/src/main/res/mipmap-xhdpi/my_icon.png`
   - `android/app/src/main/res/mipmap-xxhdpi/my_icon.png`
   - `android/app/src/main/res/mipmap-xxxhdpi/my_icon.png`

2. **Update the constant** in `lib/constants/app_constants.dart`:
   ```dart
   static const String androidNotificationIcon = '@mipmap/my_icon';
   ```

3. **Update AndroidManifest.xml** if you also want to change the app icon:
   ```xml
   android:icon="@mipmap/my_icon"
   ```

**Important:** All notification services use `AppConstants.androidNotificationIcon`, so you only need to change the constant in one place.
---

## Chat Message Notifications (Push)

Chat notifications are **push notifications** sent via Firebase Cloud Functions.
They notify users/admins about new chat messages.

### Cloud Functions Constants
**File:** `functions/index.js` (at the top of the file)

| Constant | Current Value | Description |
|----------|---------------|-------------|
| `CHAT_ADMIN_TO_USER_TITLE` | `'Destek'` | Title when admin sends message to user |
| `CHAT_DEFAULT_BODY` | `'Yeni mesaj'` | Body when message text is empty |
| `CHAT_IMAGE_BODY` | `'Fotoğraf'` | Body when message is an image |
| `CHAT_REACTION_BODY_TEMPLATE` | `'bir mesajınıza {emoji} ifadesi bıraktı'` | Body when an admin reacts to the user's message. `{emoji}` is replaced with the reaction (e.g. `👍`). Title is `CHAT_ADMIN_TO_USER_TITLE`. |
| `CHAT_USER_TO_ADMIN_DEFAULT_TITLE` | `'Kullanıcı mesajı'` | Title when user sends to admin (fallback if name not found) |
| `CHAT_ANDROID_ICON` | `'ic_notification'` | Android notification icon |
| `CHAT_ANDROID_COLOR` | `'#075E54'` | Notification color (WhatsApp green) |
| `CHAT_CHANNEL_ID` | `'chat_messages_v2'` | Android notification channel ID |

**Reaction notifications** are sent by the `notifyUserOnAdminReaction` Cloud
Function (triggered on message *updates*). When an admin leaves or changes a
reaction (`reactions.<adminUid> = emoji`) on a message the user sent, the user
is notified: title `Nilay Göktepe Yılmaz`, body e.g. `bir mesajınıza 👍 ifadesi
bıraktı`. Removing a reaction does not notify.

### Notification Channel (Android)
**File:** `android/app/src/main/res/values/string.xml`
```xml
<string name="notification_channel_id" translatable="false">chat_messages_v2</string>
<string name="chat_channel_name">Sohbet Mesajları</string>
<string name="chat_channel_description">Yeni sohbet mesajı bildirimleri</string>
```

### Custom Notification Icon
To use a custom icon for push notifications:
1. Create icon files named `ic_notification.png` in:
   - `android/app/src/main/res/drawable-hdpi/`
   - `android/app/src/main/res/drawable-mdpi/`
   - `android/app/src/main/res/drawable-xhdpi/`
   - `android/app/src/main/res/drawable-xxhdpi/`
   - `android/app/src/main/res/drawable-xxxhdpi/`
2. Icons should be white with transparent background (Android notification guidelines)

**After changing Cloud Functions:**
```bash
cd functions
firebase deploy --only functions
```

---

## News/Announcement Notifications (Push)

News notifications are **push notifications** sent via Firebase Cloud Functions.
They notify all users when new announcements are published.

### Cloud Functions Constants
**File:** `functions/index.js` (at the top of the file)

| Constant | Current Value | Description |
|----------|---------------|-------------|
| `NEWS_TITLE_PREFIX` | `'📢 '` | Emoji prefix before news title |
| `NEWS_DEFAULT_TITLE` | `'Yeni Duyuru'` | Fallback title if news has no title |
| `NEWS_ANDROID_ICON` | `'ic_notification'` | Android notification icon |
| `NEWS_ANDROID_COLOR` | `'#1976D2'` | Notification color (blue) |
| `NEWS_CHANNEL_ID` | `'news_announcements'` | Android notification channel ID |

### Notification Channel (Android)
**File:** `android/app/src/main/res/values/string.xml`
```xml
<string name="news_channel_id" translatable="false">news_announcements</string>
<string name="news_channel_name">Duyurular</string>
<string name="news_channel_description">Yeni duyuru bildirimleri</string>
```

**After changing Cloud Functions:**
```bash
cd functions
firebase deploy --only functions
```

---

## In-App Notification Banner

When the app is in the foreground, notifications are shown as in-app banners.
These are styled differently from system notifications.

### Flutter Constants
**File:** `lib/constants/app_constants.dart`

| Constant | Current Value | Description |
|----------|---------------|-------------|
| `inAppNotificationDefaultTitle` | `'Bildirim'` | Fallback title if notification has no title |
| `inAppNotificationIconAsset` | `'assets/ngy.png'` | Avatar/icon image in the banner |
| `newsNotificationBannerColor` | `0xFF1976D2` | Background color for news (blue) |
| `newsNotificationBannerAccentColor` | `0xFF64B5F6` | Accent color for news |
| `chatNotificationBannerColor` | `0xFF075E54` | Background color for chat (WhatsApp green) |
| `chatNotificationBannerAccentColor` | `0xFF25D366` | Accent color for chat |

### Banner Icon
To change the banner icon, replace the file:
**File:** `assets/ngy.png`

Make sure to update the asset path in `app_constants.dart` if you use a different filename.

---

## Quick Reference: Files to Edit

### To change App Name:
1. `lib/constants/app_constants.dart` - `AppConstants.appName`
2. `pubspec.yaml` - `name: untitled`
3. `android/app/src/main/AndroidManifest.xml` - `android:label`
4. `ios/Runner/Info.plist` - `CFBundleDisplayName` and `CFBundleName`

### To change Meal Notification Text:
1. `lib/constants/app_constants.dart` - `NotificationConstants.mealReminderTitle` and `mealReminderBodyTemplate`

### To change Chat Notification Text:
1. `functions/index.js` - Constants at the top (CHAT_*)
2. Deploy: `cd functions && firebase deploy --only functions`

### To change News Notification Text:
1. `functions/index.js` - Constants at the top (NEWS_*)
2. Deploy: `cd functions && firebase deploy --only functions`

### To change Notification Icons:
- **Local notifications (Android):** Replace `ic_launcher.png` in `android/app/src/main/res/mipmap-*/`
- **Push notifications (Android):** Add `ic_notification.png` to `android/app/src/main/res/drawable-*/`
- **In-app banner:** Replace `assets/ngy.png` and update `inAppNotificationIconAsset`

---

## Notes

- After modifying Cloud Functions (`functions/index.js`), you must deploy them:
  ```bash
  cd functions
  firebase deploy --only functions
  ```

- After modifying Android manifest or iOS Info.plist, rebuild the app:
  ```bash
  flutter clean
  flutter build apk  # or flutter build ios
  ```

- Notification channel IDs cannot be changed for existing users unless they reinstall the app or clear app data. If you change channel IDs, old channels will remain on user devices.

