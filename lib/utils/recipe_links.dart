import 'package:flutter/foundation.dart';

import '../models/diet_recipe.dart';
import '../models/diet_section.dart';

// ---------------------------------------------------------------------------
// Recipe reference marker ("*tarifi ektedir")
//
// When a diet content line references an attached recipe (e.g. a line like
// "Kek (*tarifi ektedir)"), that phrase is rendered as a tappable link that
// opens the recipe PDF attached to that link (see [DietRecipe]). The admin
// attaches a PDF to every such phrase during the diet import flow.
// ---------------------------------------------------------------------------

/// Matches the recipe reference phrase ("*tarifi ektedir") inside a diet
/// content line. Tolerant of an optional leading asterisk, flexible spacing
/// between the two words and upper/lower case — including the Turkish dotted
/// and dotless i variants (i / ı / I / İ).
///
/// The match starts at the asterisk when one is present (so only the "*…"
/// phrase, not the text before it, is turned into the link), and at the word
/// "tarifi" otherwise.
final RegExp kRecipeMarkerRegex = RegExp(
  r'(?:\*\s*)?[tT][aA][rR][iıIİ][fF][iıIİ]\s+[eE][kK][tT][eE][dD][iıIİ][rR]',
);

int recipeMarkerCount(String? line) =>
    line == null ? 0 : kRecipeMarkerRegex.allMatches(line).length;

List<List<Object?>> distributeLineRecipes(
  List<Object?> recipes,
  List<String> lines,
) {
  final List<List<Object?>> perLine = <List<Object?>>[];
  int next = 0;
  for (int i = 0; i < lines.length; i++) {
    final int wanted = next + recipeMarkerCount(lines[i]);
    final int end = i == lines.length - 1 || wanted > recipes.length
        ? recipes.length
        : wanted;
    perLine.add(recipes.sublist(next, end));
    next = end;
  }
  return perLine;
}

typedef RecipeLinkHandler = VoidCallback? Function(DietRecipe? recipe);

class RecipeLineSegment {
  final String text;
  final bool isMarker;

  const RecipeLineSegment(this.text, {this.isMarker = false});
}

List<RecipeLineSegment> splitRecipeMarkers(String line) {
  final List<RecipeLineSegment> segments = <RecipeLineSegment>[];
  int cursor = 0;
  for (final RegExpMatch match in kRecipeMarkerRegex.allMatches(line)) {
    final String before = _spacedBeforeMarker(line.substring(cursor, match.start));
    if (before.isNotEmpty) segments.add(RecipeLineSegment(before));
    segments.add(RecipeLineSegment(
      line.substring(match.start, match.end),
      isMarker: true,
    ));
    cursor = match.end;
  }
  if (segments.isEmpty) return segments;
  if (cursor < line.length) segments.add(RecipeLineSegment(line.substring(cursor)));
  return segments;
}

/// Gösterim düzeltmesi: "*tarifi ektedir" ifadesi kendisinden önceki metne
/// yapışık gelirse araya tek boşluk konur, birden fazla boşluk varsa tek
/// boşluğa indirilir. İfade parantez içindeyse boşluk parantezin soluna gider
/// ("Kek(*tarifi ektedir)" -> "Kek (*tarifi ektedir)"). Satır doğrudan ifadeyle
/// başlıyorsa başa boşluk eklenmez. Satırdaki her ifadeye uygulanır ve
/// tekrar uygulanabilir (idempotent).
String normalizeRecipeMarkerSpacing(String line) {
  final List<RecipeLineSegment> segments = splitRecipeMarkers(line);
  if (segments.isEmpty) return line;
  return segments.map((RecipeLineSegment segment) => segment.text).join();
}

/// Marker'ın solundaki metni tek boşlukla biter hâle getirir. Marker'a bitişik
/// açılış parantezleri ifadenin parçası sayılır, boşluk onların da soluna
/// konur.
String _spacedBeforeMarker(String before) {
  if (before.isEmpty) return before;

  int end = before.length;
  while (end > 0 && _isOpeningBracket(before[end - 1])) {
    end--;
  }

  final String head = before.substring(0, end).trimRight();
  final String brackets = before.substring(end);
  if (head.isEmpty) return brackets;
  return '$head $brackets';
}

bool _isOpeningBracket(String char) =>
    char == '(' || char == '[' || char == '{';

class RecipeLinkSlot {
  final DietSection section;
  final String mealName;
  final int lineIndex;
  final int linkIndex;
  final int linkCount;
  final String line;

  const RecipeLinkSlot({
    required this.section,
    required this.mealName,
    required this.lineIndex,
    required this.linkIndex,
    required this.linkCount,
    required this.line,
  });

  String get key => '${section.key}|$mealName|$lineIndex|$linkIndex';

  static List<RecipeLinkSlot> findIn(
    List<Map<String, dynamic>> meals,
    DietSection section,
  ) {
    final List<RecipeLinkSlot> slots = <RecipeLinkSlot>[];
    for (final Map<String, dynamic> meal in meals) {
      final Object? content = meal['content'];
      if (content is! List) continue;
      for (int lineIndex = 0; lineIndex < content.length; lineIndex++) {
        final Object? item = content[lineIndex];
        final String line = item is Map
            ? (item['content']?.toString() ?? '')
            : item.toString();
        final int linkCount = recipeMarkerCount(line);
        for (int linkIndex = 0; linkIndex < linkCount; linkIndex++) {
          slots.add(RecipeLinkSlot(
            section: section,
            mealName: '${meal['name']}',
            lineIndex: lineIndex,
            linkIndex: linkIndex,
            linkCount: linkCount,
            line: line,
          ));
        }
      }
    }
    return slots;
  }

  static List<Map<String, String>?>? recipesOfLine({
    required List<RecipeLinkSlot> slots,
    required Map<String, DietRecipe> recipes,
    required DietSection section,
    required String mealName,
    required int lineIndex,
  }) {
    final List<Map<String, String>?> line = <Map<String, String>?>[
      for (final RecipeLinkSlot slot in slots)
        if (slot.section == section &&
            slot.mealName == mealName &&
            slot.lineIndex == lineIndex)
          recipes[slot.key]?.toMap(),
    ];
    return line.any((Map<String, String>? recipe) => recipe != null)
        ? line
        : null;
  }
}
