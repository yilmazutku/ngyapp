// lib/widgets/chat/pending_upload_bubble.dart
import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../../models/meal_model.dart';
import '../../models/pending_upload.dart';
import '../meal_image_card.dart';

/// Sohbette yüklenmeyi bekleyen fotoğrafın baloncuğu (bkz. [PendingUpload]).
///
/// Fotoğraf cihazdaki dosyadan hemen, gerçek oranında (mesaj baloncuğuyla aynı
/// ölçüde, bkz. [photoSizeOf]) gösterilir; üstünde ilerleme ve iptal,
/// sıradaysa "Sırada", yüklenemediyse sebebi ile "Tekrar dene" / "Kaldır"
/// görünür. Yükleme bitince baloncuk kalkar, yerine gerçek mesaj gelir.
/// Ekran kilitlenmez: bu sırada yazışmaya devam edilebilir.
class PendingUploadBubble extends StatelessWidget {
  final PendingUpload upload;

  /// Fotoğrafın baloncuktaki ölçüsü, en/boy oranından; gönderilen mesajın
  /// baloncuğu da aynı ölçüyü kullanır, yükleme bitince boyut değişmez.
  final Size Function(double aspectRatio) photoSizeOf;
  final Color bubbleColor;
  final VoidCallback onDiscard;
  final VoidCallback onRetry;

  const PendingUploadBubble({
    super.key,
    required this.upload,
    required this.photoSizeOf,
    required this.bubbleColor,
    required this.onDiscard,
    required this.onRetry,
  });

  static const String _waitingText = 'Sırada';
  static const String _uploadingText = 'Gönderiliyor…';
  static const String _cancelLabel = 'İptal';
  static const String _cancelTooltip = 'Gönderimi iptal et';
  static const String _retryLabel = 'Tekrar dene';
  static const String _discardLabel = 'Kaldır';
  static const String _autoRetryText =
      'Bağlantı gelince kendiliğinden yeniden denenecek.';

  /// Oranı henüz okunmamış fotoğrafın en/boy oranı.
  static const double _defaultAspectRatio = 4 / 3;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PendingUploadStatus>(
      valueListenable: upload.status,
      builder: (context, status, _) {
        if (status == PendingUploadStatus.saving) {
          return const SizedBox.shrink();
        }

        final Meals meal = upload.meal;
        final Color mealColor = mealTypeColor(meal);
        return ValueListenableBuilder<double?>(
          valueListenable: upload.previewAspectRatio,
          builder: (context, aspectRatio, _) {
            final Size photoSize =
                photoSizeOf(aspectRatio ?? _defaultAspectRatio);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: photoSize.width + 12,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                        child: Row(
                          children: [
                            Icon(mealTypeIcon(meal),
                                size: 16, color: mealColor),
                            const SizedBox(width: 6),
                            Text(
                              meal.displayLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: mealColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildPreview(context, status, photoSize),
                      const SizedBox(height: 4),
                      _buildFooter(context, status),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPreview(
    BuildContext context,
    PendingUploadStatus status,
    Size size,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(upload.image.path),
              fit: BoxFit.cover,
              cacheWidth:
                  (size.width * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (context, error, stackTrace) =>
                  ColoredBox(color: Colors.grey.shade300),
            ),
            const ColoredBox(color: Colors.black38),
            Center(child: _buildStatusIndicator(status)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(PendingUploadStatus status) {
    switch (status) {
      case PendingUploadStatus.waiting:
        return const Icon(Icons.schedule, color: Colors.white, size: 36);
      case PendingUploadStatus.failed:
        return const Icon(Icons.error_outline, color: Colors.white, size: 40);
      case PendingUploadStatus.uploading:
      case PendingUploadStatus.saving:
        return ValueListenableBuilder<double?>(
          valueListenable: upload.progress,
          builder: (context, progress, _) => Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  value: progress,
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
              IconButton(
                tooltip: _cancelTooltip,
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onDiscard,
              ),
            ],
          ),
        );
    }
  }

  Widget _buildFooter(BuildContext context, PendingUploadStatus status) {
    final ThemeData theme = Theme.of(context);

    if (status == PendingUploadStatus.failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              upload.willAutoRetry
                  ? '${upload.errorText ?? PendingUpload.defaultErrorText} '
                      '$_autoRetryText'
                  : upload.errorText ?? PendingUpload.defaultErrorText,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                  onPressed: onDiscard, child: const Text(_discardLabel)),
              if (upload.canRetry)
                TextButton(onPressed: onRetry, child: const Text(_retryLabel)),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              status == PendingUploadStatus.waiting
                  ? _waitingText
                  : _uploadingText,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        ),
        TextButton(onPressed: onDiscard, child: const Text(_cancelLabel)),
      ],
    );
  }
}
