import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';

MealModel _photo(int i, Meals type) => MealModel(
      mealId: 'm$i',
      mealType: type,
      imageUrls: <String>['https://x/$i.jpg'],
      timestamp: DateTime(2026, 10, 5, 8 + i, 30),
      isChecked: true,
    );

final List<MealModel> _strip = <MealModel>[
  _photo(0, Meals.br),
  _photo(1, Meals.lunch),
  _photo(2, Meals.dinner),
];

class _TapCounter extends StatefulWidget {
  final String label;

  const _TapCounter({required this.label});

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

Future<Future<String?>> _open(
  WidgetTester tester,
  MealModel meal, {
  List<MealModel> gallery = const <MealModel>[],
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
    dialogImageHeight: 240,
    heroTag: MealImageCard.heroTagFor(meal),
    gallery: gallery,
    footerBuilder: (dialogContext, shown) => Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TapCounter(label: shown.mealId),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(shown.mealId),
          child: const Text('Sohbette göster'),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return result;
}

Finder get _previous => find.byTooltip('Önceki fotoğraf');
Finder get _next => find.byTooltip('Sonraki fotoğraf');

bool _enabled(WidgetTester tester, Finder arrow) =>
    tester
        .widget<IconButton>(
            find.ancestor(of: arrow, matching: find.byType(IconButton)).first)
        .onPressed !=
    null;

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('oklar şeritteki önceki ve sonraki fotoğrafa geçer',
      (tester) async {
    await _open(tester, _strip[1], gallery: _strip);

    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.textContaining('Öğle'), findsOneWidget);
    expect(find.text('m1: 0'), findsOneWidget);

    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.textContaining('Akşam'), findsOneWidget);
    expect(find.text('m2: 0'), findsOneWidget);
    expect(_enabled(tester, _next), isFalse);
    expect(_enabled(tester, _previous), isTrue);

    await tester.tap(_previous);
    await tester.pumpAndSettle();
    await tester.tap(_previous);
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.textContaining('Sabah'), findsOneWidget);
    expect(find.text('m0: 0'), findsOneWidget);
    expect(_enabled(tester, _previous), isFalse);
    expect(_enabled(tester, _next), isTrue);
  });

  testWidgets('alt satır geçilen fotoğrafla yeniden kurulur, durumu taşınmaz',
      (tester) async {
    await _open(tester, _strip[0], gallery: _strip);

    await tester.tap(find.text('m0: 0'));
    await tester.pump();
    expect(find.text('m0: 1'), findsOneWidget);

    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(find.text('m1: 0'), findsOneWidget);
  });

  testWidgets('alt satır diyaloğu o an gösterilen fotoğrafın değeriyle kapatır',
      (tester) async {
    final Future<String?> result =
        await _open(tester, _strip[0], gallery: _strip);

    await tester.tap(_next);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sohbette göster'));
    await tester.pumpAndSettle();

    expect(find.text('sayfa'), findsOneWidget);
    expect(await result, 'm1');
  });

  testWidgets('klavyenin sol/sağ okuyla da geçilir', (tester) async {
    await _open(tester, _strip[0], gallery: _strip);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(_next);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  }, variant: TargetPlatformVariant.all());

  testWidgets('tek fotoğrafta ok ve sayaç çıkmaz', (tester) async {
    await _open(tester, _strip[1]);

    expect(_previous, findsNothing);
    expect(_next, findsNothing);
    expect(find.textContaining(' / '), findsNothing);
    expect(find.text('m1: 0'), findsOneWidget);
  });

  testWidgets('fotoğraf listede yoksa yalnızca o fotoğraf gösterilir',
      (tester) async {
    await _open(tester, _photo(9, Meals.none), gallery: _strip);

    expect(_next, findsNothing);
    expect(find.text('m9: 0'), findsOneWidget);
  });
}
