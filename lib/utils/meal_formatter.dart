import 'package:flutter/material.dart';

import '../models/special_line_model.dart';

// ---------------------------------------------------------------------------
// Recipe reference marker ("*tarifi ektedir")
//
// When a diet content line references an attached recipe (e.g. a line like
// "Kek (*tarifi ektedir)"), that phrase is rendered as a tappable link that
// opens the diet's attached recipe PDF. The admin attaches the PDF during the
// diet import flow whenever this phrase is detected.
// ---------------------------------------------------------------------------

/// Matches the recipe reference phrase ("*tarifi ektedir") inside a diet
/// content line. Tolerant of an optional leading asterisk, flexible spacing
/// between the two words and upper/lower case — including the Turkish dotted
/// and dotless i variants (i / ı / I / İ).
final RegExp kRecipeMarkerRegex = RegExp(
  r'\*?\s*[tT][aA][rR][iıIİ][fF][iıIİ]\s+[eE][kK][tT][eE][dD][iıIİ][rR]',
);

/// True when [line] references an attached recipe ("*tarifi ektedir").
bool lineHasRecipeMarker(String? line) =>
    line != null && kRecipeMarkerRegex.hasMatch(line);

/// The three parts a recipe-marker line splits into: the text before the
/// marker, the marker phrase itself, and the text after it. Either side may be
/// empty (e.g. when the whole line is just the marker).
class RecipeMarkerParts {
  final String before;
  final String marker;
  final String after;

  const RecipeMarkerParts(this.before, this.marker, this.after);
}

/// Splits [line] around the recipe marker, or returns null when the line has no
/// recipe reference.
RecipeMarkerParts? splitRecipeMarker(String line) {
  final m = kRecipeMarkerRegex.firstMatch(line);
  if (m == null) return null;
  return RecipeMarkerParts(
    line.substring(0, m.start),
    line.substring(m.start, m.end),
    line.substring(m.end),
  );
}

// ---------------------------------------------------------------------------
// Legacy constants (kept for backward compatibility with files that already
// import them — e.g. add_diet_dialog.dart and the old file_handler_page.dart).
// New code should rely on [SpecialLinesRegistry] / [SpecialLineConfig] instead.
// ---------------------------------------------------------------------------
const String VEYA_MARKER = 'Veya';
const String HAFTADA_MARKER_PREFIX = 'Haftada';
const List<String> SPECIAL_MARKERS = [VEYA_MARKER, HAFTADA_MARKER_PREFIX];

final RegExp VEYA_OPTION_SEPARATOR_REGEX = RegExp(r'^Veya\s+');
final RegExp HAFTADA_OPTION_SEPARATOR_REGEX = RegExp(r'^Haftada\s+\d+\s*');

/// Returns true when [content] is a "marker + inline content" line for any
/// configured special line (built-in or admin-defined).
///
/// Mirrors the original `isSpecialMarkerSeparator`: any of the per-config
/// separator regexes (`^Veya\s+`, `^Haftada\s+\d+\s*`, …) hits.
bool isSpecialMarkerSeparator(String content) {
  for (final cfg in SpecialLinesRegistry.all) {
    if (cfg.isSeparator(content)) return true;
  }
  return false;
}

/// Lax standalone check (matches the original `isStandaloneMarker`):
/// trimmed content equals the prefix exactly OR begins with `"$prefix "`.
/// Used by callers that need to recognize an option-starting marker line.
bool isStandaloneMarker(String content) {
  for (final cfg in SpecialLinesRegistry.all) {
    if (cfg.isStandalone(content)) return true;
  }
  return false;
}

/// Strict standalone check that mirrors the original
/// `SPECIAL_MARKERS.contains(content.trim())`: trimmed content equals one of
/// the configured prefixes exactly.
///
/// The renderers use this — rather than the lax [isStandaloneMarker] — to
/// decide whether to drop the row entirely instead of stripping a marker.
bool isExactStandaloneMarker(String content) {
  for (final cfg in SpecialLinesRegistry.all) {
    if (cfg.isExactMarker(content)) return true;
  }
  return false;
}

/// Backward-compatible alias for [isSpecialMarkerSeparator] that only checks
/// the "Veya" prefix; preserved for callers that explicitly need that.
bool isVeyaOptionSeparator(String content) =>
    SpecialLinesRegistry.veya.isSeparator(content);

/// Strips the matched marker portion off a separator line and returns the
/// trailing content. Returns [content] unchanged when no marker matches.
///
/// Uses the LONGEST separator match so overlapping markers strip correctly
/// (e.g. "Haftada 1 gün" is removed whole rather than leaving "gün" behind).
String extractContentAfterMarker(String content) {
  SpecialLineConfig? best;
  int bestLen = -1;
  for (final cfg in SpecialLinesRegistry.all) {
    final len = cfg.matchLength(content);
    if (len > bestLen) {
      bestLen = len;
      best = cfg;
    }
  }
  if (best != null) {
    return content.replaceFirst(best.separatorRegex, '');
  }
  return content;
}

String extractContentAfterVeya(String content) =>
    extractContentAfterMarker(content);

/// Returns the [SpecialLineConfig] whose marker matches [content], or null.
SpecialLineConfig? _matchingConfig(String content) =>
    SpecialLinesRegistry.matching(content);

/// Best-effort label to display in the section divider for the option that
/// starts at a marker line. Falls back to "Veya" so the existing visual
/// behavior is preserved when no marker matches.
String _dividerLabelFor(String markerContent) {
  final cfg = _matchingConfig(markerContent);
  if (cfg != null) return cfg.extractMarkerLabel(markerContent);
  return VEYA_MARKER;
}

/// Utility class for formatting meal content for display.
///
/// Each call inspects the current [SpecialLinesRegistry] so admin-configured
/// markers render with the same styling as the built-in "Veya" / "Haftada X"
/// separators.
class MealFormatter {
  /// Formats a list of meal content items into widgets, inserting a styled
  /// divider before each new option introduced by a special marker line.
  ///
  /// When [onRecipeTap] is provided, any line containing the recipe reference
  /// phrase ("*tarifi ektedir") renders that phrase as a tappable link that
  /// invokes [onRecipeTap] (used to open the diet's attached recipe PDF). When
  /// it is null the phrase is shown as plain text.
  static List<Widget> formatMealContentWithOptions(
    List<dynamic> contentList, {
    double fontSize = 16,
    VoidCallback? onRecipeTap,
  }) {
    final List<Widget> formatted = [];
    final List<int> optionStartIndices = _collectOptionStarts(contentList);

    for (int optionIndex = 0;
        optionIndex < optionStartIndices.length;
        optionIndex++) {
      if (optionIndex > 0) {
        final markerItem = contentList[optionStartIndices[optionIndex]];
        final markerContent =
            (markerItem is Map) ? (markerItem['content'] ?? '') : markerItem.toString();
        final dividerText = _dividerLabelFor(markerContent.toString());

        formatted.add(const SizedBox(height: 8));
        formatted.add(Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                dividerText,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ));
        formatted.add(const SizedBox(height: 8));
      }

      final int startIdx = optionStartIndices[optionIndex];
      final int endIdx = (optionIndex < optionStartIndices.length - 1)
          ? optionStartIndices[optionIndex + 1]
          : contentList.length;

      for (int i = startIdx; i < endIdx; i++) {
        final item = contentList[i];
        String displayContent =
            (item is Map) ? (item['content'] ?? '').toString() : item.toString();

        // Strict skip — original was `SPECIAL_MARKERS.contains(t.trim())`.
        if (isExactStandaloneMarker(displayContent)) {
          continue;
        } else if (isSpecialMarkerSeparator(displayContent)) {
          displayContent = extractContentAfterMarker(displayContent);
        }

        formatted.add(_contentLineWidget(displayContent, fontSize, onRecipeTap));
      }
    }

    return formatted;
  }

  /// Builds a single content-line widget. When [onRecipeTap] is non-null and
  /// [text] contains the recipe phrase, the phrase is rendered as a tappable,
  /// underlined link (with a small PDF icon); otherwise a plain [Text].
  static Widget _contentLineWidget(
    String text,
    double fontSize,
    VoidCallback? onRecipeTap,
  ) {
    final parts = onRecipeTap == null ? null : splitRecipeMarker(text);

    if (parts == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Text(text, style: TextStyle(fontSize: fontSize)),
      );
    }

    final linkColor = Colors.blue.shade700;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        onTap: onRecipeTap,
        borderRadius: BorderRadius.circular(4),
        child: Text.rich(
          TextSpan(
            style: TextStyle(fontSize: fontSize),
            children: [
              if (parts.before.isNotEmpty) TextSpan(text: parts.before),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.picture_as_pdf,
                    size: fontSize + 2,
                    color: linkColor,
                  ),
                ),
              ),
              TextSpan(
                text: parts.marker.trim(),
                style: TextStyle(
                  color: linkColor,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
              if (parts.after.isNotEmpty) TextSpan(text: parts.after),
            ],
          ),
        ),
      ),
    );
  }

  /// Returns a [RichText] widget that formats meal content with options.
  static Widget formatMealContentAsRichText(List<dynamic> contentList) {
    final List<TextSpan> spans = [];
    final List<int> optionStartIndices = _collectOptionStarts(contentList);

    for (int optionIndex = 0;
        optionIndex < optionStartIndices.length;
        optionIndex++) {
      if (optionIndex > 0) {
        final markerItem = contentList[optionStartIndices[optionIndex]];
        final markerContent =
            (markerItem is Map) ? (markerItem['content'] ?? '') : markerItem.toString();
        final dividerText = _dividerLabelFor(markerContent.toString());

        spans.add(const TextSpan(text: '\n'));
        spans.add(TextSpan(
          text: '$dividerText\n',
          style: TextStyle(
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(const TextSpan(text: '\n'));
      }

      final int startIdx = optionStartIndices[optionIndex];
      final int endIdx = (optionIndex < optionStartIndices.length - 1)
          ? optionStartIndices[optionIndex + 1]
          : contentList.length;

      for (int i = startIdx; i < endIdx; i++) {
        final item = contentList[i];
        String displayContent =
            (item is Map) ? (item['content'] ?? '').toString() : item.toString();

        if (isExactStandaloneMarker(displayContent)) {
          continue;
        } else if (isSpecialMarkerSeparator(displayContent)) {
          displayContent = extractContentAfterMarker(displayContent);
        }

        spans.add(TextSpan(
          text: '$displayContent\n',
          style: const TextStyle(height: 1.5),
        ));
      }
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black, fontSize: 16),
        children: spans,
      ),
    );
  }

  /// Plain text version of the formatted content.
  static String formatMealContentAsString(List<dynamic> contentList) {
    final buffer = StringBuffer();
    final optionStartIndices = _collectOptionStarts(contentList);

    for (int optionIndex = 0;
        optionIndex < optionStartIndices.length;
        optionIndex++) {
      if (optionIndex > 0) {
        final markerItem = contentList[optionStartIndices[optionIndex]];
        final markerContent =
            (markerItem is Map) ? (markerItem['content'] ?? '') : markerItem.toString();
        final dividerText = _dividerLabelFor(markerContent.toString());

        buffer.writeln();
        buffer.writeln(dividerText);
        buffer.writeln();
      }

      final int startIdx = optionStartIndices[optionIndex];
      final int endIdx = (optionIndex < optionStartIndices.length - 1)
          ? optionStartIndices[optionIndex + 1]
          : contentList.length;

      for (int i = startIdx; i < endIdx; i++) {
        final item = contentList[i];
        String displayContent =
            (item is Map) ? (item['content'] ?? '').toString() : item.toString();

        if (isExactStandaloneMarker(displayContent)) {
          continue;
        } else if (isSpecialMarkerSeparator(displayContent)) {
          displayContent = extractContentAfterMarker(displayContent);
        }

        buffer.writeln(displayContent);
      }
    }

    return buffer.toString();
  }

  /// Identifies the indices in [contentList] that begin a new option block.
  /// The first item is always treated as an option start; subsequent option
  /// starts are any line recognized as a special marker (standalone or
  /// separator).
  static List<int> _collectOptionStarts(List<dynamic> contentList) {
    final List<int> starts = [];
    for (int i = 0; i < contentList.length; i++) {
      final item = contentList[i];
      final content =
          (item is Map) ? (item['content'] ?? '').toString() : item.toString();

      if (i == 0) {
        starts.add(i);
      } else if (isStandaloneMarker(content) || isSpecialMarkerSeparator(content)) {
        starts.add(i);
      }
    }
    return starts;
  }
}
