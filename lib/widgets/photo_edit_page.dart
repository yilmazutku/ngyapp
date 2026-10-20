// lib/widgets/photo_edit_page.dart
import 'dart:io' show Directory, File;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/dialog_utils.dart';

/// Kameradan çekilen fotoğrafı göndermeden önce kırpma ve 90 derecelik
/// döndürme ekranında açar (bkz. [PhotoEditPage]). Düzenlenen fotoğraf geçici
/// bir dosyaya yazılıp döner; hiçbir şey değiştirilmediyse fotoğrafın kendisi
/// döner. Vazgeçilirse null döner.
Future<XFile?> showPhotoEditPage(BuildContext context, XFile photo) {
  return Navigator.of(context).push<XFile>(
    MaterialPageRoute<XFile>(
      fullscreenDialog: true,
      builder: (_) => PhotoEditPage(photo: photo),
    ),
  );
}

/// WhatsApp'taki gibi fotoğraf düzenleme ekranı: köşelerinden ve
/// kenarlarından sürüklenen kırpma çerçevesi (içinden tutulunca çerçeve
/// taşınır), sola ve sağa 90 derecelik döndürme, "Sıfırla" ve onay.
///
/// Fotoğraf ekranda düzenlenebilecek bir ölçüye küçültülerek çözülür
/// ([_PhotoEditPageState._maxDecodeSide]); yüklemede zaten daha küçük bir
/// ölçüye indirildiği için kalite kaybı olmaz. Çözülemezse düzenleme atlanır ve
/// fotoğraf olduğu gibi döner.
class PhotoEditPage extends StatefulWidget {
  final XFile photo;

  const PhotoEditPage({super.key, required this.photo});

  @override
  State<PhotoEditPage> createState() => _PhotoEditPageState();
}

class _PhotoEditPageState extends State<PhotoEditPage> {
  static const String _cancelTooltip = 'Vazgeç';
  static const String _resetLabel = 'Sıfırla';
  static const String _rotateLeftTooltip = 'Sola döndür';
  static const String _rotateRightTooltip = 'Sağa döndür';
  static const String _doneTooltip = 'Tamam';
  static const String _errorTitle = 'Hata';
  static const String _exportErrorText =
      'Fotoğraf düzenlenemedi. Lütfen tekrar deneyin.';

  static const Rect _fullCrop = Rect.fromLTRB(0, 0, 1, 1);

  /// Çözülen fotoğrafın uzun kenarı en fazla bu kadar piksel olur.
  static const int _maxDecodeSide = 2560;
  static const int _jpegQuality = 92;

  /// Fotoğrafın ekranda kenarlardan boşluğu; çerçevenin tutamaçları ekranın
  /// kenarına yapışmasın.
  static const double _imageMargin = 24;

  /// Tutamaçlar bu kadar uzaktan da yakalanır (parmak için).
  static const double _touchRadius = 28;

  /// Kırpma çerçevesinin ekrandaki en küçük kenarı.
  static const double _minCropSide = 64;

  static const Color _doneColor = Color(0xFF25D366);

  ui.Image? _image;

  /// Saat yönünde kaç çeyrek tur döndürüldü (0-3).
  int _quarterTurns = 0;

  /// Kırpma alanı, döndürülmüş fotoğrafın ölçüsüne göre 0-1 arasında.
  Rect _crop = _fullCrop;

  /// Sürüklenen tutamaç; sürükleme yokken null.
  _CropDrag? _drag;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  bool get _changed => _quarterTurns != 0 || _crop != _fullCrop;

  Future<void> _load() async {
    ui.Image? image;
    try {
      final Uint8List bytes = await widget.photo.readAsBytes();
      final ui.ImmutableBuffer buffer =
          await ui.ImmutableBuffer.fromUint8List(bytes);
      final ui.Codec codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: _decodeSize,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      image = frame.image;
    } catch (e) {
      image = null;
    }

    if (!mounted) {
      image?.dispose();
      return;
    }
    if (image == null) {
      Navigator.of(context).pop(widget.photo);
      return;
    }
    setState(() => _image = image);
  }

  /// Yalnızca genişlik verilir: yükseklik orandan hesaplanır, fotoğraf
  /// yamulmaz.
  static ui.TargetImageSize _decodeSize(int width, int height) {
    final int longSide = math.max(width, height);
    if (longSide <= _maxDecodeSide) return const ui.TargetImageSize();
    return ui.TargetImageSize(
        width: (width * _maxDecodeSide / longSide).round());
  }

  /// Döndürülmüş fotoğrafın piksel ölçüsü.
  Size _rotatedSize(ui.Image image) => _quarterTurns.isOdd
      ? Size(image.height.toDouble(), image.width.toDouble())
      : Size(image.width.toDouble(), image.height.toDouble());

  /// Kırpma alanı döndürmeyle birlikte döner: kırpılan yer değişmez.
  void _rotate({required bool clockwise}) {
    final Rect crop = _crop;
    setState(() {
      _quarterTurns = (_quarterTurns + (clockwise ? 1 : 3)) % 4;
      _crop = clockwise
          ? Rect.fromLTRB(1 - crop.bottom, crop.left, 1 - crop.top, crop.right)
          : Rect.fromLTRB(crop.top, 1 - crop.right, crop.bottom, 1 - crop.left);
    });
  }

  void _reset() {
    setState(() {
      _quarterTurns = 0;
      _crop = _fullCrop;
    });
  }

  /// Fotoğrafın ekrandaki yeri: alana sığacak kadar büyük, ortada.
  Rect _imageRectIn(Size area, ui.Image image) {
    final Size rotated = _rotatedSize(image);
    final double maxWidth = math.max(1.0, area.width - _imageMargin * 2);
    final double maxHeight = math.max(1.0, area.height - _imageMargin * 2);
    final double scale =
        math.min(maxWidth / rotated.width, maxHeight / rotated.height);
    return Rect.fromCenter(
      center: area.center(Offset.zero),
      width: rotated.width * scale,
      height: rotated.height * scale,
    );
  }

  Rect _cropRectIn(Rect imageRect) => Rect.fromLTRB(
        imageRect.left + _crop.left * imageRect.width,
        imageRect.top + _crop.top * imageRect.height,
        imageRect.left + _crop.right * imageRect.width,
        imageRect.top + _crop.bottom * imageRect.height,
      );

  void _onPanStart(Offset position, Rect imageRect) {
    final Rect crop = _cropRectIn(imageRect);
    final bool withinX = position.dx >= crop.left - _touchRadius &&
        position.dx <= crop.right + _touchRadius;
    final bool withinY = position.dy >= crop.top - _touchRadius &&
        position.dy <= crop.bottom + _touchRadius;
    final double toLeft = (position.dx - crop.left).abs();
    final double toRight = (position.dx - crop.right).abs();
    final double toTop = (position.dy - crop.top).abs();
    final double toBottom = (position.dy - crop.bottom).abs();

    final bool nearLeft = withinY && toLeft <= _touchRadius;
    final bool nearRight = withinY && toRight <= _touchRadius;
    final bool nearTop = withinX && toTop <= _touchRadius;
    final bool nearBottom = withinX && toBottom <= _touchRadius;

    // Çerçeve küçükse iki karşı kenar da yakın olabilir: yakın olan seçilir.
    final _CropDrag drag = _CropDrag(
      left: nearLeft && (!nearRight || toLeft <= toRight),
      right: nearRight && (!nearLeft || toRight < toLeft),
      top: nearTop && (!nearBottom || toTop <= toBottom),
      bottom: nearBottom && (!nearTop || toBottom < toTop),
    );
    if (drag.moves && !crop.contains(position)) return;
    setState(() => _drag = drag);
  }

  void _onPanUpdate(Offset delta, Rect imageRect) {
    final _CropDrag? drag = _drag;
    if (drag == null) return;

    final Rect crop = _cropRectIn(imageRect);
    double left = crop.left;
    double top = crop.top;
    double right = crop.right;
    double bottom = crop.bottom;

    if (drag.moves) {
      final double dx = math.max(
          imageRect.left - left, math.min(delta.dx, imageRect.right - right));
      final double dy = math.max(
          imageRect.top - top, math.min(delta.dy, imageRect.bottom - bottom));
      left += dx;
      right += dx;
      top += dy;
      bottom += dy;
    } else {
      final double minWidth = math.min(_minCropSide, imageRect.width);
      final double minHeight = math.min(_minCropSide, imageRect.height);
      if (drag.left) {
        left = math.max(
            imageRect.left, math.min(left + delta.dx, right - minWidth));
      }
      if (drag.right) {
        right = math.min(
            imageRect.right, math.max(right + delta.dx, left + minWidth));
      }
      if (drag.top) {
        top = math.max(
            imageRect.top, math.min(top + delta.dy, bottom - minHeight));
      }
      if (drag.bottom) {
        bottom = math.min(
            imageRect.bottom, math.max(bottom + delta.dy, top + minHeight));
      }
    }

    setState(() {
      _crop = Rect.fromLTRB(
        ((left - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
        ((top - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
        ((right - imageRect.left) / imageRect.width).clamp(0.0, 1.0),
        ((bottom - imageRect.top) / imageRect.height).clamp(0.0, 1.0),
      );
    });
  }

  void _onPanEnd() {
    if (_drag != null) setState(() => _drag = null);
  }

  Future<void> _done() async {
    final ui.Image? image = _image;
    if (image == null || _saving) return;
    final NavigatorState navigator = Navigator.of(context);
    if (!_changed) {
      navigator.pop(widget.photo);
      return;
    }

    setState(() => _saving = true);
    final XFile? edited = await _export(image);
    if (!mounted) return;
    if (edited != null) {
      navigator.pop(edited);
      return;
    }

    setState(() => _saving = false);
    await DialogUtils.openError(
      context,
      title: _errorTitle,
      message: _exportErrorText,
    );
  }

  /// Döndürülmüş fotoğrafın kırpılan kısmını çizip geçici bir dosyaya yazar.
  Future<XFile?> _export(ui.Image image) async {
    ui.Image? output;
    try {
      final Size rotated = _rotatedSize(image);
      final Rect crop = Rect.fromLTRB(
        _crop.left * rotated.width,
        _crop.top * rotated.height,
        _crop.right * rotated.width,
        _crop.bottom * rotated.height,
      );
      final int width = math.max(1, crop.width.round());
      final int height = math.max(1, crop.height.round());

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.translate(-crop.left, -crop.top);
      _applyRotation(canvas, image);
      canvas.drawImage(image, Offset.zero, Paint());
      final ui.Picture picture = recorder.endRecording();
      output = await picture.toImage(width, height);
      picture.dispose();

      final ByteData? png =
          await output.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;
      final ({Uint8List bytes, String extension}) encoded = await _encode(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        width,
        height,
      );

      final Directory directory = await getTemporaryDirectory();
      final String path = p.join(
        directory.path,
        'photo_edit_${DateTime.now().microsecondsSinceEpoch}${encoded.extension}',
      );
      await File(path).writeAsBytes(encoded.bytes, flush: true);
      return XFile(path);
    } catch (e) {
      return null;
    } finally {
      output?.dispose();
    }
  }

  /// Fotoğrafı döndürülmüş hâliyle (0,0)'dan başlayarak çizdirir.
  void _applyRotation(Canvas canvas, ui.Image image) {
    final double width = image.width.toDouble();
    final double height = image.height.toDouble();
    switch (_quarterTurns) {
      case 1:
        canvas.translate(height, 0);
        canvas.rotate(math.pi / 2);
      case 2:
        canvas.translate(width, height);
        canvas.rotate(math.pi);
      case 3:
        canvas.translate(0, width);
        canvas.rotate(-math.pi / 2);
    }
  }

  /// JPEG'e çevirir; eklenti yoksa (masaüstü) PNG olarak kalır.
  static Future<({Uint8List bytes, String extension})> _encode(
    Uint8List png,
    int width,
    int height,
  ) async {
    try {
      final Uint8List jpeg = await fic.FlutterImageCompress.compressWithList(
        png,
        minWidth: width,
        minHeight: height,
        quality: _jpegQuality,
        format: fic.CompressFormat.jpeg,
      );
      if (jpeg.isNotEmpty) return (bytes: jpeg, extension: '.jpg');
    } catch (e) {
      // PNG yüklenir; yüklemede yine küçültülür.
    }
    return (bytes: png, extension: '.png');
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _image;

    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: image == null
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                        builder: (context, constraints) =>
                            _buildEditor(image, constraints.biggest),
                      ),
              ),
              _buildBottomBar(image != null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: _cancelTooltip,
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          TextButton(
            onPressed: _changed && !_saving ? _reset : null,
            child: const Text(_resetLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(ui.Image image, Size area) {
    final Rect imageRect = _imageRectIn(area, image);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _saving
          ? null
          : (details) => _onPanStart(details.localPosition, imageRect),
      onPanUpdate: (details) => _onPanUpdate(details.delta, imageRect),
      onPanEnd: (_) => _onPanEnd(),
      onPanCancel: _onPanEnd,
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: imageRect,
            child: RotatedBox(
              quarterTurns: _quarterTurns,
              child: RawImage(image: image, fit: BoxFit.fill),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _CropPainter(
                imageRect: imageRect,
                cropRect: _cropRectIn(imageRect),
                showGrid: _drag != null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool ready) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
      child: Row(
        children: [
          IconButton(
            tooltip: _rotateLeftTooltip,
            iconSize: 28,
            icon: const Icon(Icons.rotate_left),
            onPressed:
                ready && !_saving ? () => _rotate(clockwise: false) : null,
          ),
          IconButton(
            tooltip: _rotateRightTooltip,
            iconSize: 28,
            icon: const Icon(Icons.rotate_right),
            onPressed:
                ready && !_saving ? () => _rotate(clockwise: true) : null,
          ),
          const Spacer(),
          FloatingActionButton(
            heroTag: null,
            tooltip: _doneTooltip,
            backgroundColor: _doneColor,
            foregroundColor: Colors.white,
            onPressed: ready && !_saving ? _done : null,
            child: _saving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
    );
  }
}

/// Sürüklenen tutamaç: bir ya da iki kenar (köşe); hiçbiri değilse çerçeve
/// taşınır.
class _CropDrag {
  final bool left;
  final bool top;
  final bool right;
  final bool bottom;

  const _CropDrag({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  bool get moves => !left && !top && !right && !bottom;
}

/// Kırpma çerçevesi: dışı karartılır, kenarı ve köşe tutamaçları beyaz;
/// sürüklenirken üçte bir ızgarası görünür.
class _CropPainter extends CustomPainter {
  final Rect imageRect;
  final Rect cropRect;
  final bool showGrid;

  _CropPainter({
    required this.imageRect,
    required this.cropRect,
    required this.showGrid,
  });

  static const double _cornerLength = 22;
  static const double _cornerWidth = 4;
  static const double _borderWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(imageRect)
      ..addRect(cropRect);
    canvas.drawPath(outside, Paint()..color = Colors.black54);

    if (showGrid) {
      final Paint grid = Paint()
        ..color = Colors.white54
        ..strokeWidth = 1;
      for (int i = 1; i < 3; i++) {
        final double x = cropRect.left + cropRect.width * i / 3;
        final double y = cropRect.top + cropRect.height * i / 3;
        canvas.drawLine(
            Offset(x, cropRect.top), Offset(x, cropRect.bottom), grid);
        canvas.drawLine(
            Offset(cropRect.left, y), Offset(cropRect.right, y), grid);
      }
    }

    canvas.drawRect(
      cropRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = _borderWidth,
    );

    final Paint corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _cornerWidth
      ..strokeCap = StrokeCap.square;
    final double length = math.min(
      _cornerLength,
      math.min(cropRect.width, cropRect.height) / 2,
    );
    for (final Offset point in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ]) {
      final double dx = point.dx == cropRect.left ? length : -length;
      final double dy = point.dy == cropRect.top ? length : -length;
      canvas.drawPath(
        Path()
          ..moveTo(point.dx + dx, point.dy)
          ..lineTo(point.dx, point.dy)
          ..lineTo(point.dx, point.dy + dy),
        corner,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.imageRect != imageRect ||
      oldDelegate.cropRect != cropRect ||
      oldDelegate.showGrid != showGrid;
}
