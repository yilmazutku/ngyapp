import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/diet_section.dart';
import '../models/meal_model.dart';

/// One menu of a diet plan (weekday or weekend): the content lines and the
/// time of each meal, resolved to the [Meals] enum.
class DietMenu {
  final Map<Meals, List<String>> contents;

  /// Diyette yazılı öğün saatleri. Saati yazılmamış (ya da okunamayan) öğün
  /// bu map'te yoktur: varsayılan saat uydurulmaz, ekranda "-" görünür
  /// ([formatMealTime]).
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

  /// Öğünün diyetteki saati; diyette yazılı değilse null.
  TimeOfDay? timeOf(Meals meal) => times[meal];

  /// [date] günü geçerli menü: diyette hafta sonu menüsü varsa hafta sonu
  /// günlerinde o, diğer günlerde hafta içi menüsü ("Planım"daki kural).
  static DietMenu forDate({
    required DietMenu weekday,
    required DietMenu weekend,
    required DateTime date,
  }) =>
      weekend.hasContent && isWeekendDate(date) ? weekend : weekday;

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
      final TimeOfDay? time = parseMealTime(mealData['time']?.toString());
      if (time != null) times[meal] = time;
    }

    return DietMenu(contents: contents, times: times);
  }
}

/// Converts a stored time string ("HH:mm" or "HH.mm") to a [TimeOfDay].
///
/// Returns null when the time is missing or unparseable: no default time is
/// ever made up, the meal is shown without a time ("-", see
/// [formatMealTime]) and gets no reminder.
TimeOfDay? parseMealTime(String? timeString) {
  final String value = timeString?.trim() ?? '';
  if (value.isEmpty) return null;

  try {
    if (value.contains(':')) {
      final parts = value.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0].trim());
        final minute = int.tryParse(parts[1].trim());
        if (hour != null &&
            minute != null &&
            hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } else {
      return TimeOfDay.fromDateTime(DateFormat('HH:mm').parse(value));
    }
  } catch (e) {
  }
  return null;
}

class MealHeaderLine {
  final String? time;
  final String inlineContent;

  const MealHeaderLine({required this.time, required this.inlineContent});
}

final RegExp _kMealHeaderTimeRegex =
    RegExp(r'\(\s*(\d{1,2})\s*[.:]\s*(\d{2})\s*\)');

MealHeaderLine parseMealHeaderLine(String line) {
  final RegExpMatch? timeMatch = _kMealHeaderTimeRegex.firstMatch(line);

  int separatorIdx = line.indexOf(':');
  if (timeMatch != null &&
      separatorIdx >= timeMatch.start &&
      separatorIdx < timeMatch.end) {
    separatorIdx = line.indexOf(':', timeMatch.end);
  }

  String? time;
  if (timeMatch != null &&
      (separatorIdx == -1 || timeMatch.start < separatorIdx)) {
    final int hour = int.parse(timeMatch.group(1)!);
    final int minute = int.parse(timeMatch.group(2)!);
    if (hour <= 23 && minute <= 59) {
      time = '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}';
    }
  }

  return MealHeaderLine(
    time: time,
    inlineContent:
        separatorIdx == -1 ? '' : line.substring(separatorIdx + 1).trim(),
  );
}

/// Öğün saati yazılı olmadığında gösterilen işaret.
const String kMissingMealTimeText = '-';

/// Öğün saatinin ekrandaki hâli: "12:30"; diyette saat yoksa "-".
String formatMealTime(TimeOfDay? time) =>
    time == null ? kMissingMealTimeText : formatTimeOfDay24(time);

String formatTimeOfDay24(TimeOfDay time) {
  final now = DateTime.now();
  final dateTime =
      DateTime(now.year, now.month, now.day, time.hour, time.minute);
  return DateFormat('HH:mm').format(dateTime);
}
