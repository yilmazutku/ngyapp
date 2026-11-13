import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/utils/image_thumbnail.dart';
import 'package:ngy_app/utils/storage_upload.dart';

import 'fake_image_compress.dart';

int _crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

Future<Uint8List> _pngClaiming(int width, int height, int totalBytes) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  Canvas(recorder).drawPaint(Paint()..color = const Color(0xFF336699));
  final ui.Image image = await recorder.endRecording().toImage(1, 1);
  final ByteData encoded =
      (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();

  final Uint8List png = Uint8List(totalBytes)
    ..setAll(0, encoded.buffer.asUint8List());
  final ByteData header = ByteData.sublistView(png);
  header.setUint32(16, width);
  header.setUint32(20, height);
  header.setUint32(29, _crc32(png.sublist(12, 29)));
  return png;
}

Future<List<Color>> _pixelsOf(Uint8List encoded) async {
  final ui.Codec codec = await ui.instantiateImageCodec(encoded);
  final ui.Image image = (await codec.getNextFrame()).image;
  final ByteData data =
      (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final List<Color> pixels = [
    for (int offset = 0; offset < data.lengthInBytes; offset += 4)
      Color.fromARGB(
        data.getUint8(offset + 3),
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      ),
  ];
  image.dispose();
  codec.dispose();
  return pixels;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final FlutterImageCompressPlatform original =
      FlutterImageCompressPlatform.instance;
  final UploadImageProfile defaultProfile = UploadImageProfile.current;
  tearDown(() {
    FlutterImageCompressPlatform.instance = original;
    UploadImageProfile.current = defaultProfile;
  });

  test('varsayılan ölçü küçük olandır', () {
    expect(defaultProfile, UploadImageProfile.compact);
    expect(UploadImageProfile.compact.minSide, 1200);
    expect(UploadImageProfile.compact.quality, 80);
    expect(UploadImageProfile.standard.minSide, 1600);
    expect(UploadImageProfile.standard.quality, 85);
  });

  test('örnekleme katsayısı kısa kenarı hedefin altına düşürmez', () {
    int sample(int width, int height, int target) =>
        decodeSampleSizeFor(ImagePixelSize(width, height), target);

    expect(decodeSampleSizeFor(null, 1600), 1);
    expect(sample(4000, 3000, 1600), 1);
    expect(sample(3000, 4000, 1600), 1);
    expect(sample(4270, 3200, 1600), 2);
    expect(sample(8160, 6120, 1600), 2);
    expect(sample(12000, 9000, 1600), 4);
    expect(sample(16320, 12240, 1600), 4);
    expect(sample(1200, 900, 1600), 1);
    expect(sample(2133, 1600, 480), 2);
    expect(sample(4000, 3000, 480), 4);
    expect(sample(640, 480, 480), 1);
    expect(sample(4000, 3000, 0), 1);
  });

  for (final ({
    UploadImageProfile profile,
    int hugeSample,
    int twelveMpSample
  }) scenario in [
    (profile: UploadImageProfile.standard, hugeSample: 2, twelveMpSample: 1),
    (profile: UploadImageProfile.compact, hugeSample: 4, twelveMpSample: 2),
  ]) {
    final String label = 'kısa kenar ${scenario.profile.minSide}';

    test('$label: fotoğraf geçerli ölçü ve kaliteyle küçültülür', () async {
      UploadImageProfile.current = scenario.profile;
      final FakeImageCompress fake =
          FakeImageCompress(Uint8List.fromList([1, 2, 3]));
      FlutterImageCompressPlatform.instance = fake;

      final PreparedUploadImage prepared = await prepareImageForUpload(
        bytes: await _pngClaiming(8160, 6120, kUploadImageSkipBytes + 1),
        fileName: 'tabak.png',
      );

      expect(fake.inSampleSize, scenario.hugeSample);
      expect(fake.minWidth, scenario.profile.minSide);
      expect(fake.minHeight, scenario.profile.minSide);
      expect(fake.quality, scenario.profile.quality);
      expect(prepared.compressed, isTrue);
      expect(prepared.bytes, [1, 2, 3]);
      expect(prepared.fileName, 'tabak.jpg');
      expect(prepared.contentType, 'image/jpeg');
    });

    test('$label: 12 MP fotoğrafın örnekleme katsayısı', () async {
      UploadImageProfile.current = scenario.profile;
      final FakeImageCompress fake = FakeImageCompress(Uint8List.fromList([1]));
      FlutterImageCompressPlatform.instance = fake;

      await prepareImageForUpload(
        bytes: await _pngClaiming(4000, 3000, kUploadImageSkipBytes + 1),
        fileName: 'tabak.png',
      );

      expect(fake.inSampleSize, scenario.twelveMpSample);
    });
  }

  test('küçük görsel üretilirken de örnekleme katsayısı verilir', () async {
    final FakeImageCompress fake = FakeImageCompress(Uint8List.fromList([9]));
    FlutterImageCompressPlatform.instance = fake;

    final ThumbnailData? thumb =
        await generateThumbnail(await _pngClaiming(4000, 3000, 4096));

    expect(fake.inSampleSize, 4);
    expect(fake.minWidth, kThumbnailShortSide);
    expect(thumb!.bytes, [9]);
  });

  test('ölçüsü okunamayan görsel tam boyutunda çözdürülür', () async {
    final FakeImageCompress fake = FakeImageCompress(Uint8List.fromList([1]));
    FlutterImageCompressPlatform.instance = fake;

    await prepareImageForUpload(
      bytes: Uint8List(kUploadImageSkipBytes + 1),
      fileName: 'tabak.heic',
    );

    expect(fake.inSampleSize, 1);
  });

  group('encodeJpeg', () {
    const List<Color> colors = [
      Color(0xFFFF0000),
      Color(0xFF00FF00),
      Color(0xFF0000FF),
      Color(0xFF102030),
      Color(0xFFFFFFFF),
      Color(0xFF000000),
    ];

    Future<ui.Image> image3x2() {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      for (int i = 0; i < colors.length; i++) {
        canvas.drawRect(
          Rect.fromLTWH((i % 3).toDouble(), (i ~/ 3).toDouble(), 1, 1),
          Paint()..color = colors[i],
        );
      }
      return recorder.endRecording().toImage(3, 2);
    }

    test('pikselleri sıkıştırıcıya kayıpsız ve aynı ölçüde verir', () async {
      final FakeImageCompress fake = FakeImageCompress(Uint8List.fromList([7, 7]));
      FlutterImageCompressPlatform.instance = fake;
      final ui.Image image = await image3x2();

      final Uint8List? jpeg = await encodeJpeg(image, quality: 92);
      image.dispose();

      expect(jpeg, [7, 7]);
      expect(fake.minWidth, 3);
      expect(fake.minHeight, 2);
      expect(fake.quality, 92);
      expect(fake.inSampleSize, 1);

      final ImagePixelSize? size = await readImagePixelSize(fake.input!);
      expect(size!.width, 3);
      expect(size.height, 2);
      expect(await _pixelsOf(fake.input!), colors);
    });

    test('sıkıştırıcı yoksa null döner', () async {
      final ui.Image image = await image3x2();
      expect(await encodeJpeg(image, quality: 92), isNull);
      image.dispose();
    });

    test('sıkıştırıcı boş sonuç verirse null döner', () async {
      FlutterImageCompressPlatform.instance = FakeImageCompress(Uint8List(0));
      final ui.Image image = await image3x2();
      expect(await encodeJpeg(image, quality: 92), isNull);
      image.dispose();
    });
  });
}
