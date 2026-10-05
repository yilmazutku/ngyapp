import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/utils/menu_utils.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';

MealModel _photo() => MealModel(
      mealId: 'm1',
      mealType: Meals.lunch,
      imageUrls: const <String>[],
      timestamp: DateTime(2026, 10, 5, 12, 30),
      isChecked: true,
    );

Widget _card({
  required VoidCallback onTap,
  void Function(Offset globalPosition)? onMenu,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 160,
          height: 160,
          child: MealImageCard(
            meal: _photo(),
            dialogImageHeight: 240,
            onTap: onTap,
            onMenu: onMenu,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('long press opens the photo menu at the pressed point',
      (tester) async {
    int taps = 0;
    final List<Offset> menus = <Offset>[];
    await tester.pumpWidget(_card(onTap: () => taps++, onMenu: menus.add));

    final Offset center = tester.getCenter(find.byType(MealImageCard));
    await tester.longPressAt(center);
    await tester.pumpAndSettle();

    expect(menus, <Offset>[center]);
    expect(taps, 0);
  }, variant: TargetPlatformVariant.all());

  testWidgets('right click opens the photo menu, left click still taps',
      (tester) async {
    int taps = 0;
    final List<Offset> menus = <Offset>[];
    await tester.pumpWidget(_card(onTap: () => taps++, onMenu: menus.add));

    final Offset center = tester.getCenter(find.byType(MealImageCard));
    await tester.tapAt(center, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(menus, <Offset>[center]);
    expect(taps, 0);

    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(menus.length, 1);
  }, variant: TargetPlatformVariant.all());

  testWidgets('card without onMenu keeps treating a long press as a tap',
      (tester) async {
    int taps = 0;
    await tester.pumpWidget(_card(onTap: () => taps++));

    await tester.longPress(find.byType(MealImageCard));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('showMenuAt returns the chosen item and null when dismissed',
      (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        pageContext = context;
        return const Scaffold();
      }),
    ));

    List<PopupMenuEntry<String>> items() => const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'chat', child: Text('Sohbette göster')),
          PopupMenuItem<String>(value: 'delete', child: Text('Fotoğrafı Sil')),
        ];

    final Future<String?> chosen = showMenuAt<String>(
      pageContext,
      globalPosition: const Offset(100, 100),
      items: items(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fotoğrafı Sil'));
    await tester.pumpAndSettle();
    expect(await chosen, 'delete');

    final Future<String?> dismissed = showMenuAt<String>(
      pageContext,
      globalPosition: const Offset(100, 100),
      items: items(),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await dismissed, isNull);
  });
}
