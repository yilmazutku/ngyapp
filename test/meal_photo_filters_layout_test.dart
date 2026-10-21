import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/pages/admin_meal_photos_page.dart';
import 'package:ngy_app/widgets/filter_chip_group.dart';
import 'package:ngy_app/widgets/search_field.dart';

/// Sayfadaki öğün filtresinin seçenekleri.
const List<Meals> _mealOptions = [
  Meals.br,
  Meals.firstmid,
  Meals.lunch,
  Meals.dinner,
  Meals.none,
];

const double _sidePadding = 16;

/// Öğün Fotoğrafları'nın filtre alanı: sayfadaki gibi gövdedeki sütunun
/// içinde, aynı kenar boşluğu ve aynı filtre gruplarıyla.
class _FiltersHost extends StatefulWidget {
  const _FiltersHost();

  @override
  State<_FiltersHost> createState() => _FiltersHostState();
}

class _FiltersHostState extends State<_FiltersHost> {
  final TextEditingController _controller = TextEditingController();
  Meals? meal;
  bool unreactedOnly = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_sidePadding, 12, _sidePadding, 12),
          child: MealPhotoFiltersLayout(
            searchController: _controller,
            searchLabel: 'Danışan ara (ad soyad / e-posta)',
            onSearchChanged: (_) {},
            filters: [
              FilterChipGroup<Meals>(
                key: const ValueKey('meal'),
                title: 'Öğün',
                titleIcon: Icons.restaurant_menu,
                selectedValue: meal,
                options: {
                  for (final Meals option in _mealOptions)
                    option: option.displayLabel,
                },
                onSelected: (value) => setState(() => meal = value),
              ),
              FilterChipGroup<bool>(
                key: const ValueKey('reaction'),
                title: 'İfade',
                titleIcon: Icons.add_reaction_outlined,
                selectedValue: unreactedOnly ? true : null,
                options: const {true: 'İfade bırakılmayanlar'},
                onSelected: (value) =>
                    setState(() => unreactedOnly = value == true),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const Expanded(child: SizedBox()),
      ],
    );
  }
}

Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: _FiltersHost())),
  );
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  final Finder chip = find.widgetWithText(FilterChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pump();
}

void main() {
  for (final double width in const [360.0, 393.0, 430.0]) {
    testWidgets('filters stack vertically without overflow at $width dp',
        (tester) async {
      await _pumpAt(tester, width);
      expect(tester.takeException(), isNull);

      final Rect search = tester.getRect(find.byType(SearchField));
      final Rect meals = tester.getRect(find.byKey(const ValueKey('meal')));
      final Rect reactions =
          tester.getRect(find.byKey(const ValueKey('reaction')));
      final double available = width - 2 * _sidePadding;

      // Tam genişlikte arama, altında öğün, onun altında ifade filtresi.
      expect(search.width, moreOrLessEquals(available));
      expect(meals.width, moreOrLessEquals(available));
      expect(reactions.width, moreOrLessEquals(available));
      expect(meals.top, greaterThanOrEqualTo(search.bottom));
      expect(reactions.top, greaterThanOrEqualTo(meals.bottom));

      final _FiltersHostState host =
          tester.state<_FiltersHostState>(find.byType(_FiltersHost));

      // Sığmayan seçenekler yatay kaydırılarak seçilir.
      for (final Meals option in _mealOptions.reversed) {
        await _tapChip(tester, option.displayLabel);
        expect(host.meal, option);
      }

      await _tapChip(tester, 'İfade bırakılmayanlar');
      expect(host.unreactedOnly, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wide screens keep search on the left, filters on the right',
      (tester) async {
    await _pumpAt(tester, 1280);
    expect(tester.takeException(), isNull);

    final Rect search = tester.getRect(find.byType(SearchField));
    final Rect meals = tester.getRect(find.byKey(const ValueKey('meal')));
    final Rect reactions =
        tester.getRect(find.byKey(const ValueKey('reaction')));

    expect(search.width, moreOrLessEquals(SearchField.defaultMaxWidth));
    expect(meals.left, greaterThan(search.right));
    expect(reactions.left, moreOrLessEquals(meals.left));
    expect(reactions.top, greaterThanOrEqualTo(meals.bottom));
  });

  testWidgets('dar ve geniş düzen arasında geçince arama kutusu odağını korur',
      (tester) async {
    await _pumpAt(tester, 400);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'ayşe');
    await tester.pump();
    final FocusNode? focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);

    tester.view.physicalSize = const Size(900, 800);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(FocusManager.instance.primaryFocus, same(focused));
    expect(find.text('ayşe'), findsOneWidget);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(focused));
  });
}
