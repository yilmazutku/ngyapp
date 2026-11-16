import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/pages/admin_meal_photos_page.dart';
import 'package:ngy_app/widgets/count_badge.dart';
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
            activeFilterCount: (meal != null ? 1 : 0) + (unreactedOnly ? 1 : 0),
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

/// [density] verilmezse temanınki (telefonda standart) kullanılır;
/// masaüstü temaları sıkı ([VisualDensity.compact]) yoğunluktadır.
Future<void> _pumpAt(
  WidgetTester tester,
  double width, {
  VisualDensity? density,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(visualDensity: density),
      home: const Scaffold(body: _FiltersHost()),
    ),
  );
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  final Finder chip = find.widgetWithText(FilterChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pump();
}

Future<void> _toggleFiltersPanel(WidgetTester tester) async {
  await tester.tap(find.text(MealPhotoFiltersLayout.filtersLabel));
  await tester.pumpAndSettle();
}

void main() {
  const ValueKey<String> mealKey = ValueKey('meal');
  const ValueKey<String> reactionKey = ValueKey('reaction');

  for (final double width in const [360.0, 393.0, 430.0]) {
    testWidgets(
        'dar ekranda filtreler kapalı başlar, "Filtreler" kutusuna dokununca '
        'aramanın altında taşmadan açılır ($width dp)', (tester) async {
      await _pumpAt(tester, width);
      expect(tester.takeException(), isNull);

      final double available = width - 2 * _sidePadding;
      final Rect search = tester.getRect(find.byType(SearchField));
      final Rect panel = tester.getRect(find.byType(ExpansionTile));

      // Tam genişlikte arama, hemen altında aynı genişlikte ve boyda
      // "Filtreler" kutusu; filtreler ve seçili filtre rozeti görünmez.
      expect(search.width, moreOrLessEquals(available));
      expect(panel.width, moreOrLessEquals(available));
      expect(panel.height, moreOrLessEquals(search.height));
      expect(panel.top, greaterThanOrEqualTo(search.bottom));
      expect(find.byKey(mealKey), findsNothing);
      expect(find.byKey(reactionKey), findsNothing);
      expect(find.byType(CountBadge), findsNothing);

      await _toggleFiltersPanel(tester);
      expect(tester.takeException(), isNull);

      // Kutunun içinde, "Filtreler" satırının altında öğün, onun altında
      // ifade filtresi.
      final Rect openPanel = tester.getRect(find.byType(ExpansionTile));
      final Rect header = tester.getRect(
        find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.byType(ListTile),
        ),
      );
      final Rect meals = tester.getRect(find.byKey(mealKey));
      final Rect reactions = tester.getRect(find.byKey(reactionKey));
      expect(openPanel.top, moreOrLessEquals(panel.top));
      expect(meals.top, greaterThanOrEqualTo(header.bottom));
      expect(reactions.top, greaterThanOrEqualTo(meals.bottom));
      for (final Rect group in [meals, reactions]) {
        expect(group.left, greaterThan(openPanel.left));
        expect(group.right, lessThan(openPanel.right));
        expect(group.bottom, lessThanOrEqualTo(openPanel.bottom));
      }

      final _FiltersHostState host =
          tester.state<_FiltersHostState>(find.byType(_FiltersHost));

      // Sığmayan seçenekler yatay kaydırılarak seçilir; seçim sonrası
      // yeniden çizimde kutu açık kalır.
      for (final Meals option in _mealOptions.reversed) {
        await _tapChip(tester, option.displayLabel);
        expect(host.meal, option);
      }

      await _tapChip(tester, 'İfade bırakılmayanlar');
      expect(host.unreactedOnly, isTrue);
      expect(tester.takeException(), isNull);

      // Kutu kapanınca filtreler gizlenir; seçili iki filtre rozette kalır.
      await _toggleFiltersPanel(tester);
      expect(find.byKey(mealKey), findsNothing);
      expect(find.byKey(reactionKey), findsNothing);
      expect(
        find.descendant(
          of: find.byType(CountBadge),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(host.meal, Meals.br);
      expect(host.unreactedOnly, isTrue);
    });
  }

  for (final VisualDensity density in const [
    VisualDensity.standard,
    VisualDensity.compact,
  ]) {
    testWidgets(
        'geniş ekranda arama solda, "Filtreler" kutusu sağında aynı boyda; '
        'filtreler kapalı başlar, tıklayınca kaydırmadan seçilir '
        '(yoğunluk: $density)', (tester) async {
      const double width = 1280;
      await _pumpAt(tester, width, density: density);
      expect(tester.takeException(), isNull);

      final Rect search = tester.getRect(find.byType(SearchField));
      final Rect panel = tester.getRect(find.byType(ExpansionTile));

      // Tek satır: arama solda, kutu sağında aynı hizada ve aynı boyda;
      // filtreler görünmez.
      expect(search.width, moreOrLessEquals(SearchField.defaultMaxWidth));
      expect(panel.left, greaterThan(search.right));
      expect(panel.right, moreOrLessEquals(width - _sidePadding));
      expect(panel.top, moreOrLessEquals(search.top));
      expect(panel.height, moreOrLessEquals(search.height));
      expect(find.byKey(mealKey), findsNothing);
      expect(find.byKey(reactionKey), findsNothing);

      await _toggleFiltersPanel(tester);
      expect(tester.takeException(), isNull);

      // Kutu aşağı açılır, arama yerinde kalır; seçenekler kutuya sığar.
      expect(tester.getRect(find.byType(SearchField)), search);
      final Rect openPanel = tester.getRect(find.byType(ExpansionTile));
      final Rect header = tester.getRect(
        find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.byType(ListTile),
        ),
      );
      final Rect meals = tester.getRect(find.byKey(mealKey));
      final Rect reactions = tester.getRect(find.byKey(reactionKey));
      expect(meals.top, greaterThanOrEqualTo(header.bottom));
      expect(reactions.top, greaterThanOrEqualTo(meals.bottom));
      final Rect lastChip = tester.getRect(
        find.widgetWithText(FilterChip, _mealOptions.last.displayLabel),
      );
      expect(lastChip.right, lessThan(openPanel.right));

      final _FiltersHostState host =
          tester.state<_FiltersHostState>(find.byType(_FiltersHost));
      await tester.tap(
        find.widgetWithText(FilterChip, _mealOptions.last.displayLabel),
      );
      await tester.pump();
      expect(host.meal, _mealOptions.last);
      expect(
        find.descendant(
          of: find.byType(CountBadge),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('dar ve geniş düzen arasında geçince "Filtreler" kutusu açık kalır',
      (tester) async {
    await _pumpAt(tester, 400);
    await _toggleFiltersPanel(tester);
    expect(find.byKey(mealKey), findsOneWidget);

    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(mealKey), findsOneWidget);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(mealKey), findsOneWidget);
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
