import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/widgets/chat/message_actions_sheet.dart';
import 'package:ngy_app/widgets/reaction_picker.dart';

Future<Future<MessageActionChoice?>> _openSheet(
  WidgetTester tester, {
  required bool canReact,
  required List<MessageAction> actions,
  String? currentEmoji,
}) async {
  late BuildContext pageContext;
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: Builder(builder: (context) {
      pageContext = context;
      return const Scaffold();
    }),
  ));
  final Future<MessageActionChoice?> choice = showMessageActionsSheet(
    pageContext,
    canReact: canReact,
    actions: actions,
    currentEmoji: currentEmoji,
  );
  await tester.pumpAndSettle();
  return choice;
}

void main() {
  group('Mobildeki mesaj menüsü widget\'ı (A, 2.6, 7.1)', () {
    test('seçenek adları senaryodaki gibi', () {
      expect(MessageAction.reply.label, 'Yanıtla');
      expect(MessageAction.copy.label, 'Mesajı Kopyala');
      expect(MessageAction.showInMealPhotos.label,
          "Öğün Fotoğrafları'nda göster");
      expect(MessageAction.deletePhoto.label, 'Fotoğrafı Sil');
    });

    testWidgets('ifade bırakılabilen mesajda üstte hızlı ifadeler, altında seçenekler var',
        (tester) async {
      await _openSheet(
        tester,
        canReact: true,
        actions: const <MessageAction>[MessageAction.reply, MessageAction.copy],
      );

      expect(find.byType(QuickReactionRow), findsOneWidget);
      for (final String emoji in kChatQuickReactionEmojis) {
        expect(find.text(emoji), findsOneWidget, reason: emoji);
      }
      expect(find.text('Yanıtla'), findsOneWidget);
      expect(find.text('Mesajı Kopyala'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(QuickReactionRow)).dy,
        lessThan(tester.getTopLeft(find.text('Yanıtla')).dy),
      );
    });

    testWidgets('canReact=false verilince ifade satırı çıkmaz, yalnızca verilen seçenekler listelenir (kendi mesajı / silinmiş not kararını ChatPage verir, burada denenmez)',
        (tester) async {
      await _openSheet(
        tester,
        canReact: false,
        actions: const <MessageAction>[MessageAction.reply],
      );

      expect(find.byType(QuickReactionRow), findsNothing);
      for (final String emoji in kChatQuickReactionEmojis) {
        expect(find.text(emoji), findsNothing, reason: emoji);
      }
      expect(find.text('Yanıtla'), findsOneWidget);
      expect(find.text('Mesajı Kopyala'), findsNothing);
      expect(find.text('Fotoğrafı Sil'), findsNothing);
    });

    testWidgets('"Fotoğrafı Sil" kırmızı (tema hata rengi) yazılır',
        (tester) async {
      await _openSheet(
        tester,
        canReact: false,
        actions: const <MessageAction>[
          MessageAction.reply,
          MessageAction.deletePhoto,
        ],
      );

      final Color error =
          Theme.of(tester.element(find.text('Fotoğrafı Sil'))).colorScheme.error;
      expect(tester.widget<Text>(find.text('Fotoğrafı Sil')).style?.color,
          error);
      expect(tester.widget<Text>(find.text('Yanıtla')).style?.color,
          isNot(error));
    });

    testWidgets('seçilen ifade ya da seçenek geri döner', (tester) async {
      final Future<MessageActionChoice?> emojiChoice = await _openSheet(
        tester,
        canReact: true,
        actions: const <MessageAction>[MessageAction.reply],
      );
      final String emoji = kChatQuickReactionEmojis.first;
      await tester.tap(find.text(emoji));
      await tester.pumpAndSettle();
      final MessageActionChoice? picked = await emojiChoice;
      expect(picked?.emoji, emoji);
      expect(picked?.action, isNull);

      final Future<MessageActionChoice?> actionChoice = await _openSheet(
        tester,
        canReact: false,
        actions: const <MessageAction>[
          MessageAction.reply,
          MessageAction.showInMealPhotos,
        ],
      );
      await tester.tap(find.text("Öğün Fotoğrafları'nda göster"));
      await tester.pumpAndSettle();
      expect((await actionChoice)?.action, MessageAction.showInMealPhotos);
    });
  });
}
