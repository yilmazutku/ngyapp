import 'dart:async';
import 'dart:io';
import 'dart:math' show Point;
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/widgets/camera_capture_page.dart';
import 'package:path/path.dart' as p;

/// Uygulama içi kamera yalnızca telefonda açılır.
const TargetPlatformVariant _phones = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.android,
  TargetPlatform.iOS,
});

const CameraDescription _backCamera = CameraDescription(
  name: 'arka',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// Kamera eklentisinin yerine: önizleme gri bir kutu, çekilen fotoğraflar
/// sırayla [shots]'taki dosyalar.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform({this.cameras = const [_backCamera]});

  final List<CameraDescription> cameras;
  final List<String> shots = [];
  int _taken = 0;

  int created = 0;
  final List<int> disposed = [];
  final List<FlashMode> flashModes = [];
  int pauses = 0;
  int resumes = 0;

  final Map<int, StreamController<CameraInitializedEvent>> _initialized = {};
  final StreamController<CameraErrorEvent> _errors =
      StreamController<CameraErrorEvent>.broadcast();

  StreamController<CameraInitializedEvent> _initializedOf(int cameraId) =>
      _initialized.putIfAbsent(
        cameraId,
        () => StreamController<CameraInitializedEvent>.broadcast(),
      );

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async =>
      ++created;

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initializedOf(cameraId).stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errors.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream<DeviceOrientationChangedEvent>.empty();

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    _initializedOf(cameraId).add(CameraInitializedEvent(
      cameraId,
      1080,
      1920,
      ExposureMode.auto,
      true,
      FocusMode.auto,
      true,
    ));
  }

  @override
  Future<XFile> takePicture(int cameraId) async => XFile(shots[_taken++]);

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async =>
      flashModes.add(mode);

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 4;

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {}

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {}

  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {}

  @override
  Future<void> pausePreview(int cameraId) async => pauses++;

  @override
  Future<void> resumePreview(int cameraId) async => resumes++;

  @override
  Widget buildPreview(int cameraId) =>
      ColoredBox(key: ValueKey<int>(cameraId), color: Colors.grey);

  @override
  Future<void> dispose(int cameraId) async => disposed.add(cameraId);
}

/// [showCameraCapturePage]'in sonucu; sayfa kapanınca [closed] olur.
class _Closing {
  bool closed = false;
  XFile? result;
}

Future<Uint8List> _png() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 40, 20),
    Paint()..color = const Color(0xFF00AA00),
  );
  final ui.Image image = await recorder.endRecording().toImage(40, 20);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  const MethodChannel pathProvider =
      MethodChannel('plugins.flutter.io/path_provider');
  late Directory temporary;
  late _FakeCameraPlatform camera;
  late CameraPlatform realPlatform;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('camera_capture_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => temporary.path);
    realPlatform = CameraPlatform.instance;
    camera = _FakeCameraPlatform();
    CameraPlatform.instance = camera;
  });

  tearDown(() {
    CameraPlatform.instance = realPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    temporary.deleteSync(recursive: true);
  });

  /// Kamerayı açar; önizleme görünene kadar bekler.
  Future<_Closing> openCamera(WidgetTester tester, {int shots = 1}) async {
    await tester.runAsync(() async {
      final Uint8List png = await _png();
      for (int i = 0; i < shots; i++) {
        final String path = p.join(temporary.path, 'cekim_$i.png');
        File(path).writeAsBytesSync(png);
        camera.shots.add(path);
      }
    });
    final _Closing closing = _Closing();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            closing.result = await showCameraCapturePage(context);
            closing.closed = true;
          },
          child: const Text('kamera'),
        ),
      ),
    ));
    await tester.tap(find.text('kamera'));
    await tester.pumpAndSettle();
    return closing;
  }

  Finder shutter() => find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Fotoğraf çek',
      );

  /// Deklanşöre basar; düzenleme ekranı fotoğrafı çözene kadar bekler.
  Future<void> capture(WidgetTester tester) async {
    await tester.tap(shutter());
    await tester.pump();
    for (int i = 0; i < 20 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget,
        reason: 'çekince doğrudan kırpma ekranı açılır');
  }

  testWidgets(
      'çekince "Fotoğrafı Kullan" adımı olmadan kırpma ekranı açılır; '
      'gönderilen fotoğrafla kamera kapanır', (tester) async {
    final _Closing closing = await openCamera(tester);
    expect(find.byKey(const ValueKey<int>(1)), findsOneWidget,
        reason: 'önizleme');

    await capture(tester);
    expect(camera.pauses, 1, reason: 'düzenlerken önizleme durur');
    expect(find.byIcon(Icons.send), findsOneWidget);

    await tester.tap(find.byTooltip('Gönder'));
    await tester.pumpAndSettle();

    expect(closing.closed, isTrue);
    expect(closing.result?.path, camera.shots.single,
        reason: 'değiştirilmeyen fotoğrafın kendisi gönderilir');
    expect(camera.disposed, [1], reason: 'kamera bırakılır');
  }, variant: _phones);

  testWidgets(
      'kırpma ekranında vazgeçilirse kameraya dönülür; yeniden çekilip '
      'gönderilebilir, ilk çekim silinir', (tester) async {
    final _Closing closing = await openCamera(tester, shots: 2);

    await capture(tester);
    await tester.tap(find.byTooltip('Vazgeç'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Vazgeç'));
    await tester.pumpAndSettle();

    expect(find.byType(RawImage), findsNothing);
    expect(shutter(), findsOneWidget, reason: 'kameraya dönüldü');
    expect(closing.closed, isFalse);
    expect(camera.resumes, 1, reason: 'önizleme sürer');
    for (int i = 0; i < 20 && File(camera.shots.first).existsSync(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(File(camera.shots.first).existsSync(), isFalse,
        reason: 'vazgeçilen çekim silinir');

    await capture(tester);
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pumpAndSettle();

    expect(closing.result?.path, camera.shots.last);
  }, variant: _phones);

  testWidgets('kameradaki çarpı hiçbir şey göndermeden kapatır',
      (tester) async {
    final _Closing closing = await openCamera(tester);

    final Rect close = tester.getRect(find.byTooltip('Kapat'));
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(close.right, greaterThan(screen.width - 16), reason: 'sağ üstte');

    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();

    expect(closing.closed, isTrue);
    expect(closing.result, isNull);
    expect(camera.disposed, [1]);
  }, variant: _phones);

  testWidgets('kamera yoksa "Kamera açılamadı" yazar, çarpıyla kapanır',
      (tester) async {
    camera = _FakeCameraPlatform(cameras: const []);
    CameraPlatform.instance = camera;
    final _Closing closing = await openCamera(tester);

    expect(find.text('Kamera açılamadı.'), findsOneWidget);
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();
    expect(closing.result, isNull);
  }, variant: _phones);

  testWidgets(
      'arka plana geçince kamera bırakılır, öne gelince yeniden açılır',
      (tester) async {
    await openCamera(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    // Kamera yeniden açılana kadar dönen gösterge görünür: ekran durulmaz.
    await tester.pump();
    await tester.pump();
    expect(camera.disposed, [1]);
    expect(find.byKey(const ValueKey<int>(1)), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.created, 2);
    expect(find.byKey(const ValueKey<int>(2)), findsOneWidget);
  }, variant: _phones);

  testWidgets(
      'düzenlerken arka plana geçip dönülürse yeni kamera duraklatılmış '
      'açılır; kameraya dönünce devam eder', (tester) async {
    await openCamera(tester);
    await capture(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.created, 2);
    expect(camera.pauses, 2, reason: 'düzenleme ekranının arkasında durur');

    await tester.tap(find.byTooltip('Vazgeç'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Vazgeç'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<int>(2)), findsOneWidget);
    expect(camera.resumes, 1, reason: 'yeni kamera devam eder');
  }, variant: _phones);

  testWidgets('flaş kapalı açılır; dokundukça otomatik ve açık olur',
      (tester) async {
    await openCamera(tester);
    expect(camera.flashModes, [FlashMode.off]);

    await tester.tap(find.byTooltip('Flaş kapalı'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Flaş otomatik'));
    await tester.pumpAndSettle();

    expect(camera.flashModes, [FlashMode.off, FlashMode.auto, FlashMode.always]);
    expect(find.byTooltip('Flaş açık'), findsOneWidget);
  }, variant: _phones);
}
