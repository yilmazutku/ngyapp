import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;
import 'package:image_picker/image_picker.dart' show XFile;

/// Küçük görselin kısa kenarı (piksel). Liste kartları ~200, sohbet
/// baloncukları ~240 mantıksal px; 480 px, 2-3x yoğunluklu telefon ekranında
/// da baloncukta bulanık durmaz.
const int kThumbnailShortSide = 480;

/// Küçük görsel JPEG kalitesi. Kartta fark edilmez, dosya ~40-60 KB olur.
const int kThumbnailJpegQuality = 75;

/// Görselin piksel ölçüsü.
class ImagePixelSize {
  final int width;
  final int height;

  const ImagePixelSize(this.width, this.height);
}

/// [bytes] ile verilen görselin ölçüsünü yalnızca başlığını okuyarak verir
/// (görsel çözülmez); okunamazsa null. Sohbet baloncuğu görsel inmeden önce
/// doğru oranda yer ayırsın diye mesaja yazılır.
Future<ImagePixelSize?> readImagePixelSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 || descriptor.height <= 0) return null;
    return ImagePixelSize(descriptor.width, descriptor.height);
  } catch (e) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Görsel dosyanın başlığı genellikle bu kadar baytın içindedir (JPEG'de
/// EXIF bloğu en fazla 64 KB).
const int _headerReadBytes = 256 * 1024;

/// [file] görselinin ölçüsünü (EXIF yönü uygulanmış) önce yalnızca dosyanın
/// başını okuyarak verir; olmazsa dosyanın tamamını okur. Okunamazsa null.
/// Sohbette sıradaki fotoğrafın baloncuğu gerçek oranında çizilsin diye.
Future<ImagePixelSize?> readImageFilePixelSize(XFile file) async {
  try {
    final BytesBuilder header = BytesBuilder(copy: false);
    await for (final List<int> chunk in file.openRead(0, _headerReadBytes)) {
      header.add(chunk);
    }
    final ImagePixelSize? size = await readImagePixelSize(header.takeBytes());
    if (size != null) return size;
    return readImagePixelSize(await file.readAsBytes());
  } catch (e) {
    return null;
  }
}

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
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
