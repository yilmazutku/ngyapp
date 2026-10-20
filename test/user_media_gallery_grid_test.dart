import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/pages/user_media_gallery_page.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';
import 'package:ngy_app/widgets/meal_thumbnail_image.dart';

MealModel _photo(int i) => MealModel(
      mealId: 'm$i',
      mealType: Meals.values[i % Meals.values.length],
      imageUrls: const <String>[],
      timestamp: DateTime(2026, 10, 5, 8 + i % 12, 30),
      isChecked: true,
    );

Future<void> _pumpGallery(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ScrollController controller = ScrollController();
  addTearDown(controller.dispose);
  final List<MealModel> photos = List<MealModel>.generate(12, _photo);

  // Sayfadaki gibi: üstte sayaç satırı, altında kalan yeri dolduran ızgara.
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Fotoğraflarım')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('12 fotoğraf'),
          ),
          Expanded(
            child: UserMediaGalleryGrid(
              controller: controller,
              itemCount: photos.length,
              itemBuilder: (context, i, dialogImageHeight) => MealImageCard(
                meal: photos[i],
                dialogImageHeight: dialogImageHeight,
                reactions: i.isEven ? const {'u1': '👍'} : const {},
              ),
            ),
          ),
        ],
      ),
    ),
  ));
}

/// İlk satırdaki kart sayısı (sütun sayısı).
int _columnsOf(WidgetTester tester) {
  final List<Rect> cards =
      tester.widgetList(find.byType(MealImageCard)).map((widget) {
    return tester.getRect(find.byWidget(widget));
  }).toList();
  final double firstTop = cards.first.top;
  return cards.where((rect) => (rect.top - firstTop).abs() < 1).length;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  for (final double width in const [360.0, 393.0, 430.0]) {
    testWidgets('gallery grid fits phones at $width dp', (tester) async {
      await _pumpGallery(tester, width);
      expect(tester.takeException(), isNull);

      expect(_columnsOf(tester), 3);

      final Rect thumb = tester.getRect(find.byType(MealThumbnailImage).first);
      expect(thumb.width, greaterThan(80));
      expect(thumb.height, greaterThan(0.8 * thumb.width));
    });
  }

  testWidgets('gallery grid keeps 5 columns on wide screens', (tester) async {
    await _pumpGallery(tester, 1280);
    expect(tester.takeException(), isNull);
    expect(_columnsOf(tester), 5);
  });

  testWidgets('card footer never overflows on narrow cards', (tester) async {
    for (final double width in const [30.0, 48.0, 63.0, 80.0, 120.0]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 120,
              child: MealImageCard(
                meal: _photo(0),
                dialogImageHeight: 240,
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });
}
