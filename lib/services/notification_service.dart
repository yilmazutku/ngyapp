import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;


import '../constants/app_constants.dart';
import 'fcm_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const int MEAL_NOTIFICATION_DELAY_MINUTES = 45;
  static const String PAYMENT_NOTIFICATION_CHANNEL = NotificationConstants.paymentReminderChannelId;

  bool _isInitialized = false;

  /// Check if local notifications are supported on this platform (not on Windows)
  bool get _isSupported {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Public getter to check if notifications are supported on this platform
  bool get isSupported => _isSupported;

  Future<void>? _initializing;

  Future<void> initialize() {
    if (_isInitialized) return Future<void>.value();
    return _initializing ??=
        _initialize().whenComplete(() => _initializing = null);
  }

  Future<void> _initialize() async {
    if (!_isSupported) {
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
    }

    // Request permissions for Android
    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }

    const androidSettings =
        AndroidInitializationSettings(NotificationConstants.androidNotificationIcon);
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );

    const macOSSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macOSSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    _isInitialized = true;

    try {
      final NotificationAppLaunchDetails? launch =
          await _notifications.getNotificationAppLaunchDetails();
      final NotificationResponse? response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _onNotificationResponse(response);
      }
    } catch (e) {
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    final String? payload = response.payload;
    if (!isAdminPayload(payload)) return;
    FcmService().openLocalNotification(
      FcmService.adminNotificationTapData(adminNotificationDocId(payload) ?? ''),
    );
  }

  /// Ensure initialized before using notifications
  Future<bool> _ensureInitialized() async {
    if (!_isSupported) {
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
    } catch (e) {
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
        return;
      }

      // Calculate notification time
      final notificationTime = dueDate.subtract(Duration(minutes: minutesBefore));
      
      // Don't schedule if the time has already passed
      if (notificationTime.isBefore(DateTime.now())) {
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
    } catch (e) {
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
        return;
      }
      
      // Cancel each notification based on its unique ID
      for (final minutesBefore in notificationTimes) {
        final notificationId = '${paymentId}_$minutesBefore'.hashCode;
        await _notifications.cancel(notificationId);
      }
    } catch (e) {
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
        return;
      }

      // Check if notifications are enabled for this user
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final userData = userDoc.data();
      if (userData == null || userData['mealNotificationsEnabled'] != true) {
        return;
      }

      // Calculate notification time (45 minutes before meal time)
      final notificationTime = mealTime.subtract(
        const Duration(minutes: MEAL_NOTIFICATION_DELAY_MINUTES),
      );

      // Don't schedule if the time has already passed
      if (notificationTime.isBefore(DateTime.now())) {
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
    } catch (e) {
    }
  }

  static const String _adminPayloadPrefix = 'adminNotification:';

  static const int _adminIdBase = 200000000;
  static const int _adminIdRange = 100000000;

  static int adminNotificationId(String docId) {
    int hash = 0x811c9dc5;
    for (final int unit in docId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return _adminIdBase + hash % _adminIdRange;
  }

  static bool isAdminPayload(String? payload) =>
      payload != null && payload.startsWith(_adminPayloadPrefix);

  static String? adminNotificationDocId(String? payload) {
    if (payload == null || !payload.startsWith(_adminPayloadPrefix)) {
      return null;
    }
    final String docId = payload.substring(_adminPayloadPrefix.length);
    return docId.isEmpty ? null : docId;
  }

  Future<bool> scheduleAdminNotification({
    required String docId,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    try {
      final isReady = await _ensureInitialized();
      if (!isReady || !fireAt.isAfter(DateTime.now())) return false;

      await _notifications.zonedSchedule(
        adminNotificationId(docId),
        title,
        body,
        tz.TZDateTime.from(fireAt, tz.local),
        _adminNotificationDetails(body),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: '$_adminPayloadPrefix$docId',
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> showAdminNotification({
    required String docId,
    required String title,
    required String body,
    String? notificationKey,
  }) async {
    try {
      final isReady = await _ensureInitialized();
      if (!isReady) return false;
      await _notifications.show(
        adminNotificationId(notificationKey ?? docId),
        title,
        body,
        _adminNotificationDetails(body),
        payload: '$_adminPayloadPrefix$docId',
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  static NotificationDetails _adminNotificationDetails(String body) {
    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBanner: false,
      presentList: true,
      presentBadge: false,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    );
    return NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationConstants.adminReminderChannelId,
        NotificationConstants.adminReminderChannelName,
        channelDescription:
            NotificationConstants.adminReminderChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
  }

  Future<void> cancelAdminNotification(String docId) async {
    if (!_isSupported) return;
    try {
      await _notifications.cancel(adminNotificationId(docId));
    } catch (e) {
    }
  }

  Future<Set<String>> pendingAdminNotificationDocIds() async {
    if (!_isSupported) return const {};
    try {
      final isReady = await _ensureInitialized();
      if (!isReady) return const {};
      final List<PendingNotificationRequest> pending =
          await _notifications.pendingNotificationRequests();
      return {
        for (final PendingNotificationRequest request in pending)
          if (adminNotificationDocId(request.payload) case final String docId)
            docId,
      };
    } catch (e) {
      return const {};
    }
  }

  Future<void> cancelAllNotifications() async {
    if (!_isSupported) return;
    await _notifications.cancelAll();
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
      }
      
      // Android: Badge is automatically managed by the system based on active notifications
      // No action needed - badge clears when notifications are dismissed
    } catch (e) {
    }
  }
}
