import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/services/ios_app_on_mac.dart';
import 'package:ngy_app/widgets/chat/message_actions_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel platformInfo = MethodChannel('ngy_app/platform_info');

  Future<void> setIosAppOnMac(bool value) async {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        platformInfo, (MethodCall call) async => value);
    await loadIosAppOnMac();
    messenger.setMockMethodCallHandler(platformInfo, null);
  }

  const Set<TargetPlatform> desktopPlatforms = {
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  };

  test('sağ tık menüsü masaüstünde ve Mac\'teki iOS uygulamasında açılır', () {
    for (final TargetPlatform platform in TargetPlatform.values) {
      for (final bool onMac in <bool>[false, true]) {
        final bool expected = desktopPlatforms.contains(platform) ||
            (platform == TargetPlatform.iOS && onMac);
        expect(
          messageMenuOnRightClick(platform, iosAppOnMac: onMac),
          expected,
          reason: '$platform, Mac: $onMac',
        );
      }
    }
  });

  group('baloncuk hareketleri', () {
    const Key bubbleKey = Key('bubble');

    tearDown(() async {
      await setIosAppOnMac(false);
    });

    Future<List<String>> pressBubble(
      WidgetTester tester, {
      required bool onMac,
    }) async {
      await setIosAppOnMac(onMac);
      final List<String> opened = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: GestureDetector(
              onLongPress: () => opened.add('sheet'),
              onSecondaryTapDown: messageMenuOnRightClick(
                defaultTargetPlatform,
                iosAppOnMac: isIosAppOnMac,
              )
                  ? (_) => opened.add('menu')
                  : null,
              child: const ColoredBox(
                key: bubbleKey,
                color: Colors.blue,
                child: SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      ));

      final Offset center = tester.getCenter(find.byKey(bubbleKey));
      await tester.tapAt(
        center,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      final TestGesture press = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await press.up();
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('Mac\'teki iOS uygulamasında sağ tık menüyü açar, basılı '
        'tutmak da çalışır', (tester) async {
      expect(await pressBubble(tester, onMac: true), <String>['menu', 'sheet']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('iPhone, iPad ve Android\'de sağ tık menü açmaz, basılı '
        'tutmak açar',
        (tester) async {
      expect(await pressBubble(tester, onMac: false), <String>['sheet']);
    }, variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.iOS,
      TargetPlatform.android,
    }));
  });

  group('showMessageMenuAt', () {
    const Offset clickAt = Offset(200, 300);

    Future<BuildContext> pumpPage(WidgetTester tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          pageContext = context;
          return const Scaffold();
        }),
      ));
      return pageContext;
    }

    testWidgets('"Yanıtla", "İfade Bırak" ve diğer işlemler sırayla gelir; '
        'seçilen işlem döner', (tester) async {
      final BuildContext context = await pumpPage(tester);
      final Future<MessageActionChoice?> chosen = showMessageMenuAt(
        context,
        globalPosition: clickAt,
        canReact: true,
        actions: const <MessageAction>[
          MessageAction.reply,
          MessageAction.copy,
        ],
      );
      await tester.pumpAndSettle();

      final double replyY = tester.getCenter(find.text('Yanıtla')).dy;
      final double reactY = tester.getCenter(find.text(kMessageReactLabel)).dy;
      final double copyY = tester.getCenter(find.text('Mesajı Kopyala')).dy;
      expect(replyY, lessThan(reactY));
      expect(reactY, lessThan(copyY));

      await tester.tap(find.text('Mesajı Kopyala'));
      await tester.pumpAndSettle();
      final MessageActionChoice? choice = await chosen;
      expect(choice?.action, MessageAction.copy);
      expect(choice?.emoji, isNull);
    });

    testWidgets('"İfade Bırak" ifade seçicisini açar; seçilen ifade döner',
        (tester) async {
      final BuildContext context = await pumpPage(tester);
      final Future<MessageActionChoice?> chosen = showMessageMenuAt(
        context,
        globalPosition: clickAt,
        canReact: true,
        actions: const <MessageAction>[MessageAction.reply],
        currentEmoji: '👍',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(kMessageReactLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('❤️'));
      await tester.pumpAndSettle();

      final MessageActionChoice? choice = await chosen;
      expect(choice?.emoji, '❤️');
      expect(choice?.action, isNull);
    });

    testWidgets('kendi mesajında "İfade Bırak" yok; kapatılırsa null döner',
        (tester) async {
      final BuildContext context = await pumpPage(tester);
      final Future<MessageActionChoice?> chosen = showMessageMenuAt(
        context,
        globalPosition: clickAt,
        canReact: false,
        actions: const <MessageAction>[MessageAction.reply],
      );
      await tester.pumpAndSettle();

      expect(find.text('Yanıtla'), findsOneWidget);
      expect(find.text(kMessageReactLabel), findsNothing);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(await chosen, isNull);
    });
  });
}
