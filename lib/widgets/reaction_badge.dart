// lib/widgets/reaction_badge.dart
import 'package:flutter/material.dart';

/// Mesajlara bırakılan tepkilerin (ifadelerin) gösterimi.
///
/// Tepkiler mesaj dokümanında `uid -> emoji` olarak durur; ekranda ise aynı
/// emojiler tek rozette toplanır. Toplama işi [reactionCountsOf] içinde, sohbet
/// baloncuğunun altındaki rozet [ReactionBadge] içindedir. Öğün Fotoğrafları
/// sayfasındaki kart rozeti de aynı toplamayı kullanır.

/// Tepkileri `emoji -> kaç kişi bıraktı` biçiminde toplar.
///
/// Sıra, tepkilerin geldiği sırayı korur: rozet her çizimde aynı görünür.
Map<String, int> reactionCountsOf(Map<String, String> reactions) {
  final Map<String, int> counts = {};
  for (final String emoji in reactions.values) {
    counts[emoji] = (counts[emoji] ?? 0) + 1;
  }
  return counts;
}

/// Small pill shown under a message with the reactions left on it.
///
/// Identical emojis are aggregated, with a count shown when more than one
/// person left the same reaction. The badge overlaps slightly onto the
/// bubble's bottom edge, WhatsApp-style.
class ReactionBadge extends StatelessWidget {
  final Map<String, String> reactions;

  const ReactionBadge({super.key, required this.reactions});

  @override
  Widget build(BuildContext context) {
    final Map<String, int> counts = reactionCountsOf(reactions);
    if (counts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Transform.translate(
      offset: const Offset(0, -6), // overlap onto the bubble's bottom edge
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final MapEntry<String, int> entry in counts.entries) ...[
              Text(entry.key, style: const TextStyle(fontSize: 14)),
              if (entry.value > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 4),
                  child: Text(
                    '${entry.value}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
