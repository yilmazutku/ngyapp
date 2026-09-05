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
    final String w = (water ?? '').trim();
    final String s = (sport ?? '').trim();
    if (w.isNotEmpty) list.add(DietGoal(DietGoalType.water, w));
    if (s.isNotEmpty) list.add(DietGoal(DietGoalType.sport, s));
    return list;
  }

  bool get hasAny => entries.isNotEmpty;
}

/// Detects whether [line] is a diet goal line, i.e. starts with "Su Hedefi:" or
/// "Spor Hedefi:".
///
/// Matching is tolerant of casing, spacing and Turkish characters (see
/// [lettersOnly]), so "SU HEDEFİ:", "Su Hedefi :" and "su hedefi:" all match.
/// The text after the colon is not inspected; the whole line is kept verbatim
/// by the caller.
DietGoalType? detectDietGoalLine(String line) {
  final int colonIndex = line.indexOf(':');
  if (colonIndex <= 0) return null;

  final String key = lettersOnly(line.substring(0, colonIndex));
  if (key == 'suhedefi') return DietGoalType.water;
  if (key == 'sporhedefi') return DietGoalType.sport;
  return null;
}
