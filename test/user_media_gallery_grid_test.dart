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

Future<void> _pumpCells(
  WidgetTester tester, {
  required int count,
  required bool complete,
  double width = 360,
  Widget? topEdge,
  VoidCallback? onNearOldest,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ScrollController controller = ScrollController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: UserMediaGalleryGrid(
        controller: controller,
        itemCount: count,
        complete: complete,
        topEdge: topEdge,
        onNearOldest: onNearOldest,
        itemBuilder: (context, i, dialogImageHeight) =>
            Center(child: Text('p$i')),
      ),
    ),
  ));
}

/// Hücrelerin yazıları, yukarıdan aşağı ve soldan sağa okunduğu sırayla.
List<String> _readingOrder(WidgetTester tester) {
  final List<({String label, Rect rect})> cells = [
    for (final Element element in find.byType(Text).evaluate())
      if ((element.widget as Text).data!.startsWith('p'))
        (
          label: (element.widget as Text).data!,
          rect: tester.getRect(find.byWidget(element.widget)),
        ),
  ]..sort((a, b) {
      final int byRow = a.rect.center.dy.compareTo(b.rect.center.dy);
      return byRow != 0
          ? byRow
          : a.rect.center.dx.compareTo(b.rect.center.dx);
    });
  return [for (final cell in cells) cell.label];
}

double _centerX(WidgetTester tester, String label) =>
    tester.getCenter(find.text(label)).dx;

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

  test('cells map to photos oldest to newest in reading order', () {
    List<int?> cells(int count, {required bool complete}) => [
          for (int cell = 0;
              cell < UserMediaGalleryGrid.cellCountFor(count, 3);
              cell++)
            UserMediaGalleryGrid.itemIndexAt(
              cell,
              itemCount: count,
              columns: 3,
              complete: complete,
            ),
        ];

    expect(UserMediaGalleryGrid.cellCountFor(0, 3), 0);
    expect(UserMediaGalleryGrid.cellCountFor(6, 3), 6);
    expect(UserMediaGalleryGrid.cellCountFor(7, 3), 9);

    expect(cells(7, complete: false), [2, 1, 0, 5, 4, 3, null, null, 6]);
    expect(cells(7, complete: true), [0, null, null, 3, 2, 1, 6, 5, 4]);
    expect(cells(6, complete: false), [2, 1, 0, 5, 4, 3]);
    expect(cells(6, complete: true), [2, 1, 0, 5, 4, 3]);
    expect(cells(1, complete: false), [null, null, 0]);
    expect(cells(1, complete: true), [0, null, null]);
  });

  testWidgets('a partly loaded gallery ends with the newest photo at the '
      'bottom right; the missing cells are at the top left', (tester) async {
    await _pumpCells(tester, count: 7, complete: false);
    expect(tester.takeException(), isNull);

    expect(_readingOrder(tester), ['p6', 'p5', 'p4', 'p3', 'p2', 'p1', 'p0']);
    expect(_centerX(tester, 'p6'), _centerX(tester, 'p0'));
    expect(_centerX(tester, 'p0'), greaterThan(_centerX(tester, 'p1')));
    expect(
      tester.getCenter(find.text('p0')).dy,
      greaterThan(tester.getCenter(find.text('p6')).dy),
    );
  });

  testWidgets('a whole gallery starts at the top left like before',
      (tester) async {
    await _pumpCells(tester, count: 7, complete: true);
    expect(tester.takeException(), isNull);

    expect(_readingOrder(tester), ['p6', 'p5', 'p4', 'p3', 'p2', 'p1', 'p0']);
    expect(_centerX(tester, 'p6'), _centerX(tester, 'p0'));
    expect(_centerX(tester, 'p6'), lessThan(_centerX(tester, 'p5')));
  });

  testWidgets('a few photos sit at the top, not at the bottom',
      (tester) async {
    await _pumpCells(tester, count: 2, complete: true);

    expect(tester.getRect(find.text('p1')).top, lessThan(150));
    expect(_centerX(tester, 'p1'), lessThan(_centerX(tester, 'p0')));
  });

  testWidgets('a long gallery opens at the newest photo and asks for older '
      'photos only near the top', (tester) async {
    int requests = 0;
    await _pumpCells(
      tester,
      count: 60,
      complete: false,
      topEdge: const Text('kenar'),
      onNearOldest: () => requests++,
    );
    await tester.pump();

    expect(find.text('p0'), findsOneWidget);
    expect(find.text('p59'), findsNothing);
    expect(find.text('kenar').hitTestable(), findsNothing);
    expect(requests, 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 5000));
    await tester.pump();

    expect(find.text('p59'), findsOneWidget);
    expect(find.text('p0'), findsNothing);
    expect(find.text('kenar').hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.text('kenar')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('p59')).top),
    );
    expect(requests, greaterThan(0));
  });

  testWidgets('a gallery shorter than the screen asks for older photos',
      (tester) async {
    int requests = 0;
    await _pumpCells(
      tester,
      count: 5,
      complete: false,
      onNearOldest: () => requests++,
    );
    await tester.pump();

    expect(requests, greaterThan(0));
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
