/// A single token of a special-line template: either fixed literal text or the
/// integer placeholder ("X").
class SpecialLineSegment {
  /// Literal text for a fixed token; `null` marks a number placeholder.
  final String? literal;

  const SpecialLineSegment.literal(String text) : literal = text;
  const SpecialLineSegment.number() : literal = null;

  bool get isNumber => literal == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecialLineSegment && other.literal == literal;

  @override
  int get hashCode => literal?.hashCode ?? 0;
}

/// Represents the configuration of a "special line" inside a meal's content.
///
/// A special line is a content row that should be rendered as a section
/// separator (like the existing "Veya" / "Haftada X" rows) instead of as a
/// regular meal item.
///
/// A config is modelled as an ordered list of [segments], where each segment
/// is either fixed literal text or an integer placeholder. This supports an
/// arbitrary number of numbers, e.g.:
///   * `Veya`                  → [lit "Veya"]
///   * `Haftada X`             → [lit "Haftada", num]
///   * `Günde X defa`          → [lit "Günde", num, lit "defa"]
///   * `Haftada X Gün`         → [lit "Haftada", num, lit "Gün"]
///   * `Haftada X Gün X Defa`  → [lit "Haftada", num, lit "Gün", num, lit "Defa"]
///   * `X defa`                → [num, lit "defa"]
///
/// Matching is intentionally tolerant:
///   * Case-insensitive — Word documents capitalise inconsistently (e.g. the
///     marker template "Haftada X Gün" must still match "Haftada 1 gün").
///   * Glue-tolerant — `docx_to_text` drops Word <w:tab/> separators, so the
///     marker frequently arrives glued directly to its content
///     ("Veya2 yumurta", "Haftada 1 gün1 porsiyon"). Inter-segment and trailing
///     separators therefore use `\s*` (zero-or-more whitespace).
///
/// Because two markers can now share a leading word ("Haftada X" vs
/// "Haftada X Gün"), the registry resolves ambiguity by preferring the
/// LONGEST match (see [SpecialLinesRegistry.detect]).
class SpecialLineConfig {
  /// Token used in admin templates as the placeholder for an integer.
  static const String numberPlaceholder = 'X';

  /// Canonical persisted field — the template string, e.g. "Haftada X Gün".
  static const String templateField = 'template';

  // Legacy persisted fields, still read for backward compatibility.
  static const String prefixField = 'prefix';
  static const String hasNumberField = 'hasNumber';
  static const String suffixField = 'suffix';

  final List<SpecialLineSegment> segments;

  const SpecialLineConfig._(this.segments);

  /// Builds a config from a template string (e.g. "Haftada X Gün").
  /// Throws [ArgumentError] for an invalid template; use [tryParseTemplate]
  /// when the input is untrusted.
  factory SpecialLineConfig.fromTemplate(String template) {
    final parsed = tryParseTemplate(template);
    if (parsed == null) {
      throw ArgumentError('Invalid special line template: "$template"');
    }
    return parsed;
  }

  bool get hasNumber => segments.any((s) => s.isNumber);

  /// Leading literal text before the first number (or the whole literal text
  /// when there is no number). Empty when the template starts with a number.
  String get prefix {
    final parts = <String>[];
    for (final s in segments) {
      if (s.isNumber) break;
      parts.add(s.literal!);
    }
    return parts.join(' ');
  }

  /// Case-insensitive identity used for de-duplication. Two templates that
  /// render to the same text (ignoring case) are considered the same marker.
  String get identityKey => toTemplate().toLowerCase();

  /// Regex matching a "marker + (optional) inline content" line.
  ///
  /// Case-insensitive and glue-tolerant (see class docs). Trailing `\s*` keeps
  /// a bare marker ("Haftada 2", "Veya") matching as a separator with no inline
  /// content.
  RegExp get separatorRegex {
    final buffer = StringBuffer('^');
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) buffer.write(r'\s*');
      final seg = segments[i];
      buffer.write(seg.isNumber ? r'\d+' : RegExp.escape(seg.literal!));
    }
    buffer.write(r'\s*');
    return RegExp(buffer.toString(), caseSensitive: false);
  }

  bool isSeparator(String content) => separatorRegex.hasMatch(content);

  /// Length of the marker portion this config matches at the start of
  /// [content], or -1 when it does not match. Used to pick the most specific
  /// (longest) marker among overlapping configs.
  int matchLength(String content) {
    final m = separatorRegex.firstMatch(content);
    return m == null ? -1 : m.group(0)!.length;
  }

  /// Lax standalone check: trimmed content equals the leading literal exactly
  /// OR begins with `"$prefix "`. Number-leading configs opt out.
  bool isStandalone(String content) {
    final p = prefix;
    if (p.isEmpty) return false;
    final t = content.trim();
    final lower = t.toLowerCase();
    final lowerP = p.toLowerCase();
    return lower == lowerP || lower.startsWith('$lowerP ');
  }

  /// Strict marker check: trimmed content equals the leading literal exactly.
  bool isExactMarker(String content) {
    final p = prefix;
    return p.isNotEmpty && content.trim().toLowerCase() == p.toLowerCase();
  }

  /// Returns the concrete marker substring matched on a separator line, e.g.
  /// "Haftada 2" / "Haftada 1 gün". Falls back to [prefix] when only the lax
  /// standalone check matched.
  String extractMarkerLabel(String content) {
    final sepMatch = separatorRegex.firstMatch(content);
    if (sepMatch != null) return sepMatch.group(0)!.trim();
    return prefix;
  }

  /// Returns the part of [content] following the marker on a separator line.
  String stripMarker(String content) {
    if (!isSeparator(content)) return content;
    return content.replaceFirst(separatorRegex, '');
  }

  Map<String, dynamic> toMap() => {templateField: toTemplate()};

  factory SpecialLineConfig.fromMap(Map<String, dynamic> map) {
    // Preferred (new) format: a single template string.
    final tmpl = map[templateField];
    if (tmpl is String && tmpl.trim().isNotEmpty) {
      final parsed = tryParseTemplate(tmpl);
      if (parsed != null) return parsed;
    }

    // Legacy format: { prefix, hasNumber, suffix }. Reconstruct a template.
    final legacyPrefix = (map[prefixField] ?? '').toString().trim();
    final legacyHasNumber = map[hasNumberField] == true;
    final legacySuffix = (map[suffixField] ?? '').toString().trim();
    final parts = <String>[
      if (legacyPrefix.isNotEmpty) legacyPrefix,
      if (legacyHasNumber) numberPlaceholder,
      if (legacySuffix.isNotEmpty) legacySuffix,
    ];
    final parsed = tryParseTemplate(parts.join(' '));
    // Empty/invalid legacy entries become an empty config that the registry
    // filters out in setCustomLines.
    return parsed ?? const SpecialLineConfig._([]);
  }

  /// Renders this config as the admin-facing template, e.g. "Haftada X Gün".
  String toTemplate() => _renderWith(numberPlaceholder);

  /// Same as [toTemplate] but with every `X` replaced by [n]. Useful for
  /// concrete examples in admin UI (e.g. "Haftada 2 Gün").
  String formatWithNumber(int n) => _renderWith(n.toString());

  String _renderWith(String numberToken) => segments
      .map((s) => s.isNumber ? numberToken : s.literal!)
      .join(' ');

  /// Parses an admin-entered template into a [SpecialLineConfig].
  ///
  /// Rules:
  ///   * Tokens are whitespace-separated.
  ///   * Each token exactly equal to the uppercase placeholder `X` becomes a
  ///     number segment; everything else is literal text.
  ///   * Multiple `X`s are allowed (e.g. "Haftada X Gün X Defa") but two
  ///     numbers may not be adjacent (there must be literal text between them).
  ///   * There must be at least one literal token so the regex has an anchor;
  ///     a template made only of numbers (e.g. "X", "X X") is rejected.
  ///
  /// Returns `null` for an invalid template.
  static SpecialLineConfig? tryParseTemplate(String template) {
    final trimmed = template.trim();
    if (trimmed.isEmpty) return null;

    final tokens = trimmed.split(RegExp(r'\s+'));
    final segments = <SpecialLineSegment>[];
    final literalBuffer = <String>[];

    void flushLiteral() {
      if (literalBuffer.isNotEmpty) {
        segments.add(SpecialLineSegment.literal(literalBuffer.join(' ')));
        literalBuffer.clear();
      }
    }

    for (final token in tokens) {
      if (token == numberPlaceholder) {
        flushLiteral();
        // No two adjacent number placeholders.
        if (segments.isNotEmpty && segments.last.isNumber) return null;
        segments.add(const SpecialLineSegment.number());
      } else {
        literalBuffer.add(token);
      }
    }
    flushLiteral();

    // Need at least one literal segment to anchor the pattern.
    if (!segments.any((s) => !s.isNumber)) return null;

    return SpecialLineConfig._(segments);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SpecialLineConfig) return false;
    if (other.segments.length != segments.length) return false;
    for (int i = 0; i < segments.length; i++) {
      if (segments[i] != other.segments[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll(segments.map((s) => s.isNumber ? '#X#' : s.literal));
}

/// Process-wide registry of special line configurations consulted by the meal
/// formatter and by the docx import parser.
///
/// Built-in entries cover the original "Veya" and "Haftada X" markers so the
/// app keeps working even before the admin-configured list has been loaded.
/// Admin-defined entries are layered on top via [setCustomLines].
class SpecialLinesRegistry {
  static final SpecialLineConfig veya =
      SpecialLineConfig.fromTemplate('Veya');
  static final SpecialLineConfig haftada =
      SpecialLineConfig.fromTemplate('Haftada X');

  static final List<SpecialLineConfig> _builtIn = [veya, haftada];

  static List<SpecialLineConfig> _custom = const [];

  /// Replaces the admin-configured list. Built-in markers are always retained.
  ///
  /// Filters applied:
  ///   * Drop empty configs (no segments — e.g. an invalid legacy entry).
  ///   * Drop configs whose template exactly matches a built-in template, so
  ///     an admin entry can never duplicate `Veya` / `Haftada X`.
  ///   * Drop duplicates within the custom list itself.
  ///
  /// Sharing a leading word with another marker is now allowed (e.g.
  /// "Haftada X" + "Haftada X Gün"); [detect] resolves overlaps by length.
  static void setCustomLines(List<SpecialLineConfig> lines) {
    final builtInKeys = _builtIn.map((c) => c.identityKey).toSet();
    final seen = <String>{};
    _custom = List.unmodifiable(
      lines.where((c) {
        if (c.segments.isEmpty) return false;
        final key = c.identityKey;
        if (builtInKeys.contains(key)) return false;
        if (seen.contains(key)) return false;
        seen.add(key);
        return true;
      }),
    );
  }

  static List<SpecialLineConfig> get all => [..._builtIn, ..._custom];

  static List<SpecialLineConfig> get custom => List.unmodifiable(_custom);

  /// Finds the config that best matches [content], preferring the LONGEST
  /// separator match (so "Haftada X Gün" wins over "Haftada X"). Falls back to
  /// a lax standalone match. Returns null when nothing matches.
  static SpecialLineConfig? matching(String content) {
    final t = content.trim();
    final sep = _longestSeparatorMatch(t);
    if (sep != null) return sep;
    for (final cfg in all) {
      if (cfg.isStandalone(t)) return cfg;
    }
    return null;
  }

  /// Inspects [line] and returns a [SpecialLineMatch] describing how it should
  /// be split between a leading marker entry and (optional) trailing content.
  /// Returns null when [line] is a regular meal-content row.
  ///
  /// The most specific (longest) separator wins, so a line like
  /// "Haftada 1 gün1 porsiyon" is matched by "Haftada X Gün" (marker
  /// "Haftada 1 gün", content "1 porsiyon") rather than by "Haftada X".
  static SpecialLineMatch? detect(String line) {
    final t = line.trim();

    final sepCfg = _longestSeparatorMatch(t);
    if (sepCfg != null) {
      return SpecialLineMatch(
        config: sepCfg,
        markerLabel: sepCfg.extractMarkerLabel(t),
        contentAfter: sepCfg.stripMarker(t).trim(),
      );
    }

    // Fallback: lax standalone (prefix + non-numeric tail), longest prefix.
    SpecialLineConfig? bestStandalone;
    for (final cfg in all) {
      if (!cfg.isStandalone(t)) continue;
      if (bestStandalone == null ||
          cfg.prefix.length > bestStandalone.prefix.length) {
        bestStandalone = cfg;
      }
    }
    if (bestStandalone != null) {
      final p = bestStandalone.prefix;
      final tail = t.length == p.length ? '' : t.substring(p.length).trim();
      return SpecialLineMatch(
        config: bestStandalone,
        markerLabel: p,
        contentAfter: tail,
      );
    }
    return null;
  }

  /// Returns the config whose separator regex matches [content] with the
  /// longest matched marker, or null when none match.
  static SpecialLineConfig? _longestSeparatorMatch(String content) {
    SpecialLineConfig? best;
    int bestLen = -1;
    for (final cfg in all) {
      final len = cfg.matchLength(content);
      if (len > bestLen) {
        bestLen = len;
        best = cfg;
      }
    }
    return best;
  }
}

/// Result of detecting a special line inside a raw text line.
class SpecialLineMatch {
  final SpecialLineConfig config;

  /// Exact marker text to persist as the standalone marker entry, e.g.
  /// "Veya", "Haftada 2", "Haftada 1 gün".
  final String markerLabel;

  /// Trailing content after the marker, or empty when [line] was a standalone
  /// marker.
  final String contentAfter;

  const SpecialLineMatch({
    required this.config,
    required this.markerLabel,
    required this.contentAfter,
  });
}
