import 'diet_section.dart' show lettersOnly;

/// The goal lines a diet document can carry above its meals.
enum DietGoalType { water, sport }

/// One goal line, kept verbatim as written in the imported Word document.
class DietGoal {
  final DietGoalType type;
  final String line;

  const DietGoal(this.type, this.line);
}

/// The water / sport goal lines of a diet, shown above the first meal on the
/// user's plan. Either one may be absent.
class DietGoals {
  final String? water;
  final String? sport;

  const DietGoals({this.water, this.sport});

  const DietGoals.empty()
      : water = null,
        sport = null;

  /// The goals that are actually present, in the order they are displayed.
  List<DietGoal> get entries {
    final List<DietGoal> list = [];
    final String w = _ownPart(water, DietGoalType.water);
    final String s = _ownPart(sport, DietGoalType.sport);
    if (w.isNotEmpty) list.add(DietGoal(DietGoalType.water, w));
    if (s.isNotEmpty) list.add(DietGoal(DietGoalType.sport, s));
    return list;
  }

  /// Keeps only the [type] part of a stored goal.
  ///
  /// Belgeler iki hedefi tek paragrafa yapıştırabiliyor ("Su Hedefi: ...Spor
  /// Hedefi: ...") ve bunu tekrarlayabiliyor. Kayıtlı metin burada yeniden
  /// bölünür ve o türe ait ilk parça gösterilir; böylece daha önce yanlış
  /// kaydedilmiş diyetler de belge yeniden yüklenmeden doğru görünür.
  /// İçinde hiç işaret olmayan bir değer olduğu gibi kullanılır.
  static String _ownPart(String? raw, DietGoalType type) {
    final String text = (raw ?? '').trim();
    if (text.isEmpty) return '';
    for (final DietGoal goal in extractDietGoals(text)) {
      if (goal.type == type) return goal.line;
    }
    return text;
  }

  bool get hasAny => entries.isNotEmpty;
}

/// Goal keys as [lettersOnly] normalizes them, and the length of the longest
/// one: the backwards scan for a marker gives up once it has collected more
/// letters than that.
const String _waterKey = 'suhedefi';
const String _sportKey = 'sporhedefi';
const int _maxGoalKeyLength = 10;

/// Splits [line] into the goal segments it carries, each kept verbatim.
///
/// Returns an empty list unless the line *starts* with a goal marker, so a
/// regular content line is never mistaken for a goal. Beyond the first marker
/// the whole line is scanned: a document sometimes glues both goals into one
/// paragraph ("Su Hedefi: ...Spor Hedefi: ...") and may even repeat the pair,
/// so every marker starts a new segment that runs up to the next marker. The
/// caller decides what to do with repeats.
///
/// Matching is tolerant of casing, spacing and Turkish characters (see
/// [lettersOnly]), so "SU HEDEFİ:", "Su Hedefi :" and "su hedefi:" all match.
/// The text after the colon is not inspected.
List<DietGoal> extractDietGoals(String line) {
  final List<_GoalMarker> markers = _goalMarkers(line);
  if (markers.isEmpty || markers.first.start != 0) return const [];

  final List<DietGoal> goals = [];
  for (int i = 0; i < markers.length; i++) {
    final int end = i + 1 < markers.length ? markers[i + 1].start : line.length;
    final String segment = line.substring(markers[i].start, end).trim();
    if (segment.isNotEmpty) goals.add(DietGoal(markers[i].type, segment));
  }
  return goals;
}

/// Where a goal marker starts inside a line, and which goal it opens.
class _GoalMarker {
  final DietGoalType type;
  final int start;

  const _GoalMarker(this.type, this.start);
}

/// Every goal marker in [line], in the order they appear.
List<_GoalMarker> _goalMarkers(String line) {
  final List<_GoalMarker> markers = [];
  int colon = line.indexOf(':');
  while (colon >= 0) {
    final _GoalMarker? marker = _markerEndingAt(line, colon);
    if (marker != null) markers.add(marker);
    colon = line.indexOf(':', colon + 1);
  }
  return markers;
}

/// The goal marker ending at [colonIndex], or null when the text before the
/// colon is not one. Walks backwards from the colon so the same [lettersOnly]
/// tolerance applies wherever the marker sits in the line; the scan stops as
/// soon as it has read more letters than the longest key, which can no longer
/// match.
_GoalMarker? _markerEndingAt(String line, int colonIndex) {
  for (int start = colonIndex - 1; start >= 0; start--) {
    final String key = lettersOnly(line.substring(start, colonIndex));
    if (key.length > _maxGoalKeyLength) return null;
    if (key == _waterKey) return _GoalMarker(DietGoalType.water, start);
    if (key == _sportKey) return _GoalMarker(DietGoalType.sport, start);
  }
  return null;
}
