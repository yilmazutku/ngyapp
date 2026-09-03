import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/logger.dart';
import '../models/meal_model.dart';

final Logger dietMenuLogger = Logger('DietMenuParser');

/// One menu of a diet plan (weekday or weekend): the content lines and the
/// time of each meal, resolved to the [Meals] enum.
class DietMenu {
  final Map<Meals, List<String>> contents;
  final Map<Meals, TimeOfDay> times;

  const DietMenu({required this.contents, required this.times});

  const DietMenu.empty()
      : contents = const <Meals, List<String>>{},
        times = const <Meals, TimeOfDay>{};

  bool get hasContent => contents.values.any((lines) => lines.isNotEmpty);

  List<Meals> get mealsWithContent => Meals.dietValues
      .where((meal) => (contents[meal] ?? const <String>[]).isNotEmpty)
      .toList();

  List<String> linesOf(Meals meal) => contents[meal] ?? const <String>[];

  TimeOfDay timeOf(Meals meal, TimeOfDay fallback) => times[meal] ?? fallback;

  /// Parses a stored menu map (keyed by [Meals] enum name, each value holding
  /// `time` and `content`) as persisted on a diet document.
  factory DietMenu.fromSubtitles(Map<String, dynamic>? subtitles) {
    final Map<Meals, List<String>> contents = <Meals, List<String>>{};
    final Map<Meals, TimeOfDay> times = <Meals, TimeOfDay>{};

    if (subtitles == null) return DietMenu(contents: contents, times: times);

    for (final entry in subtitles.entries) {
      final meal = Meals.fromName(entry.key);
      if (meal == null) continue;

      final mealData = entry.value;
      if (mealData is! Map) {
        dietMenuLogger.warn('Skipping malformed meal entry: {}', [entry.key]);
        continue;
      }

      final rawContent = mealData['content'];
      contents[meal] = rawContent is List
          ? rawContent
              .map((item) => item is Map
                  ? (item['content'] ?? '').toString()
                  : item.toString())
              .where((line) => line.isNotEmpty)
              .toList()
          : <String>[];
      times[meal] = parseMealTime(mealData['time']?.toString());
    }

    return DietMenu(contents: contents, times: times);
  }
}

/// Converts a stored time string ("HH:mm" or "HH.mm") to a [TimeOfDay],
/// defaulting to midnight when missing or unparseable.
TimeOfDay parseMealTime(String? timeString) {
  if (timeString == null || timeString.isEmpty) {
    return const TimeOfDay(hour: 0, minute: 0);
  }
  try {
    if (timeString.contains(':')) {
      final parts = timeString.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0].trim());
        final minute = int.tryParse(parts[1].trim());
        if (hour != null && minute != null) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } else {
      return TimeOfDay.fromDateTime(DateFormat('HH:mm').parse(timeString));
    }
  } catch (e) {
    dietMenuLogger
        .err('Error when parsing the time of dietlist:{}', [e.toString()]);
  }
  return const TimeOfDay(hour: 0, minute: 0);
}

String formatTimeOfDay24(TimeOfDay time) {
  final now = DateTime.now();
  final dateTime =
      DateTime(now.year, now.month, now.day, time.hour, time.minute);
  return DateFormat('HH:mm').format(dateTime);
}
