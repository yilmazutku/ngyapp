import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:ngy_app/widgets/photo_edit_page.dart';
import 'package:path/path.dart' as p;

const Color _red = Color(0xFFFF0000);
const Color _blue = Color(0xFF0000FF);

const String _discardMessage =
    'Fotoğraf gönderilmeyecek. Vazgeçmek istiyor musunuz?';
const String _discardConfirmText = 'Vazgeç';
const String _discardCancelText = 'Düzenlemeye dön';

/// [showPhotoEditPage]'in sonucu; sayfa kapanınca [closed] olur.
class _Closing {
  bool closed = false;
  XFile? result;
}

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

  /// Düzenleyiciyi açıp fotoğraf çözülene kadar bekler.
  Future<_Closing> pumpEditor(
    WidgetTester tester, {
    EdgeInsets systemGestureInsets = EdgeInsets.zero,
  }) async {
    final File source = File('${tempDir.path}/source.png');
    await tester.runAsync(() async {
      source.writeAsBytesSync(await _halfRedHalfBluePng(40, 20));
    });

    final _Closing closing = _Closing();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(systemGestureInsets: systemGestureInsets),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              closing.result =
                  await showPhotoEditPage(context, XFile(source.path));
              closing.closed = true;
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
    return closing;
  }

  Future<void> waitUntilClosed(WidgetTester tester, _Closing closing) async {
    for (int i = 0; i < 20 && !closing.closed; i++) {
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 100),
          ));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(closing.closed, isTrue);
  }

  Future<XFile?> openEditor(
    WidgetTester tester,
    Future<void> Function() edit, {
    EdgeInsets systemGestureInsets = EdgeInsets.zero,
  }) async {
    final _Closing closing =
        await pumpEditor(tester, systemGestureInsets: systemGestureInsets);
    await edit();
    await tester.tap(find.byTooltip('Gönder'));
    await waitUntilClosed(tester, closing);
    return closing.result;
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
    // Düzenlenen fotoğraf kendi klasörüne yazılır (bkz. TempPhotoFiles).
    expect(p.dirname(result.path), p.join(tempDir.path, 'photo_edit'));

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

  testWidgets('geri tuşu sorar; vazgeçilmezse düzenleme sürer',
      (tester) async {
    final _Closing closing = await pumpEditor(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_discardMessage), findsOneWidget);
    expect(find.byType(PhotoEditPage), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, _discardCancelText));
    await tester.pumpAndSettle();
    expect(find.text(_discardMessage), findsNothing);
    expect(find.byType(PhotoEditPage), findsOneWidget);
    expect(closing.closed, isFalse);

    await tester.tap(find.byTooltip('Gönder'));
    await waitUntilClosed(tester, closing);
    expect(closing.result!.path, endsWith('source.png'));
  });

  testWidgets('geri tuşunda vazgeçilirse null döner', (tester) async {
    final _Closing closing = await pumpEditor(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, _discardConfirmText));
    await waitUntilClosed(tester, closing);
    expect(closing.result, isNull);
    expect(find.byType(PhotoEditPage), findsNothing);
  });

  testWidgets('kapatma düğmesi de sorar; vazgeçilirse null döner',
      (tester) async {
    final _Closing closing = await pumpEditor(tester);

    await tester.tap(find.byTooltip('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text(_discardMessage), findsOneWidget);
    expect(closing.closed, isFalse);

    await tester.tap(find.widgetWithText(TextButton, _discardConfirmText));
    await waitUntilClosed(tester, closing);
    expect(closing.result, isNull);
  });

  testWidgets('fotoğraf yazılırken geri tuşu yok sayılır', (tester) async {
    final _Closing closing = await pumpEditor(tester);

    await tester.tap(find.byTooltip('Sağa döndür'));
    await tester.pump();
    await tester.tap(find.byTooltip('Gönder'));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text(_discardMessage), findsNothing);

    await waitUntilClosed(tester, closing);
    expect(closing.result!.path, isNot(endsWith('source.png')));
  });

  testWidgets('kırpma çerçevesi sistem hareketlerinin alanının dışında kalır',
      (tester) async {
    const double inset = 30;
    const EdgeInsets insets = EdgeInsets.symmetric(horizontal: inset);
    final XFile? result = await openEditor(
      tester,
      () async {
        final Rect image = tester.getRect(find.byType(RawImage));
        final Size screen = tester.getSize(find.byType(PhotoEditPage));
        expect(image.left, greaterThan(inset));
        expect(image.right, lessThan(screen.width - inset));

        // Sol kenar, alanın dışında kalan yerinden tutulup ortaya çekilir.
        await tester.dragFrom(
          image.centerLeft,
          Offset(image.width / 2, 0),
        );
        await tester.pump();
      },
      systemGestureInsets: insets,
    );

    final read = await tester.runAsync(() => _read(result!));
    expect(read!.width, 20);
    expect(read.height, 20);
    expect(read.topLeft, _blue);
    expect(read.bottomRight, _blue);
  });

  testWidgets('fotoğraf yazılırken üste sayfa açılırsa düzenleme ekranı '
      'sonuçla kaldırılır, üstteki sayfa kapanmaz', (tester) async {
    final _Closing closing = await pumpEditor(tester);
    await tester.tap(find.byTooltip('Sağa döndür'));
    await tester.pump();
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pump();

    tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute<void>(builder: (_) => const Text('haberler')),
        );
    await waitUntilClosed(tester, closing);

    expect(closing.result, isNotNull);
    expect(closing.result!.path, isNot(endsWith('source.png')));
    expect(find.text('haberler'), findsOneWidget);
    expect(find.byType(PhotoEditPage), findsNothing);
  });

  testWidgets('fotoğraf vazgeç sorusu açıkken çözülemezse soru cevaplanınca '
      'karar verilir', (tester) async {
    final File bad = File('${tempDir.path}/bad.jpg')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    final _Closing closing = _Closing();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            closing.result = await showPhotoEditPage(context, XFile(bad.path));
            closing.closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fotoğraftan vazgeç'), findsOneWidget);

    // Fotoğraf bu arada çözülemedi: soru açık kalır, sayfa kapanmaz.
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('Fotoğraftan vazgeç'), findsOneWidget);
    expect(closing.closed, isFalse);

    // Vazgeçilmedi: fotoğraf olduğu gibi döner.
    await tester.tap(find.text('Düzenlemeye dön'));
    await waitUntilClosed(tester, closing);
    expect(closing.result!.path, endsWith('bad.jpg'));
  });
  testWidgets(
      'yerleşim: sağ üstte çarpı, sol üstte "Sıfırla", sağ altta yeşil '
      'gönder düğmesi', (tester) async {
    await pumpEditor(tester);
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    final Rect close = tester.getRect(find.byTooltip('Vazgeç'));
    expect(close.right, greaterThan(screen.width - 16), reason: 'sağda');
    expect(close.top, lessThan(screen.height * 0.2), reason: 'üstte');

    final Rect reset = tester.getRect(find.text('Sıfırla'));
    expect(reset.left, lessThan(screen.width * 0.2), reason: 'solda');
    expect(reset.center.dy, closeTo(close.center.dy, 1));

    final Finder send = find.byTooltip('Gönder');
    final Rect sendRect = tester.getRect(send);
    expect(sendRect.right, greaterThan(screen.width - 32), reason: 'sağda');
    expect(sendRect.bottom, greaterThan(screen.height * 0.8), reason: 'altta');
    expect(
      find.descendant(of: send, matching: find.byIcon(Icons.send)),
      findsOneWidget,
    );
    final FloatingActionButton button = tester.widget<FloatingActionButton>(
      find.ancestor(of: send, matching: find.byType(FloatingActionButton)),
    );
    expect(button.backgroundColor, const Color(0xFF25D366), reason: 'yeşil');
  });
}
