import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/utils/temp_photo_files.dart';
import 'package:path/path.dart' as p;

const MethodChannel _pathProvider =
    MethodChannel('plugins.flutter.io/path_provider');

const List<TargetPlatform> _mobile = [
  TargetPlatform.android,
  TargetPlatform.iOS,
];

const List<TargetPlatform> _desktop = [
  TargetPlatform.windows,
  TargetPlatform.macOS,
  TargetPlatform.linux,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;

  /// getTemporaryDirectory (Android'de cache, iOS'ta Library/Caches).
  late Directory temporary;

  /// getApplicationCacheDirectory.
  late Directory cache;

  /// Directory.systemTemp (iOS'ta seçicinin yazdığı tmp).
  late Directory systemTemp;

  /// Uygulamanın geçici klasörlerinin dışı (ör. kullanıcının kendi dosyası).
  late Directory outside;

  /// path_provider'ın getApplicationCacheDirectory için verdiği yol.
  late String cachePath;

  setUp(() {
    base = Directory.systemTemp.createTempSync('temp_photo_files_test');
    temporary = Directory(p.join(base.path, 'temporary'))..createSync();
    cache = Directory(p.join(base.path, 'cache'))..createSync();
    systemTemp = Directory(p.join(base.path, 'tmp'))..createSync();
    outside = Directory(p.join(base.path, 'outside'))..createSync();
    cachePath = cache.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (call) async {
      switch (call.method) {
        case 'getTemporaryDirectory':
          return temporary.path;
        case 'getApplicationCacheDirectory':
          return cachePath;
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    base.deleteSync(recursive: true);
  });

  File fileIn(Directory directory, String name) =>
      File(p.join(directory.path, name))
        ..createSync(recursive: true)
        ..writeAsStringSync('photo');

  /// [body]'yi Directory.systemTemp [systemTemp] iken çalıştırır.
  Future<T> withSystemTemp<T>(Future<T> Function() body) =>
      IOOverrides.runZoned(body, getSystemTempDirectory: () => systemTemp);

  Future<void> delete(String path) =>
      withSystemTemp(() => TempPhotoFiles.delete(path));

  for (final TargetPlatform platform in _mobile) {
    group('$platform', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);

      test('geçici klasörlerdeki fotoğraf silinir, klasörün kendisi kalır',
          () async {
        for (final Directory root in [temporary, cache, systemTemp]) {
          final File photo = fileIn(root, 'photo.jpg');
          await delete(photo.path);
          expect(photo.existsSync(), isFalse, reason: root.path);
          expect(root.existsSync(), isTrue, reason: root.path);
        }
      });

      test('geçici klasörlerin dışındaki dosya silinmez', () async {
        final File photo = fileIn(outside, 'photo.jpg');
        await delete(photo.path);
        expect(photo.existsSync(), isTrue);

        // `..` ile dışarı çıkan yol da dışarıda sayılır.
        await delete(p.join(temporary.path, '..', 'outside', 'photo.jpg'));
        expect(photo.existsSync(), isTrue);
      });

      test('geçici klasördeki bağ dışarıyı gösteriyorsa silinmez', () async {
        final File photo = fileIn(outside, 'photo.jpg');
        final Link link = Link(p.join(cache.path, 'link.jpg'))
          ..createSync(photo.path);
        await delete(link.path);
        expect(photo.existsSync(), isTrue);
      });

      test('klasörün yolu bağ üzerinden verilse de içindeki fotoğraf silinir',
          () async {
        // iOS'ta /var, /private/var'a bağdır; yollar iki biçimde de gelebilir.
        cachePath = (Link(p.join(base.path, 'cache_link'))
              ..createSync(cache.path))
            .path;
        final File photo = fileIn(cache, 'photo.jpg');
        await delete(photo.path);
        expect(photo.existsSync(), isFalse);
      });

      test('boşalan alt klasör de silinir (galeri kopyası cache/<uuid>/)',
          () async {
        final File photo = fileIn(cache, p.join('uuid-1', 'photo.jpg'));
        await delete(photo.path);
        expect(photo.existsSync(), isFalse);
        expect(photo.parent.existsSync(), isFalse);
        expect(cache.existsSync(), isTrue);
      });

      test('alt klasör boş değilse kalır', () async {
        final File photo = fileIn(cache, p.join('uuid-1', 'photo.jpg'));
        final File other = fileIn(cache, p.join('uuid-1', 'other.jpg'));
        await delete(photo.path);
        expect(photo.existsSync(), isFalse);
        expect(other.existsSync(), isTrue);
      });

      test('düzenleme klasörü boşalsa da kalır', () async {
        final Directory photoEdit =
            await withSystemTemp(TempPhotoFiles.photoEditDirectory);
        expect(photoEdit.path, p.join(temporary.path, 'photo_edit'));
        expect(photoEdit.existsSync(), isTrue);

        final File photo = fileIn(photoEdit, 'photo_edit_1.jpg');
        await delete(photo.path);
        expect(photo.existsSync(), isFalse);
        expect(photoEdit.existsSync(), isTrue);
      });

      test('olmayan dosya hata vermez', () async {
        await delete(p.join(cache.path, 'missing.jpg'));
        await delete('');
      });

      test('düzenleme klasöründe yalnızca eski ve sırada olmayanlar silinir',
          () async {
        final Directory photoEdit =
            Directory(p.join(temporary.path, 'photo_edit'));
        final DateTime old = DateTime.now().subtract(const Duration(days: 3));
        final File stale = fileIn(photoEdit, 'stale.jpg')
          ..setLastModifiedSync(old);
        final File queued = fileIn(photoEdit, 'queued.jpg')
          ..setLastModifiedSync(old);
        final File fresh = fileIn(photoEdit, 'fresh.jpg');

        await withSystemTemp(
          () => TempPhotoFiles.deleteStalePhotoEdits(keep: [queued.path]),
        );
        expect(stale.existsSync(), isFalse);
        expect(queued.existsSync(), isTrue);
        expect(fresh.existsSync(), isTrue);
      });
    });
  }

  for (final TargetPlatform platform in _desktop) {
    test('$platform: hiçbir dosya silinmez', () async {
      debugDefaultTargetPlatformOverride = platform;
      final File photo = fileIn(temporary, 'photo.jpg');
      final File stale = fileIn(temporary, p.join('photo_edit', 'stale.jpg'))
        ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(days: 3)));

      await delete(photo.path);
      await withSystemTemp(
        () => TempPhotoFiles.deleteStalePhotoEdits(keep: const []),
      );
      expect(photo.existsSync(), isTrue);
      expect(stale.existsSync(), isTrue);
    });
  }
}
