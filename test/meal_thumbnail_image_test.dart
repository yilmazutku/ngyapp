import 'dart:async';
import 'dart:io';
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

  test('a download reports its progress', () async {
    final MealPhotoLoader loader = MealPhotoLoader.instance;
    loader.client = MockClient.streaming(
      (request, body) async => http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          Uint8List(30),
          Uint8List(50),
          Uint8List(20),
        ]),
        200,
        contentLength: 100,
      ),
    );
    loader.cacheDirectory = null;

    final List<(int, int?)> progress = [];
    final Uint8List bytes = await loader.fetch(
      _nextUrl(),
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(bytes, hasLength(100));
    expect(progress, [(30, 100), (80, 100), (100, 100)]);
  });

  test('an immediate download does not wait for the queue', () async {
    final MealPhotoLoader loader = MealPhotoLoader.instance;
    final Completer<void> release = Completer<void>();
    loader.client = MockClient((request) async {
      if (request.url.path.contains('slow')) await release.future;
      return http.Response.bytes([1, 2, 3], 200);
    });
    loader.cacheDirectory = null;

    final List<Future<Uint8List>> slow = [
      for (int i = 0; i <= MealPhotoLoader.maxConcurrent; i++)
        loader.fetch('https://example.com/slow_${_urlSeed++}.jpg'),
    ];
    bool queuedDone = false;
    final Future<Uint8List> queued = loader.fetch(_nextUrl())
      ..then((_) => queuedDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(loader.activeCount, MealPhotoLoader.maxConcurrent);

    expect(await loader.fetch(_nextUrl(), immediate: true), [1, 2, 3]);
    expect(queuedDone, isFalse);
    expect(loader.activeCount, MealPhotoLoader.maxConcurrent);

    release.complete();
    await Future.wait([...slow, queued]);
    expect(queuedDone, isTrue);
    expect(loader.activeCount, 0);
  });

  test('oversized originals opened on their own are not kept on disk',
      () async {
    final Directory directory =
        Directory.systemTemp.createTempSync('meal_photo_cache_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final MealPhotoLoader loader = MealPhotoLoader.instance;
    loader.client = MockClient((request) async => http.Response.bytes(
          Uint8List(request.url.path.contains('big')
              ? MealPhotoLoader.diskCacheMaxFileBytes + 1
              : 2048),
          200,
        ));
    loader.cacheDirectory = directory;
    addTearDown(() => loader.cacheDirectory = null);

    const String small = 'https://example.com/cache_small.jpg';
    const String big = 'https://example.com/cache_big.jpg';
    const String listedBig = 'https://example.com/cache_big_listed.jpg';
    File cached(String url) =>
        File('${directory.path}/${MealPhotoLoader.cacheKeyFor(url)}');

    await loader.fetch(big, immediate: true);
    await loader.fetch(listedBig);
    await loader.fetch(small, immediate: true);
    for (int i = 0;
        i < 50 &&
            !(cached(small).existsSync() && cached(listedBig).existsSync());
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(cached(small).existsSync(), isTrue);
    expect(cached(listedBig).existsSync(), isTrue);
    expect(cached(big).existsSync(), isFalse);

    int requests = 0;
    loader.client = MockClient((request) async {
      requests++;
      return http.Response.bytes(Uint8List(2048), 200);
    });
    expect(await loader.fetch(small), hasLength(2048));
    expect(requests, 0);
  });

  test('the full-size provider decodes the original unscaled', () async {
    final Uint8List png = await _png(900, 700);
    final MealPhotoLoader loader = MealPhotoLoader.instance;
    loader.client =
        MockClient((request) async => http.Response.bytes(png, 200));
    loader.cacheDirectory = null;

    expect(
      await _decodedSize(MealThumbnailProvider.fullSize(_nextUrl())),
      const Size(900, 700),
    );
  });

  testWidgets(
      'the original shows its thumbnail and download progress until it loads',
      (tester) async {
    final Uint8List thumb = (await tester.runAsync(() => _png(40, 30)))!;
    final Uint8List original = (await tester.runAsync(() => _png(400, 300)))!;
    final String thumbUrl = _nextUrl();
    final String url = _nextUrl();
    final StreamController<List<int>> download = StreamController<List<int>>();
    final MealPhotoLoader loader = MealPhotoLoader.instance;
    loader.client = MockClient.streaming((request, body) async {
      if (request.url.toString() == thumbUrl) {
        return http.StreamedResponse(
          Stream<List<int>>.value(thumb),
          200,
          contentLength: thumb.length,
        );
      }
      return http.StreamedResponse(
        download.stream,
        200,
        contentLength: original.length,
      );
    });
    loader.cacheDirectory = null;

    Future<void> settle() async {
      for (int i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    ui.Image? shown() =>
        tester.widget<RawImage>(find.byType(RawImage)).image;

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 200,
          height: 150,
          child: MealOriginalImage(url: url, thumbUrl: thumbUrl),
        ),
      ),
    ));
    await settle();

    expect(shown()!.width, 40);
    expect(tester.getSize(find.byType(RawImage)), const Size(200, 150));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final int half = original.length ~/ 2;
    download.add(original.sublist(0, half));
    await settle();

    expect(shown()!.width, 40);
    expect(
      tester
          .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator))
          .value,
      closeTo(0.5, 0.01),
    );
    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(36, 36),
    );

    download.add(original.sublist(half));
    await download.close();
    await settle();

    expect(shown()!.width, 400);
    expect(tester.getSize(find.byType(RawImage)), const Size(200, 150));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an original that cannot be loaded shows the broken placeholder',
      (tester) async {
    _FailingServer();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 60,
            height: 40,
            child: MealOriginalImage(url: _nextUrl()),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.text(MealOriginalImage.loadErrorText), findsOneWidget);
    expect(tester.takeException(), isNull);
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
