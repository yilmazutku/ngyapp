import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../constants/app_constants.dart';
import '../models/meal_model.dart';
import '../utils/diet_menu_parser.dart';

/// Service for scheduling meal upload reminder notifications.
/// 
/// Sends notifications 30 minutes AFTER each meal time to remind users
/// to upload their meal photos if they haven't done so yet.
/// 
/// Note: Only works on supported platforms (Android, iOS, macOS, Linux).
/// Windows and Web are NOT supported.
class MealReminderService {
  static final MealReminderService _instance = MealReminderService._internal();
  factory MealReminderService() => _instance;
  MealReminderService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Minutes after meal time to send reminder
  static const int REMINDER_DELAY_MINUTES = NotificationConstants.mealReminderDelayMinutes;

  /// Notification channel for meal reminders
  static const String MEAL_REMINDER_CHANNEL = NotificationConstants.mealReminderChannelId;

  /// Base notification ID for meal reminders (each meal adds its index)
  static const int MEAL_NOTIFICATION_BASE_ID = 1000;

  /// Gün dokümanında (`users/{uid}/meals/{yyyy-MM-dd}`) o gün fotoğrafı
  /// yüklenmiş öğünlerin işareti: `reminderCancelled.<öğün>: true` (bkz.
  /// `MealManager.mealStateFields`). Fotoğraf silinince geri alınmaz; öğünün
  /// hatırlatması o gün hiçbir cihazda bir daha kurulmaz.
  static const String REMINDER_CANCELLED_FIELD = 'reminderCancelled';

  bool _isInitialized = false;

  /// Check if local notifications are supported on this platform (not on Windows)
  bool get isSupported {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized || !isSupported) return;

    // Initialize timezone data
    tz_data.initializeTimeZones();

    // Initialize notification plugin
    const androidSettings = AndroidInitializationSettings(NotificationConstants.androidNotificationIcon);
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);

    _isInitialized = true;
  }

  /// Ensure initialized before scheduling
  Future<bool> _ensureInitialized() async {
    if (!isSupported) return false;
    if (!_isInitialized) {
      await initialize();
    }
    return _isInitialized;
  }

  /// Schedule meal reminders for a user based on their diet plan.
  /// 
  /// This method:
  /// 1. Checks if meal notifications are enabled for the user
  /// 2. Fetches the user's latest diet to get meal times
  /// 3. Fetches today's meal states to see what's already uploaded
  /// 4. Schedules notifications for 30 minutes after each unchecked meal
  ///    whose photo was never uploaded today ([mealsWithoutReminder])
  /// 
  /// @param userId The user's ID
  Future<void> scheduleMealReminders(String userId) async {
    final isReady = await _ensureInitialized();
    if (!isReady) {
      return;
    }

    try {
      // 1. Check if notifications are enabled for this user
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data();
      
      if (userData == null || userData['mealNotificationsEnabled'] != true) {
        return;
      }

      // 2. Fetch the latest diet subtitles (meal times)
      final mealTimes = await _fetchUserMealTimes(userId);
      if (mealTimes.isEmpty) {
        return;
      }

      // 3. Fetch today's meals that get no reminder
      final Set<Meals> skippedMeals = await _fetchTodaySkippedMeals(userId);

      // 4. Schedule reminders for unchecked meals
      final now = DateTime.now();

      for (final entry in mealTimes.entries) {
        final meal = entry.key;
        final mealTime = entry.value;

        // İşaretlenmiş ya da fotoğrafı yüklenmiş öğün: bu cihazda önceden
        // kurulmuş hatırlatması da kalkar (fotoğraf başka cihazdan yüklenmiş
        // olabilir).
        if (skippedMeals.contains(meal)) {
          await cancelMealReminder(meal);
          continue;
        }

        // Calculate reminder time (30 minutes after meal time)
        final reminderTime = DateTime(
          now.year,
          now.month,
          now.day,
          mealTime.hour,
          mealTime.minute,
        ).add(const Duration(minutes: REMINDER_DELAY_MINUTES));

        // Only schedule if reminder time is in the future
        if (reminderTime.isAfter(now)) {
          await _scheduleNotification(
            notificationId: MEAL_NOTIFICATION_BASE_ID + meal.index,
            title: NotificationConstants.mealReminderTitle,
            body: NotificationConstants.getMealReminderBody(meal.displayLabel),
            scheduledTime: reminderTime,
          );
        }
      }
    } catch (e) {
    }
  }

  /// Cancel a specific meal's reminder notification.
  /// 
  /// Call this when a user uploads/checks off a meal to prevent
  /// the reminder from being sent.
  /// 
  /// @param meal The meal type to cancel the reminder for
  Future<void> cancelMealReminder(Meals meal) async {
    if (!isSupported) return;

    try {
      final notificationId = MEAL_NOTIFICATION_BASE_ID + meal.index;
      await _notifications.cancel(notificationId);
    } catch (e) {
    }
  }

  /// Cancel all meal reminder notifications.
  /// 
  /// Call this when user disables meal notifications.
  Future<void> cancelAllMealReminders() async {
    if (!isSupported) return;

    try {
      // Cancel all possible meal notifications
      for (final meal in Meals.dietValues) {
        final notificationId = MEAL_NOTIFICATION_BASE_ID + meal.index;
        await _notifications.cancel(notificationId);
      }
    } catch (e) {
    }
  }

  /// Fetch user's meal times from their latest diet document.
  ///
  /// Bugünün menüsü ve saatleri "Planım" ile sohbetteki öğün seçicinin
  /// kullandığı kuralla okunur ([DietMenu.forDate]); hatırlatma saati ekranda
  /// görünen saatle hep aynıdır. Diyette saati yazılmamış öğüne hatırlatma
  /// kurulmaz: varsayılan saat uydurulmaz.
  Future<Map<Meals, TimeOfDay>> _fetchUserMealTimes(String userId) async {
    Map<Meals, TimeOfDay> mealTimes = {};

    try {
      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('dietLists')
          .orderBy('uploadTime', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return mealTimes;
      }

      final data = querySnapshot.docs.first.data();
      final DietMenu menu = DietMenu.forDate(
        weekday: DietMenu.fromSubtitles(
            data['subtitles'] as Map<String, dynamic>?),
        weekend: DietMenu.fromSubtitles(
            data['weekendSubtitles'] as Map<String, dynamic>?),
        date: DateTime.now(),
      );

      for (final Meals meal in menu.mealsWithContent) {
        final TimeOfDay? time = menu.timeOf(meal);
        if (time != null) mealTimes[meal] = time;
      }
    } catch (e) {
    }

    return mealTimes;
  }

  /// Bugün hatırlatması kurulmayacak öğünler, gün dokümanının verisinden
  /// ([dayData]): işaretlenmiş (`meals.<öğün>: true`) ya da o gün fotoğrafı
  /// yüklenmiş ([REMINDER_CANCELLED_FIELD]) öğünler.
  static Set<Meals> mealsWithoutReminder(Map<String, dynamic>? dayData) {
    final Set<Meals> skipped = {};
    for (final String field in const ['meals', REMINDER_CANCELLED_FIELD]) {
      final Object? flags = dayData?[field];
      if (flags is! Map) continue;
      for (final MapEntry<dynamic, dynamic> entry in flags.entries) {
        final Object? name = entry.key;
        final Meals? meal = name is String ? Meals.fromName(name) : null;
        if (meal != null && entry.value == true) skipped.add(meal);
      }
    }
    return skipped;
  }

  /// Bugün hatırlatması kurulmayacak öğünler ([mealsWithoutReminder]).
  Future<Set<Meals>> _fetchTodaySkippedMeals(String userId) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('meals')
          .doc(today)
          .get();
      return mealsWithoutReminder(doc.data());
    } catch (e) {
      return {};
    }
  }

  /// Schedule a local notification.
  Future<void> _scheduleNotification({
    required int notificationId,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        MEAL_REMINDER_CHANNEL,
        NotificationConstants.mealReminderChannelName,
        channelDescription: NotificationConstants.mealReminderChannelDescription,
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

      await _notifications.zonedSchedule(
        notificationId,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
//androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
    }
  }
}

