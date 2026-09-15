// lib/widgets/reaction_picker.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Mesajlara bırakılan tepkinin (ifadenin) seçicisi.
///
/// Sohbet ekranındaki baloncuğa uzun basınca ve Öğün Fotoğrafları sayfasında
/// bir fotoğrafa sağ tıklayıp "İfade Bırak" seçilince aynı seçici açılır;
/// böylece iki yerde de aynı ifadeler, aynı düzen ve aynı davranış kullanılır.

/// The reactions shown directly inside the long-press pill (WhatsApp-style).
///
/// Deliberately short: the pill has to stay readable on a narrow phone. Every
/// other reaction lives behind the pill's "…" button, which opens
/// [showAllReactionsSheet]. Same set for the client and the office.
const List<String> kChatQuickReactionEmojis = [
  '👍', '❤️', '😂', '😮', '😢', '🙏',
];

/// Every reaction the picker can offer. The quick ones come first so the "…"
/// sheet opens in the same order the pill shows them. Add entries here to
/// offer more; only the first [kChatQuickReactionEmojis] appear in the pill.
const List<String> kChatAllReactionEmojis = [
  ...kChatQuickReactionEmojis,
  '👎', '🔥', '🎉', '👏', '🙌', '💪',
  '💯', '⭐', '✅', '🤔', '😅', '😊',
  '😍', '🥰', '🤗', '😋', '😴', '🥳',
  '🥗', '🍎', '💧', '🏃',
];

/// Returned by the quick pill when the viewer taps "…" instead of an emoji.
///
/// A dedicated object rather than a sentinel string, so it can never collide
/// with a real reaction.
final Object _moreReactionsMarker = Object();

/// Show a small WhatsApp-style reaction picker anchored near [globalPosition].
///
/// Returns the tapped emoji, or null if dismissed without a choice. Tapping the
/// pill's "…" button dismisses it and opens [showAllReactionsSheet] instead, so
/// the full list is one tap away without crowding the pill.
/// [currentEmoji] (if any) is highlighted so the reactor can see — and tap
/// again to remove — their existing reaction.
Future<String?> showReactionPicker(
  BuildContext context, {
  required Offset globalPosition,
  String? currentEmoji,
}) async {
  final media = MediaQuery.of(context);
  final size = media.size;

  // Pill geometry: one slot per quick reaction, plus a slot for "…" when there
  // are more reactions than the pill shows.
  const slotWidth = kReactionPillSlotWidth;
  const pillPadding = 16.0;
  const pillHeight = 52.0;
  const margin = 12.0;

  final hasMore =
      kChatAllReactionEmojis.length > kChatQuickReactionEmojis.length;
  final slots = kChatQuickReactionEmojis.length + (hasMore ? 1 : 0);

  // Never wider than the screen: a narrow phone scrolls the pill's row instead
  // of pushing it off-screen (and instead of an invalid clamp below).
  final maxPillWidth = math.max(slotWidth, size.width - margin * 2);
  final pillWidth = math.min(slots * slotWidth + pillPadding, maxPillWidth);

  final double maxLeft = math.max(margin, size.width - pillWidth - margin);
  final double left =
      (globalPosition.dx - pillWidth / 2).clamp(margin, maxLeft).toDouble();

  // Prefer showing the pill just above the finger; drop below if no room.
  double top = globalPosition.dy - pillHeight - 16;
  if (top < media.padding.top + margin) {
    top = globalPosition.dy + 16;
  }
  final double minTop = media.padding.top + margin;
  final double maxTop =
      math.max(minTop, size.height - pillHeight - margin);
  top = top.clamp(minTop, maxTop).toDouble();

  final selected = await showGeneralDialog<Object>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.15),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, __) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, _, __) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: ScaleTransition(
              scale: curved,
              alignment: Alignment.bottomCenter,
              child: FadeTransition(
                opacity: animation,
                child: _ReactionPickerBar(
                  emojis: kChatQuickReactionEmojis,
                  currentEmoji: currentEmoji,
                  maxWidth: pillWidth,
                  onSelected: (emoji) => Navigator.of(ctx).pop(emoji),
                  onShowAll: hasMore
                      ? () => Navigator.of(ctx).pop(_moreReactionsMarker)
                      : null,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  if (!identical(selected, _moreReactionsMarker)) {
    return selected as String?;
  }

  // The viewer asked for the full list; the pill has already been dismissed.
  if (!context.mounted) return null;
  return showAllReactionsSheet(context, currentEmoji: currentEmoji);
}

/// Bottom sheet listing every reaction in [kChatAllReactionEmojis].
///
/// Opened from the quick pill's "…" button. Returns the tapped emoji, or null
/// when dismissed without a choice.
Future<String?> showAllReactionsSheet(
  BuildContext context, {
  String? currentEmoji,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tepki Seç',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // Flexible + scroll view: the grid grows with the emoji list but
              // never pushes the sheet past the available height.
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final emoji in kChatAllReactionEmojis)
                        _ReactionPickerButton(
                          emoji: emoji,
                          selected: emoji == currentEmoji,
                          onTap: () => Navigator.of(ctx).pop(emoji),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The horizontal pill of emoji buttons shown by [showReactionPicker].
class _ReactionPickerBar extends StatelessWidget {
  final List<String> emojis;
  final String? currentEmoji;
  final ValueChanged<String> onSelected;

  /// Opens the full reaction list. Null hides the "…" button.
  final VoidCallback? onShowAll;

  /// Hard cap so the pill never runs off a narrow screen; its row scrolls
  /// horizontally inside the pill when the emojis do not fit.
  final double maxWidth;

  const _ReactionPickerBar({
    required this.emojis,
    required this.currentEmoji,
    required this.onSelected,
    required this.maxWidth,
    this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = isDark ? const Color(0xFF2A2A2E) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final emoji in emojis)
                _ReactionPickerButton(
                  emoji: emoji,
                  selected: emoji == currentEmoji,
                  onTap: () => onSelected(emoji),
                  glyphSize: kReactionPillGlyphSize,
                  glyphPadding: kReactionPillGlyphPadding,
                ),
              if (onShowAll != null) _ReactionMoreButton(onTap: onShowAll!),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glyph size used inside the quick pill. Smaller than the sheet's so six
/// reactions plus the "…" button still fit across a narrow phone without the
/// pill having to scroll (see [kReactionPillSlotWidth]).
const double kReactionPillGlyphSize = 24.0;

/// Padding around a glyph inside the quick pill.
const double kReactionPillGlyphPadding = 6.0;

/// Width one pill slot occupies: glyph + its padding + the button's margin.
/// Used to size and position the pill before it is laid out.
const double kReactionPillSlotWidth =
    kReactionPillGlyphSize + kReactionPillGlyphPadding * 2 + 4 + 6;

/// A single tappable emoji inside the reaction picker. Highlights a circular
/// background when it is the viewer's current reaction.
///
/// [glyphSize] and [glyphPadding] let the compact pill and the roomier "…"
/// sheet share one button without either dictating the other's metrics.
class _ReactionPickerButton extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  final double glyphSize;
  final double glyphPadding;

  const _ReactionPickerButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
    this.glyphSize = 28.0,
    this.glyphPadding = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    final highlight =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.16);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: EdgeInsets.all(glyphPadding),
        decoration: BoxDecoration(
          color: selected ? highlight : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(emoji, style: TextStyle(fontSize: glyphSize)),
      ),
    );
  }
}

/// The "…" button at the end of the quick pill. Trades the pill for the full
/// reaction list so rarely used emojis stay out of the way.
class _ReactionMoreButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ReactionMoreButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: 'Tüm tepkiler',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(kReactionPillGlyphPadding),
          decoration: BoxDecoration(
            color: onSurface.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.more_horiz,
            size: kReactionPillGlyphSize,
            color: onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
