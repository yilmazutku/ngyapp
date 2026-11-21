import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';

import 'admin_meal_photos_fakes.dart';
import 'meal_image_details_dialog_probe.dart';

const List<Meals> _mealCycle = [
  Meals.br,
  Meals.firstmid,
  Meals.lunch,
  Meals.secondmid,
  Meals.dinner,
  Meals.none,
];

const String _shortNote = 'Kısa not';
final String _longNote = List<String>.filled(14, 'Uzun açıklama').join(' ');

MealModel _photo(int i) => MealModel(
      mealId: 'm$i',
      mealType: _mealCycle[i % _mealCycle.length],
      imageUrls: ['https://ornek.com/foto-$i.jpg'],
      description: switch (i % 3) {
        0 => null,
        1 => _shortNote,
        _ => _longNote,
      },
      timestamp: DateTime(2026, 10, 5, 8).add(Duration(minutes: 47 * i)),
      isChecked: true,
    );

List<MealModel> _strip(int count) =>
    [for (int i = 0; i < count; i++) _photo(i)];

String _titleOf(MealModel meal) => '${meal.mealType.displayLabel} - '
    '${DateFormat('d MMMM y, HH:mm', 'tr_TR').format(meal.timestamp)}';

class _TapCounter extends StatefulWidget {
  const _TapCounter({required this.label});

  final String label;

  @override
  State<_TapCounter> createState() => _TapCounterState();
}

class _TapCounterState extends State<_TapCounter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _taps++),
      child: Text('${widget.label}: $_taps'),
    );
  }
}

Widget _footer(BuildContext dialogContext, MealModel shown) {
  final int index = int.parse(shown.mealId.substring(1));
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _TapCounter(label: shown.mealId),
      SizedBox(height: 12.0 + 40.0 * (index % 3)),
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(shown.mealId),
        child: const Text('Sohbette göster'),
      ),
    ],
  );
}

Future<Future<String?>> _open(
  WidgetTester tester,
  MealModel meal, {
  List<MealModel> gallery = const [],
  double dialogImageHeight = 420,
  bool settle = true,
}) async {
  late BuildContext pageContext;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      pageContext = context;
      return const Scaffold(body: Text('sayfa'));
    }),
  ));
  final Future<String?> result = showMealImageDetailsDialog<String>(
    pageContext,
    meal,
    dialogImageHeight: dialogImageHeight,
    heroTag: MealImageCard.heroTagFor(meal),
    gallery: gallery,
    footerBuilder: _footer,
  );
  if (settle) await tester.pumpAndSettle();
  return result;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('oklar', () {
    testWidgets('ilk fotoğrafta sol ok çıkmaz, sağ ok görünür', (tester) async {
      final List<MealModel> strip = _strip(5);
      await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      expect(probe.counterText, '1 / 5');
      probe.expectArrows(previousShown: false, nextShown: true);
    });

    testWidgets('son fotoğrafta sağ ok çıkmaz, sol ok görünür', (tester) async {
      final List<MealModel> strip = _strip(5);
      await _open(tester, strip.last, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      expect(probe.counterText, '5 / 5');
      probe.expectArrows(previousShown: true, nextShown: false);
    });

    testWidgets('arada iki ok da görünür', (tester) async {
      final List<MealModel> strip = _strip(5);
      await _open(tester, strip[2], gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      expect(probe.counterText, '3 / 5');
      probe.expectArrows(previousShown: true, nextShown: true);
    });

    testWidgets(
        'baştan sona ve geri gezerken her adımda yalnızca gidilecek yöndeki '
        'ok görünür; başlık, sayaç ve açıklama o fotoğrafındır',
        (tester) async {
      final List<MealModel> strip = _strip(7);
      await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      void expectShowing(int i) {
        final MealModel meal = strip[i];
        expect(probe.counterText, '${i + 1} / ${strip.length}');
        expect(probe.title, _titleOf(meal));
        expect(find.text('${meal.mealId}: 0'), findsOneWidget);
        final String? description = meal.description;
        if (description == null) {
          expect(find.text('Açıklama:'), findsNothing);
        } else {
          expect(find.text(description), findsOneWidget);
        }
        probe.expectArrows(
          previousShown: i > 0,
          nextShown: i < strip.length - 1,
        );
      }

      expectShowing(0);
      for (int i = 1; i < strip.length; i++) {
        await probe.showNext();
        expectShowing(i);
      }
      for (int i = strip.length - 2; i >= 0; i--) {
        await probe.showPrevious();
        expectShowing(i);
      }
    });

    testWidgets('iki fotoğrafta da yalnızca diğerine giden ok görünür',
        (tester) async {
      final List<MealModel> strip = _strip(2);
      await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      probe.expectArrows(previousShown: false, nextShown: true);
      await probe.showNext();
      expect(probe.counterText, '2 / 2');
      probe.expectArrows(previousShown: true, nextShown: false);
    });

    testWidgets('gizli okun yerine dokunmak bir şey yapmaz', (tester) async {
      final List<MealModel> strip = _strip(3);
      await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      await tester.tapAt(tester.getCenter(probe.previous));
      await tester.pumpAndSettle();
      expect(probe.counterText, '1 / 3');
      expect(probe.isOpen, isTrue);

      await probe.showNext();
      await probe.showNext();
      await tester.tapAt(tester.getCenter(probe.next));
      await tester.pumpAndSettle();
      expect(probe.counterText, '3 / 3');
      expect(probe.isOpen, isTrue);
    });

    testWidgets('tek fotoğrafta ok da sayaç da çıkmaz', (tester) async {
      await _open(tester, _photo(1));
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      expect(probe.hasNavigation, isFalse);
      expect(probe.counter, findsNothing);
      expect(find.text('m1: 0'), findsOneWidget);
    });

    testWidgets('fotoğraf listede yoksa yalnızca o fotoğraf gösterilir',
        (tester) async {
      await _open(tester, _photo(9), gallery: _strip(4));
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      expect(probe.hasNavigation, isFalse);
      expect(find.text('m9: 0'), findsOneWidget);
    });

    testWidgets(
        'çok görselli öğün tek başına açılınca görsellerin hepsi '
        'görünür, ok çıkmaz', (tester) async {
      final MealModel meal = MealModel(
        mealId: 'm0',
        mealType: Meals.lunch,
        imageUrls: const [
          'https://ornek.com/a.jpg',
          'https://ornek.com/b.jpg',
          'https://ornek.com/c.jpg',
        ],
        timestamp: DateTime(2026, 10, 5, 12),
        isChecked: true,
      );
      await _open(tester, meal, dialogImageHeight: 240);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      expect(
        find.descendant(
            of: probe.dialog, matching: find.byType(InteractiveViewer)),
        findsNWidgets(3),
      );
      expect(probe.hasNavigation, isFalse);
    });
  });

  group('yerleşim', () {
    final ScreenVariant screens = ScreenVariant();

    testWidgets(
        'oklar fotoğrafın hemen altında, sayaç ortada, kaydırmadan görünür; '
        'diyalog ekranın ortasında açılır', (tester) async {
      final List<MealModel> strip = _strip(12);
      await _open(tester, strip[4], gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);
      final String at = screens.current.name;

      probe.expectPlacement(at);
      probe.expectCentered(at);
      expect(tester.takeException(), isNull);
    }, variant: screens);

    testWidgets(
        'baştan sona gezerken başlık, fotoğraf, oklar ve sayaç yerinden '
        'oynamaz (açıklama ve alt satır fotoğraftan fotoğrafa değişse de)',
        (tester) async {
      final List<MealModel> strip = _strip(12);
      await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);
      final String at = screens.current.name;
      final Map<String, Rect> first = probe.layout();

      for (int i = 1; i < strip.length; i++) {
        await probe.showNext();
        probe.expectSameLayout(first, '$at, ${i + 1}. fotoğraf');
        probe.expectPlacement('$at, ${i + 1}. fotoğraf');
      }
      for (int i = strip.length - 2; i >= 0; i--) {
        await probe.showPrevious();
        probe.expectSameLayout(first, '$at, geri ${i + 1}. fotoğraf');
      }
      expect(tester.takeException(), isNull);
    }, variant: screens);

    testWidgets(
        'açılışta ilk karede ortalanan diyalog sonraki karelerde de aynı '
        'yerde kalır', (tester) async {
      final List<MealModel> strip = _strip(6);
      await _open(tester, strip[2], gallery: strip, settle: false);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      await tester.pump();
      final Map<String, Rect> firstFrame = probe.layout();
      await tester.pump();
      await tester.pumpAndSettle();
      probe.expectSameLayout(firstFrame, screens.current.name);
      probe.expectCentered(screens.current.name);
    }, variant: screens);

    final ScreenVariant uprightScreens = ScreenVariant(screens: [
      for (final TestScreen screen in kTestScreens)
        if (screen != kTestScreens[2]) screen,
    ]);

    testWidgets('büyük yazı boyutunda da taşma olmaz, oklar yerinde',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final List<MealModel> strip = _strip(12);
      await _open(tester, strip[9], gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);
      final String at = '${uprightScreens.current.name}, yazı 2x';

      probe.expectPlacement(at);
      final Map<String, Rect> first = probe.layout();
      await probe.showNext();
      probe.expectSameLayout(first, at);
      expect(tester.takeException(), isNull);
    }, variant: uprightScreens);

    final ScreenVariant landscape = ScreenVariant(screens: [kTestScreens[2]]);

    testWidgets(
        'yatay telefonda büyük yazıda yer çok darsa oklar kaydırınca '
        'görünür ve çalışır, taşma olmaz', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final List<MealModel> strip = _strip(12);
      await _open(tester, strip[9], gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      await tester.ensureVisible(probe.next);
      await tester.pumpAndSettle();
      probe.expectArrows(previousShown: true, nextShown: true);
      await probe.showNext();
      expect(probe.counterText, '11 / 12');
      expect(tester.takeException(), isNull);
    }, variant: landscape);
  });

  group('ekran döndürülünce', () {
    final ScreenVariant portrait = ScreenVariant(screens: [kTestScreens[0]]);

    testWidgets(
        'diyalog yeni ekranda ortalanır, oklar kaydırmadan görünür ve '
        'gezinme sürer', (tester) async {
      final List<MealModel> strip = _strip(6);
      await _open(tester, strip[1], gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);
      await probe.showNext();

      applyTestScreen(tester.view, kTestScreens[2]);
      await tester.pumpAndSettle();
      probe.expectPlacement('yatay');
      probe.expectCentered('yatay');
      expect(probe.counterText, '3 / 6');
      await probe.showNext();
      expect(probe.counterText, '4 / 6');

      applyTestScreen(tester.view, kTestScreens[0]);
      await tester.pumpAndSettle();
      probe.expectPlacement('dikey');
      probe.expectCentered('dikey');
      expect(tester.takeException(), isNull);
    }, variant: portrait);
  });

  group('fotoğraf geçişi', () {
    testWidgets('alt satır geçilen fotoğrafla yeniden kurulur, durumu taşınmaz',
        (tester) async {
      final List<MealModel> strip = _strip(3);
      await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      await tester.ensureVisible(find.text('m0: 0'));
      await tester.tap(find.text('m0: 0'));
      await tester.pump();
      expect(find.text('m0: 1'), findsOneWidget);

      await probe.showNext();
      expect(find.text('m1: 0'), findsOneWidget);
      await probe.showPrevious();
      expect(find.text('m0: 0'), findsOneWidget);
    });

    testWidgets(
        'alt satır diyaloğu o an gösterilen fotoğrafın değeriyle kapatır',
        (tester) async {
      final List<MealModel> strip = _strip(3);
      final Future<String?> result =
          await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      await probe.showNext();
      await tester.ensureVisible(find.text('Sohbette göster'));
      await tester.tap(find.text('Sohbette göster'));
      await tester.pumpAndSettle();

      expect(probe.isOpen, isFalse);
      expect(find.text('sayfa'), findsOneWidget);
      expect(await result, 'm1');
    });

    testWidgets('"Kapat" diyaloğu değersiz kapatır', (tester) async {
      final List<MealModel> strip = _strip(3);
      final Future<String?> result =
          await _open(tester, strip[1], gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      await probe.showNext();
      await tester.tap(find.text(kCloseLabel));
      await tester.pumpAndSettle();

      expect(probe.isOpen, isFalse);
      expect(await result, isNull);
    });

    testWidgets('yakınlaştırılan fotoğraftan geçince yakınlaştırma sıfırlanır',
        (tester) async {
      final List<MealModel> strip = _strip(3);
      await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      final TestPointer mouse = TestPointer(1, PointerDeviceKind.mouse);
      final Offset center = tester.getCenter(probe.image);
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
      await tester.pump();
      expect(probe.imageScale, greaterThan(1.5));

      await probe.showNext();
      expect(probe.imageScale, moreOrLessEquals(1));
      await probe.showPrevious();
      expect(probe.imageScale, moreOrLessEquals(1));
    });

    testWidgets(
        'karttan büyüme (Hero) yalnızca açılan fotoğrafta; diğerlerinde yok',
        (tester) async {
      final List<MealModel> strip = _strip(3);
      await _open(tester, strip[1], gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      expect(probe.heroCount, 1);
      await probe.showNext();
      expect(probe.heroCount, 0);
      await probe.showPrevious();
      expect(probe.heroCount, 1);
    });
  });

  group('klavye', () {
    testWidgets('sol/sağ ok tuşlarıyla geçilir; uçlarda bir şey olmaz',
        (tester) async {
      final List<MealModel> strip = _strip(4);
      await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(probe.counterText, '1 / 4');

      for (int i = 2; i <= 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(probe.counterText, '$i / 4');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(probe.counterText, '4 / 4');
      probe.expectArrows(previousShown: true, nextShown: false);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(probe.counterText, '3 / 4');
    }, variant: TargetPlatformVariant.all());

    testWidgets(
        'sağ ok düğmesine klavyeyle basılıp sona gelince düğme gizlenir; '
        'ok tuşları ve Esc çalışmaya devam eder', (tester) async {
      final List<MealModel> strip = _strip(3);
      final Future<String?> result =
          await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      Focus.of(tester.element(find.byIcon(Icons.chevron_right))).requestFocus();
      await tester.pump();
      for (int i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }
      expect(probe.counterText, '3 / 3');
      probe.expectArrows(previousShown: true, nextShown: false);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(probe.counterText, '2 / 3');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(probe.isOpen, isFalse);
      expect(await result, isNull);
    }, variant: TargetPlatformVariant.all());

    testWidgets(
        'alt satırdaki düğme odaktayken geçilince odak kaybolmaz, ok tuşları '
        've Esc çalışmaya devam eder', (tester) async {
      final List<MealModel> strip = _strip(4);
      await _open(tester, strip.first, gallery: strip);
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      Focus.of(tester.element(find.text('m0: 0'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(probe.counterText, '2 / 4');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(probe.counterText, '3 / 4');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(probe.isOpen, isFalse);
    }, variant: TargetPlatformVariant.all());

    testWidgets('tek fotoğrafta ok tuşları bir şey yapmaz, Esc kapatır',
        (tester) async {
      await _open(tester, _photo(0));
      final PhotoDialogProbe probe = PhotoDialogProbe(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(probe.isOpen, isTrue);
      expect(find.text('m0: 0'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(probe.isOpen, isFalse);
    }, variant: TargetPlatformVariant.all());
  });
}
