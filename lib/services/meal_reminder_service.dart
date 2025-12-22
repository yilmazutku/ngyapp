import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../constants/app_constants.dart';
import '../models/logger.dart';
import '../models/meal_model.dart';

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

  final Logger _logger = Logger.forClass(MealReminderService);
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Minutes after meal time to send reminder
  static const int REMINDER_DELAY_MINUTES = NotificationConstants.mealReminderDelayMinutes;

  /// Notification channel for meal reminders
  static const String MEAL_REMINDER_CHANNEL = NotificationConstants.mealReminderChannelId;

  /// Base notification ID for meal reminders (each meal adds its index)
  static const int MEAL_NOTIFICATION_BASE_ID = 1000;

  bool _isInitialized = false;

  /// Check if local notifications are supported on this platform
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux;
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
    _logger.info('MealReminderService initialized');
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
  /// 
  /// @param userId The user's ID
  Future<void> scheduleMealReminders(String userId) async {
    final isReady = await _ensureInitialized();
    if (!isReady) {
      _logger.info('Meal reminders not supported on this platform');
      return;
    }

    try {
      // 1. Check if notifications are enabled for this user
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data();
      
      if (userData == null || userData['mealNotificationsEnabled'] != true) {
        _logger.info('Meal notifications disabled for user $userId');
        return;
      }

      // 2. Fetch the latest diet subtitles (meal times)
      final mealTimes = await _fetchUserMealTimes(userId);
      if (mealTimes.isEmpty) {
        _logger.info('No meal times found for user $userId');
        return;
      }

      // 3. Fetch today's meal states
      final mealStates = await _fetchTodayMealStates(userId);

      // 4. Schedule reminders for unchecked meals
      final now = DateTime.now();
      int scheduledCount = 0;

      for (final entry in mealTimes.entries) {
        final meal = entry.key;
        final mealTime = entry.value;

        // Skip if meal is already checked/uploaded
        if (mealStates[meal] == true) {
          _logger.debug('Meal ${meal.name} already checked, skipping');
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
          scheduledCount++;
          _logger.info('Scheduled reminder for ${meal.name} at $reminderTime');
        } else {
          _logger.debug('Reminder time for ${meal.name} has passed');
        }
      }

      _logger.info('Scheduled $scheduledCount meal reminders for user $userId');
    } catch (e) {
      _logger.err('Error scheduling meal reminders: $e');
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
      _logger.info('Cancelled reminder for ${meal.name}');
    } catch (e) {
      _logger.err('Error cancelling meal reminder: $e');
    }
  }

  /// Cancel all meal reminder notifications.
  /// 
  /// Call this when user disables meal notifications.
  Future<void> cancelAllMealReminders() async {
    if (!isSupported) return;

    try {
      // Cancel all possible meal notifications
      for (final meal in Meals.values) {
        final notificationId = MEAL_NOTIFICATION_BASE_ID + meal.index;
        await _notifications.cancel(notificationId);
      }
      _logger.info('Cancelled all meal reminders');
    } catch (e) {
      _logger.err('Error cancelling all meal reminders: $e');
    }
  }

  /// Fetch user's meal times from their latest diet document.
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
        _logger.info('No diet lists found for user $userId');
        return mealTimes;
      }

      final data = querySnapshot.docs.first.data();
      final subtitles = data['subtitles'] as Map<String, dynamic>?;

      if (subtitles == null) {
        _logger.warn('Diet list has no subtitles');
        return mealTimes;
      }

      for (final entry in subtitles.entries) {
        final mealName = entry.key;
        final mealData = entry.value as Map<String, dynamic>;
        final meal = Meals.fromName(mealName);

        if (meal == null) continue;

        // Check if content exists (meal is assigned to this user)
        final content = mealData['content'] as List<dynamic>?;
        if (content == null || content.isEmpty) continue;

        // Parse meal time
        final timeString = mealData['time'] as String?;
        TimeOfDay time = _parseDefaultTime(meal);

        if (timeString != null && timeString.isNotEmpty) {
          final parsedTime = _parseTimeString(timeString);
          if (parsedTime != null) {
            time = parsedTime;
          }
        }

        mealTimes[meal] = time;
      }
    } catch (e) {
      _logger.err('Error fetching user meal times: $e');
    }

    return mealTimes;
  }

  /// Fetch today's meal states (checked/unchecked) for a user.
  Future<Map<Meals, bool>> _fetchTodayMealStates(String userId) async {
    Map<Meals, bool> states = {
      for (final meal in Meals.values) meal: false,
    };

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('meals')
          .doc(today)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final meals = data?['meals'] as Map<String, dynamic>?;

        if (meals != null) {
          for (final entry in meals.entries) {
            final meal = Meals.fromName(entry.key);
            if (meal != null) {
              states[meal] = entry.value as bool? ?? false;
            }
          }
        }
      }
    } catch (e) {
      _logger.err('Error fetching meal states: $e');
    }

    return states;
  }

  /// Parse a time string (HH:mm format) into TimeOfDay.
  TimeOfDay? _parseTimeString(String timeString) {
    try {
      if (timeString.contains(':')) {
        final parts = timeString.split(':');
        if (parts.length >= 2) {
          final hour = int.tryParse(parts[0]);
          final minute = int.tryParse(parts[1]);
          if (hour != null && minute != null) {
            return TimeOfDay(hour: hour, minute: minute);
          }
        }
      }
    } catch (e) {
      _logger.err('Error parsing time string "$timeString": $e');
    }
    return null;
  }

  /// Get default time for a meal type.
  TimeOfDay _parseDefaultTime(Meals meal) {
    final parts = meal.defaultTime.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 12,
      minute: int.tryParse(parts[1]) ?? 0,
    );
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
      _logger.info('scheduled notification {}');
    } catch (e) {
      _logger.err('Error scheduling notification: $e');
    }
  }
}

