import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngy_app/services/meal_photo_loader.dart';
import 'package:ngy_app/widgets/meal_thumbnail_image.dart';

/// İstekleri sayan, hep 404 dönen sahte istemci; yükleyiciye takılır, disk
/// önbelleği kapatılır.
///
/// Testin gövdesinde kurulur: yükleyicinin beklediği hazır Future'lar testin
/// (sahte zamanlı) bölgesinde oluşmalı, yoksa devamları çalışmaz.
class _FailingServer {
  final List<String> requests = <String>[];

  _FailingServer() {
    final MealPhotoLoader loader = MealPhotoLoader.instance;
    loader.client = MockClient((request) async {
      requests.add(request.url.toString());
      return http.Response('', 404);
    });
    loader.cacheDirectory = null;
  }
}

int _urlSeed = 0;

Future<Uint8List> _png(int width, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF336699),
  );
  final ui.Image image =
      await recorder.endRecording().toImage(width, height);
  final ByteData? data =
      await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<Size> _decodedSize(ImageProvider provider) {
  final Completer<Size> done = Completer<Size>();
  final ImageStream stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, synchronousCall) {
      stream.removeListener(listener);
      done.complete(Size(
        image.image.width.toDouble(),
        image.image.height.toDouble(),
      ));
    },
    onError: (exception, stackTrace) {
      stream.removeListener(listener);
      done.completeError(exception, stackTrace);
    },
  );
  stream.addListener(listener);
  return done.future;
}

/// Her test kendi adresini kullanır: görsel önbelleği testler arasında
/// paylaşılır.
String _nextUrl() => 'https://example.com/thumb_${_urlSeed++}.jpg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed load is evicted so the next resolve downloads again',
      () async {
    final _FailingServer server = _FailingServer();
    final String url = _nextUrl();
    final MealThumbnailProvider provider =
        MealThumbnailProvider(url: url, isOriginal: false);

    Future<Object> resolveError() {
      final Completer<Object> error = Completer<Object>();
      final ImageStream stream = provider.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (image, synchronousCall) {},
        onError: (exception, stackTrace) {
          stream.removeListener(listener);
          error.complete(exception);
        },
      );
      stream.addListener(listener);
      return error.future;
    }

    expect(await resolveError(), isA<PhotoDownloadException>());
    await Future<void>.delayed(Duration.zero);
    expect(PaintingBinding.instance.imageCache.containsKey(provider), isFalse);

    expect(await resolveError(), isA<PhotoDownloadException>());
    expect(server.requests, <String>[url, url]);
  });

  testWidgets(
      'tapping a broken thumbnail retries it and still taps the parent',
      (tester) async {
    final _FailingServer server = _FailingServer();
    final String url = _nextUrl();
    int parentTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: GestureDetector(
            onTap: () => parentTaps++,
            child: SizedBox(
              width: 120,
              height: 120,
              child: MealThumbnailImage(url: url, isOriginal: false),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(server.requests, hasLength(1));

    // Yeniden çizim tek başına yeniden indirmez.
    await tester.pump();
    expect(server.requests, hasLength(1));

    await tester.tap(find.byType(MealThumbnailImage));
    await tester.pumpAndSettle();
    expect(parentTaps, 1);
    expect(server.requests, hasLength(2));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

    // Yer tutucunun üstünden kaydırmak yeniden denemez.
    await tester.drag(find.byType(MealThumbnailImage), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(server.requests, hasLength(2));
    expect(parentTaps, 1);
  }, variant: TargetPlatformVariant.all());

  test('small previews are decoded by their short side, never upscaled', () {
    ui.TargetImageSize target(int w, int h, {required bool original,
            int? shortSide}) =>
        MealThumbnailProvider.targetSizeFor(w, h,
            isOriginal: original, shortSide: shortSide);

    expect(target(480, 640, original: false).width, 480);
    expect(target(480, 640, original: false).height, 640);
    expect(target(480, 640, original: false, shortSide: 96).width, 96);
    expect(target(480, 640, original: false, shortSide: 96).height, isNull);
    expect(target(640, 480, original: false, shortSide: 96).height, 96);
    expect(target(640, 480, original: false, shortSide: 96).width, isNull);
    expect(target(50, 80, original: false, shortSide: 96).width, 50);
    expect(target(50, 80, original: false, shortSide: 96).height, 80);
    expect(target(3000, 4000, original: true).width,
        MealThumbnailProvider.maxDecodeWidth);
    expect(target(3000, 4000, original: true, shortSide: 96).width, 96);
    expect(target(4000, 300, original: true, shortSide: 96).width,
        MealThumbnailProvider.maxDecodeWidth);
    expect(target(4000, 300, original: false, shortSide: 96).height, 96);
  });

  test('the decode size is part of the cache key', () {
    const MealThumbnailProvider full =
        MealThumbnailProvider(url: 'u', isOriginal: false);
    expect(full, const MealThumbnailProvider(url: 'u', isOriginal: false));
    expect(
        full,
        isNot(const MealThumbnailProvider(
            url: 'u', isOriginal: false, decodeShortSide: 96)));
    expect(
        const MealThumbnailProvider(
            url: 'u', isOriginal: false, decodeShortSide: 96),
        const MealThumbnailProvider(
            url: 'u', isOriginal: false, decodeShortSide: 96));
  });

  test('a thumbnail is decoded small only when a decode size is given',
      () async {
    final Uint8List png = await _png(200, 300);
    final MealPhotoLoader loader = MealPhotoLoader.instance;
    loader.client =
        MockClient((request) async => http.Response.bytes(png, 200));
    loader.cacheDirectory = null;
    final String url = _nextUrl();

    expect(
      await _decodedSize(MealThumbnailProvider(url: url, isOriginal: false)),
      const Size(200, 300),
    );
    expect(
      await _decodedSize(MealThumbnailProvider(
          url: url, isOriginal: false, decodeShortSide: 64)),
      const Size(64, 96),
    );
  });

  testWidgets('the preview asks for its size in physical pixels',
      (tester) async {
    _FailingServer();
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: MealThumbnailImage(
            url: _nextUrl(),
            isOriginal: false,
            decodeSize: 32,
          ),
        ),
      ),
    ));
    final MealThumbnailProvider provider =
        tester.widget<Image>(find.byType(Image)).image as MealThumbnailProvider;
    expect(provider.decodeShortSide, 96);
    await tester.pumpAndSettle();
  });
}
