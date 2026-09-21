import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/meal_photo_loader.dart';

/// Orijinal fotoğraf indirilmek zorunda kaldığında (küçük görseli yoktu)
/// baytlarıyla çağrılır; küçük görselin üretilip kaydedilmesi için.
typedef OriginalBytesCallback = Future<void> Function(Uint8List bytes);

/// Liste kartlarındaki öğün fotoğrafı için görsel sağlayıcı.
///
/// `Image.network`'ten farkları:
/// - İndirmeler [MealPhotoLoader] kuyruğundan geçer: aynı anda en fazla
///   birkaç indirme sürer, sayfa 87 isteği birden açıp kasmaz.
/// - Küçük görsel varsa yalnızca o indirilir (orijinalin 50-100'de biri).
/// - Küçük görsel yoksa orijinal indirilir ama **çözülürken** küçültülür
///   ([maxDecodeWidth]); bellekte tam boy bitmap tutulmaz. İndirilen baytlar
///   [onOriginalLoaded] ile dışarı verilir ki küçük görsel bir kez üretilip
///   kaydedilsin ve bir daha tam boy indirme gerekmesin.
///
/// Anahtar (eşitlik) adres + orijinal bayrağıdır: Flutter'ın görsel önbelleği
/// aynı adresi ikinci kez çözmez.
class MealThumbnailProvider extends ImageProvider<MealThumbnailProvider> {
  final String url;

  /// [url] tam boy orijinal mi (küçük görsel bulunamadı).
  final bool isOriginal;

  final OriginalBytesCallback? onOriginalLoaded;

  const MealThumbnailProvider({
    required this.url,
    required this.isOriginal,
    this.onOriginalLoaded,
  });

  /// Orijinalden çözülürken izin verilen en büyük genişlik (piksel). Kart
  /// ~200 mantıksal px; 640, 3x yoğunlukta bile net kalır.
  static const int maxDecodeWidth = 640;

  @override
  Future<MealThumbnailProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<MealThumbnailProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      MealThumbnailProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(decode),
      scale: 1.0,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('url', url),
      ],
    );
  }

  Future<ui.Codec> _loadCodec(ImageDecoderCallback decode) async {
    final Uint8List bytes = await MealPhotoLoader.instance.fetch(url);

    if (isOriginal && onOriginalLoaded != null) {
      // Gösterimi bekletmez; üretim arka planda sürer.
      unawaited(onOriginalLoaded!(bytes).catchError((Object e) {}));
    }

    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(bytes);
    if (!isOriginal) return decode(buffer);

    return decode(
      buffer,
      getTargetSize: (int intrinsicWidth, int intrinsicHeight) =>
          intrinsicWidth <= maxDecodeWidth
              ? ui.TargetImageSize(
                  width: intrinsicWidth, height: intrinsicHeight)
              // Yalnızca genişlik verilir; yükseklik orandan hesaplanır.
              : const ui.TargetImageSize(width: maxDecodeWidth),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MealThumbnailProvider &&
          other.url == url &&
          other.isOriginal == isOriginal;

  @override
  int get hashCode => Object.hash(url, isOriginal);
}

/// Liste kartındaki küçük görsel: yüklenene kadar **hareketsiz** bir yer
/// tutucu gösterir.
///
/// `Image.network` + `loadingBuilder` yüklenene kadar her karede yeniden
/// çizilir ve dönen bir gösterge çalıştırır; onlarca kartta bu, listenin
/// kasmasının başlıca sebebiydi. `frameBuilder` yalnızca ilk kare çözüldüğünde
/// bir kez çalışır.
class MealThumbnailImage extends StatelessWidget {
  final String url;
  final bool isOriginal;
  final OriginalBytesCallback? onOriginalLoaded;
  final BoxFit fit;

  const MealThumbnailImage({
    super.key,
    required this.url,
    required this.isOriginal,
    this.onOriginalLoaded,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _ThumbnailPlaceholder(icon: Icons.image);

    return Image(
      image: MealThumbnailProvider(
        url: url,
        isOriginal: isOriginal,
        onOriginalLoaded: onOriginalLoaded,
      ),
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          frame == null
              ? const _ThumbnailPlaceholder(icon: Icons.image_outlined)
              : child,
      errorBuilder: (context, error, stackTrace) =>
          const _ThumbnailPlaceholder(icon: Icons.broken_image_outlined),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  final IconData icon;

  const _ThumbnailPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(icon, size: 28, color: Colors.grey.shade500),
      ),
    );
  }
}
