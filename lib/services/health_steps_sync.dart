import 'package:shared_preferences/shared_preferences.dart';

import '../providers/daily_data_provider.dart';
import 'fcm_service.dart';
import 'health_steps_service.dart';

class HealthStepsSync {
  HealthStepsSync({HealthStepsService? health, DateTime Function()? clock})
      : _health = health ?? HealthStepsService.shared,
        _clock = clock ?? DateTime.now;

  static final HealthStepsSync shared = HealthStepsSync();

  static const Duration minInterval = Duration(minutes: 5);
  static const int maxDaysBack = 6;
  static const String lastSyncKeyPrefix = 'healthStepsLastSync_';

  final HealthStepsService _health;
  final DateTime Function() _clock;
  Future<void>? _running;

  Future<void> syncIfDue(String userId, DailyDataProvider provider) {
    if (FcmService.isAdmin(userId) || !_health.isSupported) {
      return Future<void>.value();
    }
    return _running ??=
        _sync(userId, provider).whenComplete(() => _running = null);
  }

  Future<void> _sync(String userId, DailyDataProvider provider) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String key = '$lastSyncKeyPrefix$userId';
      final DateTime now = _clock();
      final int? lastMillis = prefs.getInt(key);
      final DateTime? last = lastMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastMillis);
      if (last != null &&
          !now.isBefore(last) &&
          now.difference(last) < minInterval) {
        return;
      }

      final List<DateTime> days = _daysToSync(now, last);
      final List<int?> steps = await Future.wait(days.map(_health.stepsForDay));
      bool found = false;
      for (int i = 0; i < days.length; i++) {
        final int? value = steps[i];
        if (value == null || value <= 0) continue;
        found = true;
        await provider.saveStepsIfHigher(userId, days[i], value);
      }
      if (found) {
        await prefs.setInt(key, now.millisecondsSinceEpoch);
      }
    } catch (_) {}
  }

  static List<DateTime> _daysToSync(DateTime now, DateTime? last) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime earliest =
        DateTime(today.year, today.month, today.day - maxDaysBack);
    final DateTime yesterday =
        DateTime(today.year, today.month, today.day - 1);
    DateTime start = earliest;
    if (last != null) {
      final DateTime lastDay = DateTime(last.year, last.month, last.day);
      start = lastDay.isBefore(yesterday) ? lastDay : yesterday;
      if (start.isBefore(earliest)) start = earliest;
    }
    return <DateTime>[
      for (DateTime day = start;
          !day.isAfter(today);
          day = DateTime(day.year, day.month, day.day + 1))
        day,
    ];
  }
}
