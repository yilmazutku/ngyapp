import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/diet_recipe.dart';
import '../models/special_line_model.dart';
import 'recipe_links.dart';

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
  if (cfg == null) return VEYA_MARKER;
  // docx import glues markers to tabs, so collapse any inner whitespace run to
  // a single space ("Haftada 4 gün\t\t2" -> "Haftada 4 gün 2").
  return cfg
      .extractMarkerLabel(markerContent)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
  /// When [onRecipeLink] is provided, every recipe reference phrase
  /// ("*tarifi ektedir") of a line asks it for its tap action, passing the
  /// recipe PDF attached to that phrase (the item's `recipes` list, see
  /// [DietRecipe]); a phrase whose action is null, or every phrase when
  /// [onRecipeLink] is null, is shown as plain text.
  static List<Widget> formatMealContentWithOptions(
    List<dynamic> contentList, {
    double fontSize = 16,
    RecipeLinkHandler? onRecipeLink,
  }) {
    final List<Widget> formatted = [];
    final List<int> optionStartIndices = _collectOptionStarts(contentList);

    for (int optionIndex = 0;
        optionIndex < optionStartIndices.length;
        optionIndex++) {
      final String markerContent =
          _rawContentOf(contentList[optionStartIndices[optionIndex]]);
      if (_isOptionMarkerLine(markerContent)) {
        final dividerText = _dividerLabelFor(markerContent);

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
        final String? displayContent = _displayContentFor(contentList[i]);
        if (displayContent == null) continue;

        formatted.add(_contentLineWidget(
          displayContent,
          _recipesOf(contentList[i]),
          fontSize,
          onRecipeLink,
        ));
      }
    }

    return formatted;
  }

  /// Builds a single content-line widget. When [onRecipeLink] gives an action
  /// for a recipe phrase of [text], ONLY that phrase ("*…tarifi ektedir") is
  /// rendered as a tappable, underlined link — the rest of the line stays
  /// plain, non-tappable text. Otherwise a plain [Text].
  static Widget _contentLineWidget(
    String text,
    List<DietRecipe?> recipes,
    double fontSize,
    RecipeLinkHandler? onRecipeLink,
  ) {
    final List<RecipeLineSegment> segments = onRecipeLink == null
        ? const <RecipeLineSegment>[]
        : splitRecipeMarkers(text);
    final int markerCount =
        segments.where((RecipeLineSegment segment) => segment.isMarker).length;
    final List<VoidCallback?> markerTaps = <VoidCallback?>[
      for (int i = 0; i < markerCount; i++)
        onRecipeLink!(i < recipes.length ? recipes[i] : null),
    ];

    if (markerTaps.every((VoidCallback? onTap) => onTap == null)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Text(text, style: TextStyle(fontSize: fontSize)),
      );
    }

    return _RecipeContentLine(
      segments: segments,
      markerTaps: markerTaps,
      fontSize: fontSize,
    );
  }

  static List<DietRecipe?> _recipesOf(dynamic item) => item is Map
      ? DietRecipe.listFrom(item[DietRecipe.lineField])
      : const <DietRecipe?>[];

  /// Returns a [RichText] widget that formats meal content with options.
  static Widget formatMealContentAsRichText(List<dynamic> contentList) {
    final List<TextSpan> spans = [];
    final List<int> optionStartIndices = _collectOptionStarts(contentList);

    for (int optionIndex = 0;
        optionIndex < optionStartIndices.length;
        optionIndex++) {
      final String markerContent =
          _rawContentOf(contentList[optionStartIndices[optionIndex]]);
      if (_isOptionMarkerLine(markerContent)) {
        final dividerText = _dividerLabelFor(markerContent);

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
        final String? displayContent = _displayContentFor(contentList[i]);
        if (displayContent == null) continue;

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
      final String markerContent =
          _rawContentOf(contentList[optionStartIndices[optionIndex]]);
      if (_isOptionMarkerLine(markerContent)) {
        final dividerText = _dividerLabelFor(markerContent);

        buffer.writeln();
        buffer.writeln(dividerText);
        buffer.writeln();
      }

      final int startIdx = optionStartIndices[optionIndex];
      final int endIdx = (optionIndex < optionStartIndices.length - 1)
          ? optionStartIndices[optionIndex + 1]
          : contentList.length;

      for (int i = startIdx; i < endIdx; i++) {
        final String? displayContent = _displayContentFor(contentList[i]);
        if (displayContent == null) continue;

        buffer.writeln(displayContent);
      }
    }

    return buffer.toString();
  }

  /// Bir içerik satırının ekranda görünecek hâli; tamamen atlanması gereken
  /// satırlarda null döner (özel işaretin tek başına olduğu satırlar). Ayıklama
  /// sonrası "*tarifi ektedir" ifadesinin solunda tek boşluk bırakılır.
  static String? _displayContentFor(dynamic item) {
    String content = _rawContentOf(item);

    // Strict skip — original was `SPECIAL_MARKERS.contains(t.trim())`.
    if (isExactStandaloneMarker(content)) return null;
    if (isSpecialMarkerSeparator(content)) {
      content = extractContentAfterMarker(content);
    }
    // A row that was nothing but its marker ("Haftada 4 gün") is already shown
    // as the option divider; rendering the empty remainder would leave a blank
    // line in the meal content.
    if (content.trim().isEmpty) return null;
    return normalizeRecipeMarkerSpacing(content);
  }

  /// Raw text of a content row, which may be stored either as a
  /// `{'content': ...}` map or as a bare value.
  static String _rawContentOf(dynamic item) =>
      (item is Map) ? (item['content'] ?? '').toString() : item.toString();

  /// Whether [content] is a special-line marker row ("Veya", "Haftada 4 gün",
  /// any admin-defined template) that introduces a new option block.
  static bool _isOptionMarkerLine(String content) =>
      isStandaloneMarker(content) || isSpecialMarkerSeparator(content);

  /// Identifies the indices in [contentList] that begin a new option block.
  /// The first item is always treated as an option start; subsequent option
  /// starts are any line recognized as a special marker (standalone or
  /// separator).
  static List<int> _collectOptionStarts(List<dynamic> contentList) {
    final List<int> starts = [];
    for (int i = 0; i < contentList.length; i++) {
      if (i == 0 || _isOptionMarkerLine(_rawContentOf(contentList[i]))) {
        starts.add(i);
      }
    }
    return starts;
  }
}

/// Renders a diet content line that contains recipe references so that ONLY
/// the "*…tarifi ektedir" phrases are tappable links; the surrounding text
/// stays plain. Owns the [TapGestureRecognizer]s applied to the phrase spans
/// so they are disposed correctly (a recognizer created inline in a build
/// would leak).
class _RecipeContentLine extends StatefulWidget {
  final List<RecipeLineSegment> segments;
  final List<VoidCallback?> markerTaps;
  final double fontSize;

  const _RecipeContentLine({
    required this.segments,
    required this.markerTaps,
    required this.fontSize,
  });

  @override
  State<_RecipeContentLine> createState() => _RecipeContentLineState();
}

class _RecipeContentLineState extends State<_RecipeContentLine> {
  List<TapGestureRecognizer?> _recognizers = const <TapGestureRecognizer?>[];

  @override
  void initState() {
    super.initState();
    _syncRecognizers();
  }

  @override
  void didUpdateWidget(covariant _RecipeContentLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRecognizers();
  }

  void _syncRecognizers() {
    final List<TapGestureRecognizer?> previous = _recognizers;
    final List<TapGestureRecognizer?> next = <TapGestureRecognizer?>[
      for (int i = 0; i < widget.markerTaps.length; i++)
        if (widget.markerTaps[i] == null)
          null
        else
          ((i < previous.length ? previous[i] : null) ?? TapGestureRecognizer())
            ..onTap = widget.markerTaps[i],
    ];
    for (int i = 0; i < previous.length; i++) {
      final TapGestureRecognizer? recognizer = previous[i];
      if (recognizer != null &&
          (i >= next.length || !identical(next[i], recognizer))) {
        recognizer.dispose();
      }
    }
    _recognizers = next;
  }

  @override
  void dispose() {
    for (final TapGestureRecognizer? recognizer in _recognizers) {
      recognizer?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle linkStyle = TextStyle(
      color: Colors.blue.shade700,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    int markerIndex = 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: widget.fontSize),
          children: <InlineSpan>[
            for (final RecipeLineSegment segment in widget.segments)
              if (!segment.isMarker)
                TextSpan(text: segment.text)
              else
                _markerSpan(segment.text, markerIndex++, linkStyle),
          ],
        ),
      ),
    );
  }

  TextSpan _markerSpan(String text, int index, TextStyle linkStyle) {
    final TapGestureRecognizer? recognizer =
        index < _recognizers.length ? _recognizers[index] : null;
    if (recognizer == null) return TextSpan(text: text);
    return TextSpan(text: text, style: linkStyle, recognizer: recognizer);
  }
}
