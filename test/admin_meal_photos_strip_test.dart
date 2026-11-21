import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/pages/admin_meal_photos_page.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';

import 'admin_meal_photos_fakes.dart';

const String _photoClientId = 'danisan-foto';
const String _emptyClientId = 'danisan-bos';
const int _photoCount = 12;
const List<Meals> _mealCycle = [
  Meals.br,
  Meals.firstmid,
  Meals.lunch,
  Meals.secondmid,
  Meals.dinner,
  Meals.thirdmid,
];

String _thumbUrl(int index) => 'https://ornek.com/kucuk-$index.png';

List<MealModel> _meals(DateTime day) => [
      for (int i = 0; i < _photoCount; i++)
        MealModel(
          mealId: 'ogun-$i',
          mealType: _mealCycle[i % _mealCycle.length],
          imageUrls: ['https://ornek.com/foto-$i.jpg'],
          thumbUrls: [_thumbUrl(i)],
          timestamp: day.add(Duration(hours: 8, minutes: 20 * i)),
          isChecked: false,
        ),
    ];

Rect _thumbRect(Finder scrollbar) {
  final List<Rect> drawn = [];
  expect(
    scrollbar,
    paints
      ..everything((Symbol method, List<dynamic> arguments) {
        if (method == #drawRRect) {
          drawn.add((arguments.first as RRect).outerRect);
        } else if (method == #drawRect) {
          drawn.add(arguments.first as Rect);
        }
        return true;
      }),
  );
  expect(drawn, isNotEmpty);
  return drawn.last;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  final ScreenVariant screens = ScreenVariant(ignoreTestFontOverflow: true);

  testWidgets('şeridin kaydırma çubuğu kartların altında, şeridin en altında',
      (tester) async {
    await rememberSolidImages(tester, [
      for (int i = 0; i < _photoCount; i++) _thumbUrl(i),
    ]);

    await tester.pumpWidget(
      adminMealPhotosApp(
        customers: [
          testCustomer(_photoClientId, 'Buket', 'Tekkeli'),
          testCustomer(_emptyClientId, 'Aslı', 'Aydaş'),
        ],
        mealsByUser: {_photoClientId: _meals(testToday())},
        chatManager: FakeChatManager(),
        home: const AdminMealPhotosPage(),
      ),
    );
    await settleAdminMealPhotos(tester);

    final Finder cards = find.byType(MealImageCard);
    expect(cards, findsWidgets);
    final Finder strip = find
        .ancestor(
          of: cards.first,
          matching: find.byWidgetPredicate((widget) => widget is RawScrollbar),
        )
        .first;
    await tester.ensureVisible(strip);
    await tester.pump(const Duration(milliseconds: 300));

    final Rect stripRect = tester.getRect(strip);
    final double cardsBottom = tester
        .widgetList<MealImageCard>(cards)
        .map((card) => tester.getRect(find.byWidget(card)).bottom)
        .reduce(math.max);
    final Rect thumb = _thumbRect(strip).shift(stripRect.topLeft);

    expect(thumb.width, greaterThan(thumb.height),
        reason: 'yatay şeridin çubuğu bulunmalı');
    expect(thumb.top, greaterThanOrEqualTo(cardsBottom),
        reason: 'çubuk kartların (öğün/saat satırının) altında olmalı');
    expect(thumb.bottom, lessThanOrEqualTo(stripRect.bottom + 0.01),
        reason: 'çubuk şeridin içinde kalmalı');
    expect(stripRect.bottom - thumb.bottom, lessThan(8),
        reason: 'çubuk şeridin en altına yakın olmalı');
    expect(thumb.left - stripRect.left, lessThan(8),
        reason: 'çubuk ekranın yan boşluğu kadar içeri itilmemeli');

    await disposeAdminMealPhotos(tester);
  }, variant: screens);
}
