/// Represents the configuration of a "special line" inside a meal's content.
///
/// A special line is a content row that should be rendered as a section
/// separator (like the existing "Veya" / "Haftada X" rows) instead of as
/// a regular meal item. Each config has up to three pieces:
///   - [prefix]   : literal text BEFORE the optional number (e.g. "Haftada",
///                  "Günde"); may be empty when the marker starts with the
///                  number itself.
///   - [hasNumber]: whether an integer is part of the marker.
///   - [suffix]   : literal text AFTER the number (e.g. "defa" in
///                  "Günde 3 defa"). Must be empty when [hasNumber] is false.
///
/// Examples:
///   * `Veya`            → prefix=`Veya`,    hasNumber=false, suffix=``
///   * `Haftada X`       → prefix=`Haftada`, hasNumber=true,  suffix=``
///   * `Günde X defa`    → prefix=`Günde`,   hasNumber=true,  suffix=`defa`
///   * `Iki Kelime X`    → prefix=`Iki Kelime`, hasNumber=true, suffix=``
///   * `X defa`          → prefix=``,        hasNumber=true,  suffix=`defa`
///
/// IMPORTANT — for the legacy markers (`Veya`, `Haftada X` with empty suffix)
/// these matchers stay byte-for-byte identical with the original hard-coded
/// regexes in `meal_formatter.dart`:
///   * `VEYA_OPTION_SEPARATOR_REGEX    = ^Veya\s+`
///   * `HAFTADA_OPTION_SEPARATOR_REGEX = ^Haftada\s+\d+\s*`   (note `\s*`)
///   * `isStandaloneMarker(content)`   was the lax check
///         `t == prefix || t.startsWith('$prefix ')`
///   * `SPECIAL_MARKERS.contains(t)`   was the strict check
///         `t == prefix` exactly
class SpecialLineConfig {
  static const String prefixField = 'prefix';
  static const String hasNumberField = 'hasNumber';
  static const String suffixField = 'suffix';

  /// Token used in admin templates as the placeholder for the integer.
  static const String numberPlaceholder = 'X';

  final String prefix;
  final bool hasNumber;
  final String suffix;

  const SpecialLineConfig({
    required this.prefix,
    required this.hasNumber,
    this.suffix = '',
  });

  /// Regex that matches a "marker + inline content" line. Pattern is built
  /// from the prefix/number/suffix triple; trailing `\s*` (instead of `\s+`)
  /// keeps the legacy behavior where a bare "Haftada 2" — i.e. the marker
  /// with no inline content — still counts as a separator.
  RegExp get separatorRegex {
    final buffer = StringBuffer('^');
    if (prefix.isNotEmpty) {
      buffer.write(RegExp.escape(prefix));
      if (hasNumber) buffer.write(r'\s+');
    }
    if (hasNumber) {
      buffer.write(r'\d+');
      if (suffix.isNotEmpty) {
        buffer.write(r'\s+');
        buffer.write(RegExp.escape(suffix));
      }
    }
    // For non-numbered, non-suffixed markers we still require at least one
    // space after the prefix (otherwise "Veyax foo" would match "Veya").
    final tail = hasNumber || prefix.isEmpty ? r'\s*' : r'\s+';
    buffer.write(tail);
    return RegExp(buffer.toString());
  }

  bool isSeparator(String content) => separatorRegex.hasMatch(content);

  /// Lax standalone check. Mirrors the original `isStandaloneMarker`
  /// semantics: trimmed content equals the prefix exactly OR begins with
  /// `"$prefix "`. Empty-prefix configs (e.g. `X defa`) opt out — there is
  /// no meaningful "lax prefix" check for them, so they only match via the
  /// separator regex.
  bool isStandalone(String content) {
    if (prefix.isEmpty) return false;
    final t = content.trim();
    return t == prefix || t.startsWith('$prefix ');
  }

  /// Strict marker check. Mirrors the original `SPECIAL_MARKERS.contains`:
  /// trimmed content equals the prefix exactly. The renderer uses this to
  /// decide whether to skip a row entirely instead of stripping a marker.
  bool isExactMarker(String content) =>
      prefix.isNotEmpty && content.trim() == prefix;

  /// Returns the marker substring matched on a separator line, e.g.
  /// "Haftada 2" from "Haftada 2 Yulaflı kahvaltı" or
  /// "Günde 3 defa" from "Günde 3 defa yumurta". Falls back to [prefix]
  /// when the line only matched via the lax standalone check.
  String extractMarkerLabel(String content) {
    final sepMatch = separatorRegex.firstMatch(content);
    if (sepMatch != null) return sepMatch.group(0)!.trim();
    return prefix;
  }

  /// Returns the part of [content] that follows the marker for separator
  /// lines. Mirrors `extractContentAfterMarker` exactly: no trim, single
  /// `replaceFirst` so multi-space prefixes leave their original whitespace
  /// unchanged.
  String stripMarker(String content) {
    if (!isSeparator(content)) return content;
    return content.replaceFirst(separatorRegex, '');
  }

  Map<String, dynamic> toMap() => {
        prefixField: prefix,
        hasNumberField: hasNumber,
        if (suffix.isNotEmpty) suffixField: suffix,
      };

  factory SpecialLineConfig.fromMap(Map<String, dynamic> map) {
    return SpecialLineConfig(
      prefix: (map[prefixField] ?? '').toString(),
      hasNumber: map[hasNumberField] == true,
      suffix: (map[suffixField] ?? '').toString(),
    );
  }

  /// Renders this config as the admin-facing template, e.g.
  ///   * `Veya`            (no number)
  ///   * `Haftada X`       (number at the end)
  ///   * `Günde X defa`    (number in the middle)
  ///   * `X defa`          (number at the start)
  String toTemplate() => _renderWith(numberPlaceholder);

  /// Same as [toTemplate] but with `X` replaced by [n]. Useful for showing
  /// concrete examples in admin UI (e.g. "Günde 3 defa").
  String formatWithNumber(int n) => _renderWith(n.toString());

  String _renderWith(String numberToken) {
    if (!hasNumber) return prefix;
    final parts = <String>[
      if (prefix.isNotEmpty) prefix,
      numberToken,
      if (suffix.isNotEmpty) suffix,
    ];
    return parts.join(' ');
  }

  /// Parses an admin-entered template back into a [SpecialLineConfig].
  ///
  /// Rules:
  ///   * The placeholder is the literal uppercase token `X`.
  ///   * `X` may appear ZERO or ONE times.
  ///   * When present, `X` must be a standalone token surrounded by spaces
  ///     (or by a word boundary at the start/end of the template).
  ///   * Lowercase `x`, multiple `X`s, or an `X` glued to other text (e.g.
  ///     `Xfoo`, `fooX`) are rejected.
  ///
  /// Returns `null` for an invalid template.
  static SpecialLineConfig? tryParseTemplate(String template) {
    final trimmed = template.trim();
    if (trimmed.isEmpty) return null;

    final tokens = trimmed.split(RegExp(r'\s+'));
    final xPositions = <int>[];
    for (int i = 0; i < tokens.length; i++) {
      if (tokens[i] == numberPlaceholder) xPositions.add(i);
    }
    // No more than one X. (Zero is fine — that's a fixed-text marker.)
    if (xPositions.length > 1) return null;

    if (xPositions.isEmpty) {
      // Reject things like "Haftada X" written with lowercase x — at this
      // point we only have non-X tokens, so the template is treated as a
      // fixed-text marker.
      return SpecialLineConfig(prefix: trimmed, hasNumber: false);
    }

    final xIndex = xPositions.first;
    final beforeTokens = tokens.sublist(0, xIndex);
    final afterTokens = tokens.sublist(xIndex + 1);

    final prefix = beforeTokens.join(' ').trim();
    final suffix = afterTokens.join(' ').trim();
    // At least one of prefix/suffix must be non-empty so the regex anchors
    // somewhere; an isolated "X" template doesn't define a marker.
    if (prefix.isEmpty && suffix.isEmpty) return null;

    return SpecialLineConfig(
      prefix: prefix,
      hasNumber: true,
      suffix: suffix,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecialLineConfig &&
          other.prefix == prefix &&
          other.hasNumber == hasNumber &&
          other.suffix == suffix;

  @override
  int get hashCode => Object.hash(prefix, hasNumber, suffix);
}

/// Process-wide registry of special line configurations consulted by the meal
/// formatter and by the docx import parser.
///
/// Built-in entries cover the original "Veya" and "Haftada X" markers so the
/// app keeps working even before the admin-configured list has been loaded.
/// Admin-defined entries are layered on top via [setCustomLines].
class SpecialLinesRegistry {
  static const SpecialLineConfig veya =
      SpecialLineConfig(prefix: 'Veya', hasNumber: false);
  static const SpecialLineConfig haftada =
      SpecialLineConfig(prefix: 'Haftada', hasNumber: true);

  static const List<SpecialLineConfig> _builtIn = [veya, haftada];

  static List<SpecialLineConfig> _custom = const [];

  /// Replaces the admin-configured list. Built-in markers are always retained.
  ///
  /// Two safety filters are applied:
  ///   * Drop fully-empty configs (both prefix and suffix blank — these
  ///     would build a regex that matches nothing meaningful).
  ///   * Drop configs whose non-empty prefix collides with a built-in
  ///     prefix, so an admin entry can never silently override `Veya` or
  ///     `Haftada`.
  static void setCustomLines(List<SpecialLineConfig> lines) {
    final builtInPrefixes =
        _builtIn.map((c) => c.prefix.toLowerCase()).toSet();
    _custom = List.unmodifiable(
      lines.where((c) {
        final hasAnyText = c.prefix.trim().isNotEmpty || c.suffix.trim().isNotEmpty;
        if (!hasAnyText) return false;
        if (c.prefix.trim().isEmpty) return true; // empty prefix is allowed
        return !builtInPrefixes.contains(c.prefix.toLowerCase());
      }),
    );
  }

  static List<SpecialLineConfig> get all => [..._builtIn, ..._custom];

  static List<SpecialLineConfig> get custom => List.unmodifiable(_custom);

  /// Finds the first config whose marker matches [content] either as a
  /// standalone marker line or as a separator line; returns null otherwise.
  static SpecialLineConfig? matching(String content) {
    final t = content.trim();
    for (final cfg in all) {
      if (cfg.isStandalone(t) || cfg.isSeparator(t)) return cfg;
    }
    return null;
  }

  /// Inspects [line] and returns a [SpecialLineMatch] describing how it
  /// should be split between a leading marker entry and (optional) trailing
  /// content. Returns null when [line] is a regular meal-content row.
  ///
  /// Detection order — separator first, lax standalone second — matches what
  /// the original parser/renderer pipeline did: a "marker + content" line is
  /// always cleanly split, while bare-prefix lines (e.g. "Veya") become
  /// standalone markers with no trailing content.
  static SpecialLineMatch? detect(String line) {
    final t = line.trim();
    for (final cfg in all) {
      if (cfg.isSeparator(t)) {
        return SpecialLineMatch(
          config: cfg,
          markerLabel: cfg.extractMarkerLabel(t),
          contentAfter: cfg.stripMarker(t).trim(),
        );
      }
      if (cfg.isStandalone(t)) {
        // Lax standalone covers two shapes:
        //   - exact "Veya" / "Haftada"      → no trailing content
        //   - "Haftada foo" (prefix + space + non-numeric tail for a numbered
        //      marker, which the separator regex rejected) → keep tail as
        //      regular content so it isn't lost.
        final tail = t == cfg.prefix
            ? ''
            : t.substring(cfg.prefix.length).trim();
        return SpecialLineMatch(
          config: cfg,
          markerLabel: cfg.prefix,
          contentAfter: tail,
        );
      }
    }
    return null;
  }
}

/// Result of detecting a special line inside a raw text line.
class SpecialLineMatch {
  final SpecialLineConfig config;

  /// Exact marker text to persist as the standalone marker entry, e.g.
  /// "Veya", "Haftada 2".
  final String markerLabel;

  /// Trailing content after the marker, or empty when [line] was a
  /// standalone marker.
  final String contentAfter;

  const SpecialLineMatch({
    required this.config,
    required this.markerLabel,
    required this.contentAfter,
  });
}
