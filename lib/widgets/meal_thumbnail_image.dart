import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
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

  final int? decodeShortSide;

  final bool immediate;

  const MealThumbnailProvider({
    required this.url,
    required this.isOriginal,
    this.onOriginalLoaded,
    this.decodeShortSide,
  }) : immediate = false;

  const MealThumbnailProvider.fullSize(this.url)
      : isOriginal = false,
        onOriginalLoaded = null,
        decodeShortSide = null,
        immediate = true;

  /// Orijinalden çözülürken izin verilen en büyük genişlik (piksel). Kart
  /// ~200 mantıksal px; 640, 3x yoğunlukta bile net kalır.
  static const int maxDecodeWidth = 640;

  /// Cihazda üretilip [url] adresine yüklenen küçük görseli önceden
  /// hazırlar: baytlar indirme önbelleğine konur ve görsel çözülüp Flutter'ın
  /// görsel önbelleğine alınır. Görseli gösteren ilk ekran (ör. az önce
  /// gönderilen fotoğrafın sohbet baloncuğu) indirme ve yer tutucu beklemez.
  static void seed(String url, Uint8List bytes) {
    MealPhotoLoader.instance.remember(url, bytes);
    final ImageStream stream = MealThumbnailProvider(url: url, isOriginal: false)
        .resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo image, bool synchronousCall) {
        stream.removeListener(listener);
        image.dispose();
      },
      onError: (Object error, StackTrace? stackTrace) =>
          stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  @override
  Future<MealThumbnailProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<MealThumbnailProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      MealThumbnailProvider key, ImageDecoderCallback decode) {
    final StreamController<ImageChunkEvent> chunkEvents =
        StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('url', url),
      ],
    );
  }

  Future<ui.Codec> _loadCodec(
    MealThumbnailProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      return await _fetchAndDecode(decode, chunkEvents);
    } catch (e) {
      // NetworkImage'daki gibi: hatalı sonuç önbellekte kalırsa adres uygulama
      // yeniden açılana kadar bozuk görünür. Önbellekten çıkarılır ki sonraki
      // çözümleme yeniden denesin (önbellek anahtarı henüz eklememiş
      // olabilir; bu yüzden mikro görevde).
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    } finally {
      unawaited(chunkEvents.close());
    }
  }

  Future<ui.Codec> _fetchAndDecode(
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    final Uint8List bytes = await MealPhotoLoader.instance.fetch(
      url,
      immediate: immediate,
      onProgress: (int received, int? total) => chunkEvents.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: received,
          expectedTotalBytes: total,
        ),
      ),
    );

    if (isOriginal && onOriginalLoaded != null) {
      // Gösterimi bekletmez; üretim arka planda sürer.
      unawaited(onOriginalLoaded!(bytes).catchError((Object e) {}));
    }

    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(bytes);
    if (!isOriginal && decodeShortSide == null) return decode(buffer);

    return decode(
      buffer,
      getTargetSize: (int intrinsicWidth, int intrinsicHeight) =>
          targetSizeFor(
        intrinsicWidth,
        intrinsicHeight,
        isOriginal: isOriginal,
        shortSide: decodeShortSide,
      ),
    );
  }

  @visibleForTesting
  static ui.TargetImageSize targetSizeFor(
    int width,
    int height, {
    required bool isOriginal,
    int? shortSide,
  }) {
    if (shortSide != null &&
        shortSide > 0 &&
        math.min(width, height) > shortSide) {
      if (width <= height) return ui.TargetImageSize(width: shortSide);
      if (!isOriginal || width * shortSide / height <= maxDecodeWidth) {
        return ui.TargetImageSize(height: shortSide);
      }
    }
    if (isOriginal && width > maxDecodeWidth) {
      return const ui.TargetImageSize(width: maxDecodeWidth);
    }
    return ui.TargetImageSize(width: width, height: height);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MealThumbnailProvider &&
          other.url == url &&
          other.isOriginal == isOriginal &&
          other.decodeShortSide == decodeShortSide;

  @override
  int get hashCode => Object.hash(url, isOriginal, decodeShortSide);
}

/// Liste kartındaki küçük görsel: yüklenene kadar **hareketsiz** bir yer
/// tutucu gösterir.
///
/// `Image.network` + `loadingBuilder` yüklenene kadar her karede yeniden
/// çizilir ve dönen bir gösterge çalıştırır; onlarca kartta bu, listenin
/// kasmasının başlıca sebebiydi. `frameBuilder` yalnızca ilk kare çözüldüğünde
/// bir kez çalışır.
///
/// Yüklenemeyen görselin yer tutucusuna dokununca görsel yeniden denenir.
/// Dokunuş ham işaretçi olaylarından ([Listener]) okunur, dokunma
/// algılayıcılarıyla yarışmaz: kartın ya da baloncuğun kendi dokunuşu (büyük
/// görsel, tam ekran, sohbete gitme) her zamanki gibi çalışır, küçük görsel
/// de arkada yeniden yüklenir.
class MealThumbnailImage extends StatefulWidget {
  final String url;
  final bool isOriginal;
  final OriginalBytesCallback? onOriginalLoaded;
  final BoxFit fit;

  final double? decodeSize;

  const MealThumbnailImage({
    super.key,
    required this.url,
    required this.isOriginal,
    this.onOriginalLoaded,
    this.fit = BoxFit.cover,
    this.decodeSize,
  });

  @override
  State<MealThumbnailImage> createState() => _MealThumbnailImageState();
}

class _MealThumbnailImageState extends State<MealThumbnailImage> {
  /// [Image]'ın anahtarı; artınca görsel yeniden çözülür (hatalı sonuç
  /// önbellekten çıkarılmış olduğu için yeniden indirilir).
  int _attempt = 0;

  /// Yer tutucuda basılan nokta; parmak kaydırmaya dönüştüyse (liste
  /// kaydırılıyor) yeniden denenmez.
  Offset? _downPosition;

  void _onPointerUp(PointerUpEvent event) {
    final Offset? down = _downPosition;
    _downPosition = null;
    if (down == null || (event.position - down).distance > kTouchSlop) return;
    if (!mounted) return;
    setState(() => _attempt++);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) {
      return const _ThumbnailPlaceholder(icon: Icons.image);
    }

    final double? decodeSize = widget.decodeSize;
    return Image(
      key: ValueKey<int>(_attempt),
      image: MealThumbnailProvider(
        url: widget.url,
        isOriginal: widget.isOriginal,
        onOriginalLoaded: widget.onOriginalLoaded,
        decodeShortSide: decodeSize == null
            ? null
            : (decodeSize * MediaQuery.devicePixelRatioOf(context)).ceil(),
      ),
      fit: widget.fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          frame == null
              ? const _ThumbnailPlaceholder(icon: Icons.image_outlined)
              : child,
      errorBuilder: (context, error, stackTrace) => Listener(
        onPointerDown: (event) => _downPosition = event.position,
        onPointerUp: _onPointerUp,
        onPointerCancel: (event) => _downPosition = null,
        child: const _ThumbnailPlaceholder(icon: Icons.broken_image_outlined),
      ),
    );
  }
}

class MealOriginalImage extends StatelessWidget {
  static const String loadErrorText = 'Görsel yüklenemedi';

  final String url;
  final String? thumbUrl;
  final BoxFit fit;
  final Color? progressColor;
  final Color? errorColor;

  const MealOriginalImage({
    super.key,
    required this.url,
    this.thumbUrl,
    this.fit = BoxFit.contain,
    this.progressColor,
    this.errorColor,
  });

  @override
  Widget build(BuildContext context) {
    final String thumbUrl = this.thumbUrl ?? '';
    final Widget placeholder = thumbUrl.isEmpty
        ? const SizedBox.shrink()
        : Image(
            image: MealThumbnailProvider(url: thumbUrl, isOriginal: false),
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          );

    return Image(
      image: MealThumbnailProvider.fullSize(url),
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          frame == null ? placeholder : child,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        final int? total = loadingProgress.expectedTotalBytes;
        return Stack(
          fit: StackFit.passthrough,
          alignment: Alignment.center,
          children: [
            child,
            UnconstrainedBox(
              child: CircularProgressIndicator(
                color: progressColor,
                value: total != null && total > 0
                    ? loadingProgress.cumulativeBytesLoaded / total
                    : null,
              ),
            ),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) {
        final Color color = errorColor ?? Colors.grey.shade600;
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: color, size: 48),
                const SizedBox(height: 8),
                Text(
                  loadErrorText,
                  maxLines: 1,
                  style: TextStyle(color: color),
                ),
              ],
            ),
          ),
        );
      },
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
