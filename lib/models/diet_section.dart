/// The two parts a diet plan can be split into: weekday (Hafta İçi) and
/// weekend (Hafta Sonu).
///
/// A diet document always has a weekday plan (persisted in the `subtitles`
/// field). It may optionally also have a weekend plan (persisted in the
/// `weekendSubtitles` field) when the imported Word document contained a
/// standalone `HAFTASONU` line separating the two menus.
enum DietSection {
  weekday('Hafta İçi', 'weekday'),
  weekend('Hafta Sonu', 'weekend');

  const DietSection(this.label, this.key);

  /// User-facing section title.
  final String label;

  /// Stable key (not currently persisted, but handy for widget keys / logs).
  final String key;
}

/// Returns true when [date] falls on Saturday or Sunday.
///
/// Used by the plan and reminder screens to decide which menu (weekday or
/// weekend) is the one the user should be eating / tracking today.
bool isWeekendDate(DateTime date) =>
    date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

/// Detects whether [line] is a standalone diet-section marker.
///
/// The Word import treats a line as a section switch only when the whole line
/// is just the marker word with no other words on it (e.g. "HAFTASONU",
/// "HAFTA SONU", "HAFTA SONU:"). A line that carries extra words such as
/// "HAFTASONU MENÜSÜ" is NOT a marker and is parsed as regular content, matching
/// the requirement that the marker line must contain no other word.
///
/// Matching is tolerant of casing, spacing and Turkish characters:
///   * "HAFTASONU" / "Hafta Sonu" / "hafta sonu" → [DietSection.weekend]
///   * "HAFTAİÇİ"  / "Hafta İçi"  / "hafta ici"  → [DietSection.weekday]
///
/// Returns null when [line] is not a section marker.
DietSection? detectDietSectionMarker(String line) {
  final normalized = lettersOnly(line);
  if (normalized == 'haftasonu') return DietSection.weekend;
  if (normalized == 'haftaici') return DietSection.weekday;
  return null;
}

/// Lower-cases [input], maps Turkish-specific letters to their ASCII base and
/// drops every non-letter character (spaces, punctuation, digits). So
/// "HAFTA SONU:" and "HAFTASONU" both collapse to "haftasonu".
///
/// Turkish-aware on purpose: Dart's [String.toLowerCase] maps "I" to "i"
/// rather than "ı", so a plain lower-case comparison would miss all-caps
/// Turkish words.
String lettersOnly(String input) {
  const turkish = {
    'ı': 'i',
    'İ': 'i',
    'I': 'i',
    'ç': 'c',
    'Ç': 'c',
    'ş': 's',
    'Ş': 's',
    'ğ': 'g',
    'Ğ': 'g',
    'ö': 'o',
    'Ö': 'o',
    'ü': 'u',
    'Ü': 'u',
  };

  final sb = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final mapped = turkish[ch];
    if (mapped != null) {
      sb.write(mapped);
      continue;
    }
    final lower = ch.toLowerCase();
    if (lower.length == 1) {
      final code = lower.codeUnitAt(0);
      if (code >= 0x61 && code <= 0x7A) sb.write(lower);
    }
  }
  return sb.toString();
}
