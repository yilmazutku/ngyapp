import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/widgets/chat/message_actions_sheet.dart';

void main() {
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
