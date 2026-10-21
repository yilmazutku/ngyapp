import 'dart:async';

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
}
