import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/widgets/reaction_badge.dart';

void main() {
  const Map<String, String> reactions = {'admin-1': '👍'};

  Future<void> pumpBadge(
    WidgetTester tester, {
    VoidCallback? onTap,
    required VoidCallback onPhotoTap,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            // Albümde rozet fotoğrafın üstünde durur: fotoğrafa dokunmak tam
            // ekranı açar.
            child: GestureDetector(
              onTap: onPhotoTap,
              child: SizedBox(
                width: 120,
                height: 120,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ReactionBadge(reactions: reactions, onTap: onTap),
                ),
              ),
            ),
          ),
        ),
      ));

  testWidgets('dokunma verilince rozete dokunmak onu çağırır, fotoğrafı açmaz',
      (tester) async {
    int badgeTaps = 0;
    int photoTaps = 0;
    await pumpBadge(
      tester,
      onTap: () => badgeTaps++,
      onPhotoTap: () => photoTaps++,
    );

    await tester.tap(find.text('👍'));

    expect(badgeTaps, 1);
    expect(photoTaps, 0);
  });

  testWidgets('dokunma verilmezse rozete dokunmak fotoğrafı açar (eskisi gibi)',
      (tester) async {
    int photoTaps = 0;
    await pumpBadge(tester, onPhotoTap: () => photoTaps++);

    await tester.tap(find.text('👍'));

    expect(photoTaps, 1);
  });

  group('ifade silme sorusu', () {
    Future<Future<bool>> ask(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const Scaffold();
        }),
      ));
      final Future<bool> answer = confirmRemoveReaction(context, '👍');
      await tester.pumpAndSettle();
      expect(find.text('İfade silinsin mi?'), findsOneWidget);
      expect(find.text('Bıraktığınız 👍 ifadesi kaldırılacak.'), findsOneWidget);
      return answer;
    }

    testWidgets('"Evet" silinsin der', (tester) async {
      final Future<bool> answer = await ask(tester);
      await tester.tap(find.text('Evet'));
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
    });

    testWidgets('"Hayır" silinmesin der', (tester) async {
      final Future<bool> answer = await ask(tester);
      await tester.tap(find.text('Hayır'));
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
    });
  });
}
