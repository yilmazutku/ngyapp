import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;

import '../models/logger.dart';

final Logger _log = Logger('ImageThumbnail');

/// Küçük görselin kısa kenarı (piksel). Liste kartları ~200 mantıksal px;
/// 320 px, 1.5x yoğunluklu ekranda bile net kalır.
const int kThumbnailShortSide = 320;

/// Küçük görsel JPEG kalitesi. Kartta fark edilmez, dosya ~25-40 KB olur.
const int kThumbnailJpegQuality = 75;

/// Üretilmiş küçük görsel.
class ThumbnailData {
  final Uint8List bytes;
  final String contentType;

  /// Dosya adına eklenecek uzantı (noktayla): `.jpg` ya da `.png`.
  final String extension;

  const ThumbnailData({
    required this.bytes,
    required this.contentType,
    required this.extension,
  });
}

/// [bytes] ile verilen fotoğraftan kısa kenarı [kThumbnailShortSide] piksel
/// olan küçük bir görsel üretir.
///
/// Neden var: Liste ekranları her fotoğrafın **tamamını** indirmek zorunda
/// kalmasın. Küçük görsel orijinalin 50-100'de biri boyutundadır; 87 fotoğraflı
/// bir sayfa 350 MB yerine birkaç MB indirir.
///
/// İki yol denenir:
/// 1. `flutter_image_compress` (Android/iOS): donanım hızlandırmalı, JPEG.
/// 2. Flutter'ın kendi çözücüsü (`dart:ui`): her platformda çalışır, PNG
///    üretir. Eklentinin olmadığı masaüstünde eski fotoğrafların küçük
///    görselini üretmek için (bkz. MealManager.backfillThumbnail).
///
/// Hiçbiri başaramazsa `null` döner; çağıran taraf küçük görselsiz devam eder.
Future<ThumbnailData?> generateThumbnail(Uint8List bytes) async {
  try {
    final Uint8List jpeg = await fic.FlutterImageCompress.compressWithList(
      bytes,
      minWidth: kThumbnailShortSide,
      minHeight: kThumbnailShortSide,
      quality: kThumbnailJpegQuality,
      format: fic.CompressFormat.jpeg,
      keepExif: false,
    );
    if (jpeg.isNotEmpty) {
      return ThumbnailData(
          bytes: jpeg, contentType: 'image/jpeg', extension: '.jpg');
    }
  } catch (e) {
    _log.debug('Native thumbnail generation unavailable: {}', [e]);
  }

  return _generateWithDartUi(bytes);
}

/// Flutter motoruyla küçültme. Yalnızca hedef genişlik verilir: yükseklik
/// orandan hesaplanır, görsel hiçbir koşulda yamulmaz.
Future<ThumbnailData?> _generateWithDartUi(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);

    final int width = descriptor.width;
    final int height = descriptor.height;
    if (width <= 0 || height <= 0) return null;

    // Kısa kenar hedefe inecek şekilde genişlik seçilir; küçük görsel zaten
    // küçükse büyütülmez.
    final int shortSide = width < height ? width : height;
    final int targetWidth = shortSide <= kThumbnailShortSide
        ? width
        : (width * kThumbnailShortSide / shortSide).round();

    codec = await descriptor.instantiateCodec(targetWidth: targetWidth);
    final ui.FrameInfo frame = await codec.getNextFrame();
    image = frame.image;

    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;

    return ThumbnailData(
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      contentType: 'image/png',
      extension: '.png',
    );
  } catch (e) {
    _log.warn('Thumbnail generation failed: {}', [e]);
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
