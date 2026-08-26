import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;


import '../constants/app_constants.dart';
import '../models/logger.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger.forClass(NotificationService);

  static const int MEAL_NOTIFICATION_DELAY_MINUTES = 45;
  static const String PAYMENT_NOTIFICATION_CHANNEL = NotificationConstants.paymentReminderChannelId;

  bool _isInitialized = false;

  /// Check if local notifications are supported on this platform (not on Windows)
  bool get _isSupported {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Public getter to check if notifications are supported on this platform
  bool get isSupported => _isSupported;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    if (!_isSupported) {
      _logger.info('Local notifications not supported on this platform');
      _isInitialized = true; // Mark as initialized to avoid repeated attempts
      return;
    }

    tz_data.initializeTimeZones();

    // Request permissions for iOS
    final iosImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosImplementation != null) {
      await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      _logger.info('iOS notification permissions requested');
    }

    // Request permissions for Android
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      _logger.info('Android notification permissions requested');
    }

    const androidSettings =
        AndroidInitializationSettings(NotificationConstants.androidNotificationIcon);
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        _logger.info('Notification tapped: ${response.payload}');
      },
    );
    _isInitialized = true;
    _logger.info('Notification service initialized');
  }

  /// Ensure initialized before using notifications
  Future<bool> _ensureInitialized() async {
    if (!_isSupported) {
      _logger.info('Local notifications not supported on this platform');
      return false;
    }
    if (!_isInitialized) {
      await initialize();
    }
    return _isInitialized && _isSupported;
  }

  Future<void> scheduleTestNotification() async {
    try {
      final isReady = await _ensureInitialized();
      if (!isReady) {
        _logger.info('Cannot schedule test notification - platform not supported');
        return;
      }

      const androidDetails = AndroidNotificationDetails(
        'test_channel',
        'Test Notifications',
        channelDescription: 'Channel for testing notifications',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        enableLights: true,
        playSound: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.reminder,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: 1,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Schedule notification for 5 seconds from now
      final now = DateTime.now();
      final scheduledDate = now.add(const Duration(seconds: 5));

      await _notifications.zonedSchedule(
        0, // notification id
        NotificationConstants.testNotificationTitle,
        NotificationConstants.testNotificationBody,
        tz.TZDateTime.from(scheduledDate, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,//androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      _logger
          .info('Test notification scheduled for: ${scheduledDate.toString()}');
    } catch (e) {
      _logger.err('Error scheduling test notification: $e');
    }
  }

  /// Schedule a notification for a payment due date
  /// 
  /// @param paymentId The ID of the payment
  /// @param userId The ID of the user
  /// @param amount The payment amount
  /// @param dueDate The payment due date
  /// @param minutesBefore How many minutes before the due date to send the notification
  Future<void> schedulePaymentNotification({
    required String paymentId,
    required String userId,
    required double amount,
    required DateTime dueDate,
    required int minutesBefore,
  }) async {
    try {
      final isReady = await _ensureInitialized();
      if (!isReady) {
        _logger.info('Cannot schedule payment notification - platform not supported');
        return;
      }

      // Calculate notification time
      final notificationTime = dueDate.subtract(Duration(minutes: minutesBefore));
      
      // Don't schedule if the time has already passed
      if (notificationTime.isBefore(DateTime.now())) {
        _logger.info('Notification time has already passed for payment $paymentId');
        return;
      }

      final androidDetails = AndroidNotificationDetails(
        PAYMENT_NOTIFICATION_CHANNEL,
        NotificationConstants.paymentReminderChannelName,
        channelDescription: NotificationConstants.paymentReminderChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        enableLights: true,
        playSound: true,
        category: AndroidNotificationCategory.reminder,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: 1,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Generate a unique notification ID based on payment ID and minutes before
      final notificationId = '${paymentId}_$minutesBefore'.hashCode;

      await _notifications.zonedSchedule(
        notificationId,
        NotificationConstants.paymentReminderTitle,
        NotificationConstants.getPaymentReminderBody(amount.toStringAsFixed(0), minutesBefore),
        tz.TZDateTime.from(notificationTime, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,//androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: paymentId, // Store the payment ID as payload
      );

      _logger.info('Scheduled payment notification for $paymentId at $notificationTime');
    } catch (e) {
      _logger.err('Error scheduling payment notification: $e');
    }
  }

  /// Cancel all notifications related to a specific payment
  /// 
  /// @param paymentId The ID of the payment
  /// @param notificationTimes List of notification times in minutes before due date
  Future<void> cancelPaymentNotifications(String paymentId, List<int>? notificationTimes) async {
    try {
      if (!_isSupported) return;
      
      if (notificationTimes == null || notificationTimes.isEmpty) {
        _logger.info('No notification times specified for payment $paymentId');
        return;
      }
      
      // Cancel each notification based on its unique ID
      for (final minutesBefore in notificationTimes) {
        final notificationId = '${paymentId}_$minutesBefore'.hashCode;
        await _notifications.cancel(notificationId);
        _logger.info('Canceled notification $notificationId for payment $paymentId');
      }
    } catch (e) {
      _logger.err('Error canceling payment notifications: $e');
    }
  }

  Future<void> scheduleMealNotification({
    required String userId,
    required String mealName,
    required DateTime mealTime,
  }) async {
    try {
      final isReady = await _ensureInitialized();
      if (!isReady) {
        _logger.info('Cannot schedule meal notification - platform not supported');
        return;
      }

      // Check if notifications are enabled for this user
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final userData = userDoc.data();
      if (userData == null || userData['mealNotificationsEnabled'] != true) {
        _logger.info('Meal notifications are disabled for user $userId');
        return;
      }

      // Calculate notification time (45 minutes before meal time)
      final notificationTime = mealTime.subtract(
        const Duration(minutes: MEAL_NOTIFICATION_DELAY_MINUTES),
      );

      // Don't schedule if the time has already passed
      if (notificationTime.isBefore(DateTime.now())) {
        _logger.info('Notification time has already passed for meal $mealName');
        return;
      }

      final androidDetails = AndroidNotificationDetails(
        NotificationConstants.mealReminderChannelId,
        NotificationConstants.mealReminderChannelName,
        channelDescription: NotificationConstants.mealReminderChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        enableLights: true,
        playSound: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.reminder,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
        badgeNumber: 1,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.zonedSchedule(
        mealName.hashCode, // Use meal name hash as notification id
        NotificationConstants.mealReminderTitle,
        '$mealName için $MEAL_NOTIFICATION_DELAY_MINUTES dakika kaldı!',
        tz.TZDateTime.from(notificationTime, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      //androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      _logger.info(
          'Scheduled notification for meal $mealName at $notificationTime');
    } catch (e) {
      _logger.err('Error scheduling meal notification: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    if (!_isSupported) return;
    await _notifications.cancelAll();
    _logger.info('All notifications cancelled');
  }

  /// Clear the app badge (set badge count to 0)
  /// Call this when app resumes to foreground to clear badge after user dismisses notifications
  Future<void> clearBadge() async {
    if (!_isSupported) return;
    
    try {
      // iOS: Clear badge by setting badge number to 0
      if (Platform.isIOS) {
        final iosImplementation = _notifications
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        // Use the setBadge method available on iOS plugin
        // Note: This requires iOS 16+ for direct badge setting, but the notification
        // channel approach works on older versions too
        await iosImplementation?.requestPermissions(badge: true);
        
        // The most reliable way to clear badge on iOS is to show and immediately
        // cancel a notification with badgeNumber: 0, but simpler is to use
        // the underlying UNUserNotificationCenter API which flutter_local_notifications
        // exposes. For now, we use a workaround: set badge via notification details.
        // Actually, flutter_local_notifications doesn't have a direct setBadge method,
        // so we need to use a different approach.
        
        // Alternative: Use native iOS API through platform channel, but for simplicity
        // we can show a silent notification with badge: 0 then cancel it
        const iosDetails = DarwinNotificationDetails(
          presentAlert: false,
          presentBadge: true,
          presentSound: false,
          badgeNumber: 0,
        );
        
        const details = NotificationDetails(iOS: iosDetails);
        
        // Show notification with badge 0 (won't display anything, just clears badge)
        await _notifications.show(
          -1, // Use a reserved ID for badge clearing
          '', // Empty title
          '', // Empty body
          details,
        );
        
        // Immediately cancel to ensure no notification is shown
        await _notifications.cancel(-1);
        
        _logger.info('iOS badge cleared');
      }
      
      // Android: Badge is automatically managed by the system based on active notifications
      // No action needed - badge clears when notifications are dismissed
      if (Platform.isAndroid) {
        _logger.info('Android badge is auto-managed by system');
      }
    } catch (e) {
      _logger.err('Error clearing badge: $e');
    }
  }
}
