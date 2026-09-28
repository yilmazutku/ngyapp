// lib/widgets/full_screen_image_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'meal_thumbnail_image.dart';

/// Fotoğrafı tam ekranda açar (bkz. [FullScreenImagePage]). Görüntüleyici
/// bir değerle kapanırsa (ör. alt çubuktaki bir düğme) o değer döner.
Future<T?> showFullScreenImage<T>(
  BuildContext context, {
  required String imageUrl,
  String? thumbUrl,
  String? title,
  WidgetBuilder? bottomBarBuilder,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: FullScreenImagePage._transitionDuration,
      reverseTransitionDuration: FullScreenImagePage._transitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          FullScreenImagePage(
        imageUrl: imageUrl,
        thumbUrl: thumbUrl,
        title: title,
        bottomBarBuilder: bottomBarBuilder,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Tam ekran fotoğraf sayfası (duyuru ayrıntısındaki tam ekran görselden
/// ortak widget'a taşındı; duyurular ve sohbet bunu kullanır): siyah zemin,
/// iki parmakla ya da çift dokunuşla yakınlaştırma, her fotoğrafta seçilen
/// koyu zeminli kapatma düğmesi, aşağı ya da yukarı kaydırarak kapatma
/// (yakınlaştırılmamışken) ve masaüstünde Esc. Orijinal inerken varsa küçük
/// görsel gösterilir; ekran boş kalmaz.
class FullScreenImagePage extends StatefulWidget {
  final String imageUrl;
  final String? thumbUrl;
  final String? title;

  /// Verilirse fotoğrafın altında işlemler çubuğu olarak gösterilir.
  final WidgetBuilder? bottomBarBuilder;

  const FullScreenImagePage({
    super.key,
    required this.imageUrl,
    this.thumbUrl,
    this.title,
    this.bottomBarBuilder,
  });

  static const Duration _transitionDuration = Duration(milliseconds: 200);

  @override
  State<FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<FullScreenImagePage>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 1.0;
  static const double _maxScale = 5.0;
  static const double _doubleTapScale = 2.5;

  /// Bu kadar kaydırınca ya da bu hızla bırakınca görüntüleyici kapanır.
  static const double _dismissDistance = 120.0;
  static const double _dismissVelocity = 800.0;

  /// Kaydırma bu mesafeye ulaşınca zemin tamamen saydamlaşır.
  static const double _fadeDistance = 400.0;
  static const Duration _springBackDuration = Duration(milliseconds: 180);

  static const String _closeTooltip = 'Kapat';
  static const String _loadErrorText = 'Görsel yüklenemedi';

  final TransformationController _transformation = TransformationController();
  late final AnimationController _springBack;
  Animation<double>? _springBackAnimation;

  double _dragOffset = 0;
  bool _zoomed = false;
  Offset? _doubleTapPosition;

  @override
  void initState() {
    super.initState();
    _springBack = AnimationController(vsync: this, duration: _springBackDuration)
      ..addListener(() {
        final Animation<double>? animation = _springBackAnimation;
        if (animation != null) setState(() => _dragOffset = animation.value);
      });
  }

  @override
  void dispose() {
    _springBack.dispose();
    _transformation.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _updateZoomed() {
    final bool zoomed =
        _transformation.value.getMaxScaleOnAxis() > _minScale + 0.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _toggleDoubleTapZoom() {
    if (_zoomed) {
      _transformation.value = Matrix4.identity();
    } else {
      final Offset position = _doubleTapPosition ?? Offset.zero;
      _transformation.value = Matrix4.identity()
        ..translateByDouble(
          -position.dx * (_doubleTapScale - 1),
          -position.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
    _updateZoomed();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _springBack.stop();
    setState(() => _dragOffset += details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0;
    if (_dragOffset.abs() > _dismissDistance ||
        velocity.abs() > _dismissVelocity) {
      _close();
      return;
    }
    _springBackAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _springBack, curve: Curves.easeOut),
    );
    _springBack.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final double backgroundOpacity =
        (1 - _dragOffset.abs() / _fadeDistance).clamp(0.0, 1.0);
    final WidgetBuilder? bottomBarBuilder = widget.bottomBarBuilder;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Colors.black.withValues(alpha: backgroundOpacity),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onVerticalDragUpdate: _zoomed ? null : _onDragUpdate,
                onVerticalDragEnd: _zoomed ? null : _onDragEnd,
                onDoubleTapDown: (details) =>
                    _doubleTapPosition = details.localPosition,
                onDoubleTap: _toggleDoubleTapZoom,
                child: Transform.translate(
                  offset: Offset(0, _dragOffset),
                  child: InteractiveViewer(
                    transformationController: _transformation,
                    minScale: _minScale,
                    maxScale: _maxScale,
                    panEnabled: _zoomed,
                    onInteractionEnd: (_) => _updateZoomed(),
                    child: Center(child: _buildImage()),
                  ),
                ),
              ),
              _buildTopBar(context),
              if (bottomBarBuilder != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black54,
                    child: SafeArea(
                      top: false,
                      child: bottomBarBuilder(context),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final String? title = widget.title;

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              IconButton.filled(
                tooltip: _closeTooltip,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close),
                onPressed: _close,
              ),
              if (title != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final String? thumbUrl = widget.thumbUrl;
    // Küçük görsel listede/sohbette zaten inmiş olur: aynı sağlayıcıyla
    // önbellekten gelir, yeniden indirilmez.
    final Widget placeholder = thumbUrl == null
        ? const SizedBox.shrink()
        : Image(
            image: MealThumbnailProvider(url: thumbUrl, isOriginal: false),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          );

    return Image.network(
      widget.imageUrl,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        final int? total = loadingProgress.expectedTotalBytes;
        return Stack(
          alignment: Alignment.center,
          children: [
            placeholder,
            CircularProgressIndicator(
              color: Colors.white,
              value: total != null
                  ? loadingProgress.cumulativeBytesLoaded / total
                  : null,
            ),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
          SizedBox(height: 8),
          Text(_loadErrorText, style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
