// lib/widgets/camera_capture_page.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../utils/dialog_utils.dart';
import '../utils/temp_photo_files.dart';
import 'photo_edit_page.dart';

/// Kamerayı uygulamanın içinde açar (bkz. [CameraCapturePage]). Gönderilen
/// fotoğraf döner; kameradan çıkılırsa null.
Future<XFile?> showCameraCapturePage(BuildContext context) {
  return Navigator.of(context).push<XFile>(
    MaterialPageRoute<XFile>(
      fullscreenDialog: true,
      builder: (_) => const CameraCapturePage(),
    ),
  );
}

/// Uygulama içi kamera: fotoğraf çekilince sistem kamerasının "Fotoğrafı
/// Kullan / Yeniden Çek" adımı olmadan doğrudan kırpma ve döndürme ekranı
/// ([PhotoEditPage]) açılır; oradan gönderilen fotoğrafla kamera kapanır.
/// Düzenleme ekranından vazgeçilirse kameraya dönülür, yeniden çekilir.
///
/// Arka kamera açılır; flaş (kapalı / otomatik / açık), iki parmakla
/// yakınlaştırma ve dokunulan yere odaklanma vardır. Uygulama arka plana
/// geçince kamera bırakılır, öne gelince yeniden açılır. Kamera izni
/// açılmadan önce sorulur (bkz. `ChatPage`).
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver {
  static const String _closeTooltip = 'Kapat';
  static const String _shutterLabel = 'Fotoğraf çek';
  static const String _unavailableText = 'Kamera açılamadı.';
  static const String _captureErrorTitle = 'Hata';
  static const String _captureErrorText =
      'Fotoğraf çekilemedi. Lütfen tekrar deneyin.';

  static const Map<FlashMode, IconData> _flashIcons = {
    FlashMode.off: Icons.flash_off,
    FlashMode.auto: Icons.flash_auto,
    FlashMode.always: Icons.flash_on,
  };
  static const Map<FlashMode, String> _flashTooltips = {
    FlashMode.off: 'Flaş kapalı',
    FlashMode.auto: 'Flaş otomatik',
    FlashMode.always: 'Flaş açık',
  };

  /// Flaş düğmesine basıldıkça sırayla geçilen ayarlar.
  static const List<FlashMode> _flashCycle = [
    FlashMode.off,
    FlashMode.auto,
    FlashMode.always,
  ];

  static const double _shutterSize = 76;
  static const double _shutterRing = 4;
  static const double _shutterGap = 5;

  CameraDescription? _camera;
  CameraController? _controller;

  /// Kamera açılamadı (cihazda kamera yok ya da açılırken hata verdi).
  bool _unavailable = false;

  /// Uygulama arka plana geçtiği için kamera bırakıldı; öne gelince açılır.
  bool _released = false;

  /// Her açılışta ve arka plana geçişte artar: süren bir açılış geçersiz
  /// kalır, açtığı kamera bırakılır (iki kamera birden tutulmaz).
  int _openGeneration = 0;

  bool _capturing = false;

  /// Çekilen fotoğraf düzenleme ekranında; kamera önizlemesi duraklatıldı.
  bool _editing = false;

  FlashMode _flashMode = FlashMode.off;

  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;

  /// İki parmak hareketi başladığındaki yakınlaştırma.
  double _baseZoom = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (_released) return;
      _released = true;
      _openGeneration++;
      final CameraController? controller = _controller;
      if (controller == null) return;
      setState(() => _controller = null);
      controller.dispose();
    } else if (state == AppLifecycleState.resumed && _released) {
      _released = false;
      _open();
    }
  }

  /// Arka kamerayı açar (yoksa ilk kamerayı).
  Future<void> _open() async {
    final int generation = ++_openGeneration;
    bool stale() => !mounted || generation != _openGeneration;
    try {
      CameraDescription? camera = _camera;
      if (camera == null) {
        final List<CameraDescription> cameras = await availableCameras();
        if (stale()) return;
        if (cameras.isEmpty) {
          setState(() => _unavailable = true);
          return;
        }
        camera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );
        _camera = camera;
      }

      final CameraController controller = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await controller.initialize();
      if (stale()) {
        await controller.dispose();
        return;
      }
      await _applyFlashMode(controller, _flashMode);
      final double minZoom = await controller.getMinZoomLevel();
      final double maxZoom = await controller.getMaxZoomLevel();
      if (stale()) {
        await controller.dispose();
        return;
      }
      // Düzenleme ekranı açıkken (arka plandan dönüldü) önizleme durur.
      if (_editing) controller.pausePreview().catchError((Object e) {});
      setState(() {
        _controller = controller;
        _unavailable = false;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _zoom = minZoom;
      });
    } catch (e) {
      // Kamera açılamadı (izin, donanım ya da bu platformda kamera yok).
      if (!stale()) setState(() => _unavailable = true);
    }
  }

  /// Flaşı ayarlar; cihaz desteklemiyorsa (ör. flaşı yok) ayar değişmez.
  static Future<bool> _applyFlashMode(
    CameraController controller,
    FlashMode mode,
  ) async {
    try {
      await controller.setFlashMode(mode);
      return true;
    } on CameraException {
      return false;
    }
  }

  Future<void> _cycleFlash() async {
    final CameraController? controller = _controller;
    if (controller == null) return;
    final FlashMode next = _flashCycle[
        (_flashCycle.indexOf(_flashMode) + 1) % _flashCycle.length];
    if (await _applyFlashMode(controller, next) && mounted) {
      setState(() => _flashMode = next);
    }
  }

  void _onScaleStart(ScaleStartDetails details) => _baseZoom = _zoom;

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final CameraController? controller = _controller;
    if (controller == null || details.pointerCount < 2) return;
    final double zoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    if (zoom == _zoom) return;
    _zoom = zoom;
    controller.setZoomLevel(zoom).catchError((Object e) {});
  }

  /// Dokunulan yere odaklanır ve pozlamayı oraya göre ayarlar.
  void _focusAt(TapDownDetails details, BoxConstraints constraints) {
    final CameraController? controller = _controller;
    if (controller == null) return;
    final Offset point = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    if (controller.value.exposurePointSupported) {
      controller.setExposurePoint(point).catchError((Object e) {});
    }
    if (controller.value.focusPointSupported) {
      controller.setFocusPoint(point).catchError((Object e) {});
    }
  }

  /// Fotoğrafı çeker ve düzenleme ekranında açar. Gönderilirse kamera o
  /// fotoğrafla kapanır; vazgeçilirse kameraya dönülür. Kullanılmayan dosyalar
  /// silinir.
  Future<void> _capture() async {
    final CameraController? controller = _controller;
    if (controller == null ||
        _capturing ||
        _editing ||
        controller.value.isTakingPicture) {
      return;
    }

    setState(() => _capturing = true);
    XFile? shot;
    try {
      shot = await controller.takePicture();
    } on CameraException {
      shot = null;
    }
    if (!mounted) {
      if (shot != null) unawaited(TempPhotoFiles.delete(shot.path));
      return;
    }
    setState(() => _capturing = false);
    if (shot == null) {
      await DialogUtils.openError(
        context,
        title: _captureErrorTitle,
        message: _captureErrorText,
      );
      return;
    }

    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    setState(() => _editing = true);
    controller.pausePreview().catchError((Object e) {});
    final XFile? edited = await showPhotoEditPage(context, shot);
    if (edited?.path != shot.path) unawaited(TempPhotoFiles.delete(shot.path));

    // Kamera bu arada kapandıysa (ör. bildirimden sayfa açıldı) fotoğraf
    // gönderilmez.
    if (!mounted || route == null || !route.isActive) {
      if (edited != null) unawaited(TempPhotoFiles.delete(edited.path));
      return;
    }
    if (edited != null) {
      DialogUtils.closeOwnRoute(context, edited);
      return;
    }
    setState(() => _editing = false);
    // Düzenlerken uygulama arka plana geçtiyse kamera yeniden açılmış ve
    // duraklatılmıştır: devam eden o kameradır.
    _controller?.resumePreview().catchError((Object e) {});
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final CameraController? controller = _controller;
    final bool ready = controller != null && !_editing;

    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: _buildPreview(controller)),
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      IconButton.filled(
                        tooltip: _flashTooltips[_flashMode],
                        style: _overlayButtonStyle,
                        icon: Icon(_flashIcons[_flashMode]),
                        onPressed: ready ? _cycleFlash : null,
                      ),
                      const Spacer(),
                      IconButton.filled(
                        tooltip: _closeTooltip,
                        style: _overlayButtonStyle,
                        icon: const Icon(Icons.close),
                        onPressed: _close,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: _buildShutter(ready),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final ButtonStyle _overlayButtonStyle = IconButton.styleFrom(
    backgroundColor: Colors.black54,
    foregroundColor: Colors.white,
    disabledBackgroundColor: Colors.black26,
  );

  Widget _buildPreview(CameraController? controller) {
    if (_unavailable) {
      return const Text(_unavailableText, textAlign: TextAlign.center);
    }
    if (controller == null) return const CircularProgressIndicator();
    return CameraPreview(
      controller,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onTapDown: (details) => _focusAt(details, constraints),
        ),
      ),
    );
  }

  Widget _buildShutter(bool ready) {
    final bool enabled = ready && !_capturing;
    return Semantics(
      button: true,
      enabled: enabled,
      label: _shutterLabel,
      child: GestureDetector(
        onTap: enabled ? _capture : null,
        child: Container(
          width: _shutterSize,
          height: _shutterSize,
          padding: const EdgeInsets.all(_shutterGap),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: _shutterRing),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}
