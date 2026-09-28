// lib/widgets/chat/message_reply_quote.dart
import 'package:flutter/material.dart';

import '../meal_thumbnail_image.dart';

/// Yanıtlanan mesajın alıntısı: kimin yazdığı, metni ya da fotoğrafı. Yanıt
/// baloncuğunun üstünde ve mesaj kutusunun üstündeki "yanıtlanıyor"
/// çubuğunda ([MessageReplyComposerBar]) aynı görünür.
class MessageReplyQuote extends StatelessWidget {
  final String senderLabel;
  final String text;
  final String? imageUrl;

  /// Verilirse alıntıya dokununca çağrılır (ör. yanıtlanan mesaja gitmek).
  final VoidCallback? onTap;

  const MessageReplyQuote({
    super.key,
    required this.senderLabel,
    required this.text,
    this.imageUrl,
    this.onTap,
  });

  static const String _photoLabel = 'Fotoğraf';
  static const double _imageSize = 40;
  static const double _accentWidth = 4;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = theme.colorScheme.primary;
    final String? image = imageUrl;
    final bool photoOnly = text.isEmpty && image != null;

    return Material(
      color: Colors.black.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: _accentWidth, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        senderLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (photoOnly)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.photo_outlined,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(_photoLabel, style: theme.textTheme.bodySmall),
                          ],
                        )
                      else
                        Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
              if (image != null)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: _imageSize,
                      height: _imageSize,
                      // Alıntıdaki adres küçük görsel ya da (eski mesajda)
                      // orijinal olabilir; orijinalse küçültülerek çözülür.
                      child: MealThumbnailImage(url: image, isOriginal: true),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mesaj kutusunun üstündeki "yanıtlanıyor" çubuğu: yanıtlanan mesajın
/// alıntısı ve yanıtı iptal eden düğme.
class MessageReplyComposerBar extends StatelessWidget {
  final String senderLabel;
  final String text;
  final String? imageUrl;
  final VoidCallback onCancel;

  const MessageReplyComposerBar({
    super.key,
    required this.senderLabel,
    required this.text,
    required this.onCancel,
    this.imageUrl,
  });

  static const String _cancelTooltip = 'Yanıtı iptal et';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.reply, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: MessageReplyQuote(
              senderLabel: senderLabel,
              text: text,
              imageUrl: imageUrl,
            ),
          ),
          IconButton(
            tooltip: _cancelTooltip,
            icon: const Icon(Icons.close),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
