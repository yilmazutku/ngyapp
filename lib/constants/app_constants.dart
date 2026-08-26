/// Application-wide constants for easy configuration.
/// 
/// This file centralizes configurable values like:
/// - App name and branding
/// - Notification titles, bodies, and icons
/// - Notification channels
/// 
/// For a complete reference of all notification-related locations
/// (including Cloud Functions and native platform configs),
/// see: docs/notification_constants_reference.md
library;

/// Application name constants.
/// 
/// Note: Changing these values only affects the Dart code.
/// For the actual app name displayed on the device, you must also update:
/// - Android: android/app/src/main/AndroidManifest.xml (android:label)
/// - iOS: ios/Runner/Info.plist (CFBundleDisplayName and CFBundleName)
/// - pubspec.yaml (name field)
class AppConstants {
  AppConstants._();

  /// The display name of the application
  static const String appName = 'Dyt. Nilay Göktepe Yılmaz';

  /// Version shown to the user (top-right of the home page).
  /// Keep in step with the `version:` field in pubspec.yaml.
  static const String appVersion = '1.0.1';
  
  /// The app description shown in various places
  static const String appDescription = 'A new Flutter project.';
}

/// Notification constants for local notifications (Flutter).
/// 
/// These are used by:
/// - MealReminderService (meal_reminder_service.dart)
/// - NotificationService (notification_service.dart)
class NotificationConstants {
  NotificationConstants._();

  // ============================================================
  // MEAL NOTIFICATIONS (Local - Flutter)
  // ============================================================
  
  /// Title for meal reminder notifications
  static const String mealReminderTitle = 'Öğün Hatırlatması';
  
  /// Body template for meal reminder notifications.
  /// Use {mealLabel} as placeholder for the meal name.
  /// Example: "Kahvaltı öğününüzü yüklediniz mi? Fotoğraf eklemeyi unutmayın!"
  static const String mealReminderBodyTemplate = 
      '{mealLabel} öğününüzü yüklediniz mi? Fotoğraf eklemeyi unutmayın!';
  
  /// Generates the meal reminder body with the actual meal label.
  static String getMealReminderBody(String mealLabel) {
    return mealReminderBodyTemplate.replaceAll('{mealLabel}', mealLabel);
  }
  
  /// Notification channel ID for meal reminders (Android)
  static const String mealReminderChannelId = 'meal_reminders';
  
  /// Notification channel name for meal reminders (Android)
  static const String mealReminderChannelName = 'Öğün Hatırlatmaları';
  
  /// Notification channel description for meal reminders (Android)
  static const String mealReminderChannelDescription = 
      'Öğün fotoğrafı yükleme hatırlatmaları';
  
  /// Minutes after meal time to send the reminder
  static const int mealReminderDelayMinutes = 30;

  // ============================================================
  // PAYMENT NOTIFICATIONS (Local - Flutter)
  // ============================================================
  
  /// Title for payment reminder notifications
  static const String paymentReminderTitle = 'Ödeme Hatırlatması';
  
  /// Body template for payment reminder notifications.
  /// Use {amount} for the payment amount and {minutes} for time remaining.
  static const String paymentReminderBodyTemplate = 
      '{amount} ₺ tutarındaki ödemeniz için {minutes} dakika kaldı!';
  
  /// Generates the payment reminder body with actual values.
  static String getPaymentReminderBody(String amount, int minutes) {
    return paymentReminderBodyTemplate
        .replaceAll('{amount}', amount)
        .replaceAll('{minutes}', minutes.toString());
  }
  
  /// Notification channel ID for payment reminders (Android)
  static const String paymentReminderChannelId = 'payment_reminders';
  
  /// Notification channel name for payment reminders (Android)
  static const String paymentReminderChannelName = 'Ödeme Hatırlatmaları';
  
  /// Notification channel description for payment reminders (Android)
  static const String paymentReminderChannelDescription = 
      'Ödeme zamanı yaklaştığında bildirim gönderir';

  // ============================================================
  // TEST NOTIFICATIONS (Local - Flutter)
  // ============================================================
  
  /// Title for test notifications
  static const String testNotificationTitle = 'Test Bildirimi';
  
  /// Body for test notifications
  static const String testNotificationBody = 
      'Bu bir test bildirimidir. Bildirim sistemi çalışıyor!';

  // ============================================================
  // IN-APP NOTIFICATION BANNER (Flutter - FCM Service)
  // ============================================================
  static const int notificationDisplayTime=10;//sec

  /// Default title when notification title is null
  static const String inAppNotificationDefaultTitle = 'Bildirim';
  
  /// Asset path for the notification banner icon/avatar
  static const String inAppNotificationIconAsset = 'assets/ngy.png';
  
  /// Background color for news notifications (in-app banner)
  static const int newsNotificationBannerColor = 0xFF1976D2; // Blue
  
  /// Accent color for news notifications (in-app banner)
  static const int newsNotificationBannerAccentColor = 0xFF64B5F6;
  
  /// Background color for chat notifications (in-app banner)
  static const int chatNotificationBannerColor = 0xFF075E54; // WhatsApp green
  
  /// Accent color for chat notifications (in-app banner)
  static const int chatNotificationBannerAccentColor = 0xFF25D366;

  // ============================================================
  // ANDROID LOCAL NOTIFICATION ICON
  // ============================================================
  
  /// The icon resource name for Android local notifications.
  /// To change: update the icon files in android/app/src/main/res/mipmap-*/ folders
  /// and update this constant to match the filename (without extension).
  static const String androidNotificationIcon = '@mipmap/ngy';
}

/// Constants for Push Notification configuration (Cloud Functions).
/// 
/// IMPORTANT: These constants are for REFERENCE ONLY in Flutter.
/// The actual push notification titles/bodies are defined in Cloud Functions.
/// To change them, edit: functions/index.js
/// 
/// This class documents what's configured in Cloud Functions.
class PushNotificationReference {
  PushNotificationReference._();

  // ============================================================
  // CHAT NOTIFICATIONS (Cloud Functions - index.js)
  // ============================================================
  
  /// Title for admin-to-user chat notifications
  /// Location: functions/index.js line ~144 and chat_page_new.dart
  static const String chatAdminToUserTitle = 'Nilay Göktepe Yılmaz';
  
  /// Default body for chat notifications when message is empty
  /// Location: functions/index.js line ~137
  static const String chatDefaultBody = 'Yeni mesaj';
  
  /// Body for image messages
  /// Location: functions/index.js lines ~141, ~227
  static const String chatImageBody = 'Fotoğraf';

  /// Body template for admin reaction notifications ({emoji} is the reaction).
  /// Rendered as e.g. "bir mesajınıza 👍 ifadesi bıraktı".
  /// Location: functions/index.js (CHAT_REACTION_BODY_TEMPLATE)
  static const String chatReactionBodyTemplate =
      'bir mesajınıza {emoji} ifadesi bıraktı';

  /// Default title for user-to-admin notifications (when name not found)
  /// Location: functions/index.js line ~231
  static const String chatUserToAdminDefaultTitle = 'Kullanıcı mesajı';
  
  /// Android notification icon (in drawable resources)
  /// Location: functions/index.js line ~39
  static const String chatAndroidIcon = 'ic_notification';
  
  /// Android notification color (WhatsApp green)
  /// Location: functions/index.js line ~40
  static const String chatAndroidColor = '#075E54';

  // ============================================================
  // NEWS/ANNOUNCEMENT NOTIFICATIONS (Cloud Functions - index.js)
  // ============================================================
  
  /// Prefix emoji for news notification titles
  /// Location: functions/index.js lines ~425, ~511
  static const String newsTitlePrefix = '📢 ';
  
  /// Default title when news has no title
  /// Location: functions/index.js lines ~401, ~487
  static const String newsDefaultTitle = 'Yeni Duyuru';
  
  /// Android notification icon for news
  /// Location: functions/index.js line ~306
  static const String newsAndroidIcon = 'ic_notification';
  
  /// Android notification color for news (blue)
  /// Location: functions/index.js line ~307
  static const String newsAndroidColor = '#1976D2';

  // ============================================================
  // NOTIFICATION CHANNELS (Android - defined in strings.xml)
  // ============================================================
  
  /// Chat notification channel ID
  /// Location: functions/index.js line ~14, android string.xml line ~4
  static const String chatChannelId = 'chat_messages_v2';
  
  /// News notification channel ID
  /// Location: functions/index.js line ~15, android string.xml line ~11
  static const String newsChannelId = 'news_announcements';
}

