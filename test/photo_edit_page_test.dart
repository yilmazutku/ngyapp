import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:ngy_app/widgets/photo_edit_page.dart';

const Color _red = Color(0xFFFF0000);
const Color _blue = Color(0xFF0000FF);

/// Sol yarısı kırmızı, sağ yarısı mavi [width]x[height] PNG.
Future<Uint8List> _halfRedHalfBluePng(int width, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
    Paint()..color = _red,
  );
  canvas.drawRect(
    Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
    Paint()..color = _blue,
  );
  final ui.Image image = await recorder.endRecording().toImage(width, height);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<({int width, int height, Color topLeft, Color bottomRight})> _read(
  XFile file,
) async {
  final ui.Codec codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final ui.Image image = (await codec.getNextFrame()).image;
  final ByteData data =
      (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  Color pixel(int x, int y) {
    final int offset = (y * image.width + x) * 4;
    return Color.fromARGB(
      data.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  }

  final result = (
    width: image.width,
    height: image.height,
    topLeft: pixel(0, 0),
    bottomRight: pixel(image.width - 1, image.height - 1),
  );
  image.dispose();
  return result;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('photo_edit_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    tempDir.deleteSync(recursive: true);
  });

  Future<XFile?> openEditor(
    WidgetTester tester,
    Future<void> Function() edit,
  ) async {
    final File source = File('${tempDir.path}/source.png');
    await tester.runAsync(() async {
      source.writeAsBytesSync(await _halfRedHalfBluePng(40, 20));
    });

    XFile? result;
    bool closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPhotoEditPage(context, XFile(source.path));
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (int i = 0; i < 20 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 100),
          ));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);

    await edit();
    await tester.tap(find.byTooltip('Tamam'));
    for (int i = 0; i < 20 && !closed; i++) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 100),
          ));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    return result;
  }

  testWidgets('değişiklik yoksa fotoğrafın kendisi döner', (tester) async {
    final XFile? result = await openEditor(tester, () async {});
    expect(result!.path, endsWith('source.png'));
  });

  testWidgets('sağa döndürünce sol yarı üste gelir', (tester) async {
    final XFile? result = await openEditor(tester, () async {
      await tester.tap(find.byTooltip('Sağa döndür'));
      await tester.pump();
    });
    expect(result!.path, isNot(endsWith('source.png')));

    final read = await tester.runAsync(() => _read(result));
    expect(read!.width, 20);
    expect(read.height, 40);
    expect(read.topLeft, _red);
    expect(read.bottomRight, _blue);
  });

  testWidgets('sola döndürünce sağ yarı üste gelir', (tester) async {
    final XFile? result = await openEditor(tester, () async {
      await tester.tap(find.byTooltip('Sola döndür'));
      await tester.pump();
    });

    final read = await tester.runAsync(() => _read(result!));
    expect(read!.width, 20);
    expect(read.height, 40);
    expect(read.topLeft, _blue);
    expect(read.bottomRight, _red);
  });

  testWidgets('sağ kenar ortaya çekilince yalnızca sol yarı kalır',
      (tester) async {
    final XFile? result = await openEditor(tester, () async {
      final Rect image = tester.getRect(find.byType(RawImage));
      await tester.dragFrom(
        image.centerRight,
        Offset(-image.width / 2, 0),
      );
      await tester.pump();
    });

    final read = await tester.runAsync(() => _read(result!));
    expect(read!.width, 20);
    expect(read.height, 20);
    expect(read.topLeft, _red);
    expect(read.bottomRight, _red);
  });
}
