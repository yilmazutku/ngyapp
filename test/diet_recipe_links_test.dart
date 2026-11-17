import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/diet_model.dart';
import 'package:ngy_app/models/diet_recipe.dart';
import 'package:ngy_app/models/diet_section.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/utils/diet_menu_parser.dart';
import 'package:ngy_app/utils/pdf_launcher.dart';
import 'package:ngy_app/utils/recipe_links.dart';
import 'package:ngy_app/widgets/diet_plan_view.dart';

const DietRecipe kek = DietRecipe(
  url: 'https://example.com/kek.pdf',
  path: 'users/u1/dietRecipes/1/kek.pdf',
  name: 'kek.pdf',
);
const DietRecipe salata = DietRecipe(
  url: 'https://example.com/salata.pdf',
  path: 'users/u1/dietRecipes/2/salata.pdf',
  name: 'salata.pdf',
);
const DietRecipe eski = DietRecipe(
  url: 'https://example.com/eski.pdf',
  path: 'users/u1/dietRecipes/0/eski.pdf',
  name: 'eski.pdf',
);

Map<String, dynamic> twoRecipeLunch() => <String, dynamic>{
      Meals.lunch.name: <String, dynamic>{
        'time': '12:30',
        'content': <Map<String, dynamic>>[
          <String, dynamic>{
            'content': 'Kek (*tarifi ektedir)',
            DietRecipe.lineField: <Map<String, String>>[kek.toMap()],
          },
          <String, dynamic>{'content': ''},
          <String, dynamic>{
            'content': 'Salata(*tarifi ektedir)',
            DietRecipe.lineField: <Map<String, String>>[salata.toMap()],
          },
        ],
      },
    };

Future<DietDocument> storedDiet(Map<String, dynamic> data) async {
  final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();
  final DocumentReference<Map<String, dynamic>> ref =
      firestore.collection('dietLists').doc('d1');
  await ref.set(<String, dynamic>{
    'userId': 'u1',
    'displayName': 'liste',
    ...data,
  });
  return DietDocument.fromSnapshot(await ref.get());
}

List<TextSpan> linkSpans(WidgetTester tester) {
  final List<TextSpan> spans = <TextSpan>[];
  for (final RichText text
      in tester.widgetList<RichText>(find.byType(RichText))) {
    text.text.visitChildren((InlineSpan span) {
      if (span is TextSpan && span.recognizer != null) spans.add(span);
      return true;
    });
  }
  return spans;
}

void tapLink(TextSpan span) =>
    (span.recognizer! as TapGestureRecognizer).onTap!();

void main() {
  group('tarif ifadeleri', () {
    test('satırdaki her ifade ayrı parça, solundaki boşluk düzeltilir', () {
      const String line =
          'Mercimek köftesi(*tarifi ektedir) veya nohut köftesi   (*TARİFİ ektedir)';
      final List<RecipeLineSegment> segments = splitRecipeMarkers(line);

      expect(recipeMarkerCount(line), 2);
      expect(
        <String>[for (final RecipeLineSegment s in segments) s.text],
        <String>[
          'Mercimek köftesi (',
          '*tarifi ektedir',
          ') veya nohut köftesi (',
          '*TARİFİ ektedir',
          ')',
        ],
      );
      expect(
        <bool>[for (final RecipeLineSegment s in segments) s.isMarker],
        <bool>[false, true, false, true, false],
      );
      final String normalized = normalizeRecipeMarkerSpacing(line);
      expect(normalized,
          'Mercimek köftesi (*tarifi ektedir) veya nohut köftesi (*TARİFİ ektedir)');
      expect(normalizeRecipeMarkerSpacing(normalized), normalized);
    });

    test('ifadesi olmayan satır parçalanmaz', () {
      expect(splitRecipeMarkers('Yulaf ezmesi'), isEmpty);
      expect(recipeMarkerCount('Yulaf ezmesi'), 0);
      expect(normalizeRecipeMarkerSpacing('Yulaf ezmesi'), 'Yulaf ezmesi');
    });

    test('bölünen satırın tarifleri ifade sırasıyla yeni satırlara geçer', () {
      final List<Object?> recipes = <Object?>[kek.toMap(), null, salata.toMap()];

      expect(
        distributeLineRecipes(recipes, <String>[
          'Kek (*tarifi ektedir)',
          'Ayran',
          'Börek (*tarifi ektedir) ve salata (*tarifi ektedir)',
        ]),
        <List<Object?>>[
          <Object?>[kek.toMap()],
          <Object?>[],
          <Object?>[null, salata.toMap()],
        ],
      );
      expect(
        distributeLineRecipes(recipes, <String>['Kek', 'Salata']),
        <List<Object?>>[
          <Object?>[],
          <Object?>[kek.toMap(), null, salata.toMap()],
        ],
      );
    });
  });

  group('içe aktarma', () {
    final List<Map<String, dynamic>> meals = <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Öğle',
        'time': '12:30',
        'content': <Map<String, String>>[
          <String, String>{'content': 'Mercimek köftesi (*tarifi ektedir)'},
          <String, String>{'content': 'Yeşil salata'},
          <String, String>{'content': 'Kinoa salatası (*tarifi ektedir)'},
        ],
      },
      <String, dynamic>{
        'name': 'Akşam',
        'time': '19:00',
        'content': <Map<String, String>>[
          <String, String>{
            'content': 'Börek (*tarifi ektedir) veya pide (*tarifi ektedir)',
          },
        ],
      },
    ];

    test('alt alta iki ifade iki ayrı PDF yeri açar', () {
      final List<RecipeLinkSlot> slots =
          RecipeLinkSlot.findIn(meals, DietSection.weekday);

      expect(
        slots.map((RecipeLinkSlot s) => (s.mealName, s.lineIndex, s.linkIndex)),
        <(String, int, int)>[
          ('Öğle', 0, 0),
          ('Öğle', 2, 0),
          ('Akşam', 0, 0),
          ('Akşam', 0, 1),
        ],
      );
      expect(slots.map((RecipeLinkSlot s) => s.key).toSet(), hasLength(4));
      expect(
        RecipeLinkSlot.findIn(meals, DietSection.weekend)
            .map((RecipeLinkSlot s) => s.key)
            .toSet()
            .intersection(slots.map((RecipeLinkSlot s) => s.key).toSet()),
        isEmpty,
      );
    });

    test('her PDF kendi ifadesinin satırına yazılır', () {
      final List<RecipeLinkSlot> slots =
          RecipeLinkSlot.findIn(meals, DietSection.weekday);
      final Map<String, DietRecipe> uploaded = <String, DietRecipe>{
        slots[0].key: kek,
        slots[1].key: salata,
        slots[3].key: eski,
      };
      List<Map<String, String>?>? lineOf(String meal, int line,
              {DietSection section = DietSection.weekday}) =>
          RecipeLinkSlot.recipesOfLine(
            slots: slots,
            recipes: uploaded,
            section: section,
            mealName: meal,
            lineIndex: line,
          );

      expect(lineOf('Öğle', 0), <Map<String, String>?>[kek.toMap()]);
      expect(lineOf('Öğle', 1), isNull);
      expect(lineOf('Öğle', 2), <Map<String, String>?>[salata.toMap()]);
      expect(lineOf('Akşam', 0), <Map<String, String>?>[null, eski.toMap()]);
      expect(lineOf('Öğle', 0, section: DietSection.weekend), isNull);
    });
  });

  group('DietRecipe', () {
    test('adresi olmayan kayıt tarif sayılmaz', () {
      expect(DietRecipe.fromMap(<String, String>{'name': 'x.pdf'}), isNull);
      expect(DietRecipe.fromMap('kek.pdf'), isNull);
      expect(
        DietRecipe.listFrom(<Object?>[kek.toMap(), null, 3])
            .map((DietRecipe? r) => r?.url),
        <String?>[kek.url, null, null],
      );
      expect(DietRecipe.listFrom(null), isEmpty);
    });
  });

  group('DietMenu', () {
    test('satırların tarifleri boş satırlar atlanınca da hizalı kalır', () {
      final DietMenu menu = DietMenu.fromSubtitles(twoRecipeLunch());

      expect(menu.linesOf(Meals.lunch),
          <String>['Kek (*tarifi ektedir)', 'Salata(*tarifi ektedir)']);
      expect(
        menu
            .recipesOf(Meals.lunch)
            .map((List<DietRecipe?> line) => line.single?.url),
        <String>[kek.url, salata.url],
      );
      expect(menu.recipesOf(Meals.br), isEmpty);
    });
  });

  group('DietDocument', () {
    test('eski diyette bütün bağlantılar tek PDF\'i açar', () async {
      final DietDocument diet = await storedDiet(<String, dynamic>{
        'subtitles': <String, dynamic>{
          Meals.lunch.name: <String, dynamic>{
            'time': '12:30',
            'content': <Map<String, String>>[
              <String, String>{'content': 'Kek (*tarifi ektedir)'},
              <String, String>{'content': 'Salata (*tarifi ektedir)'},
            ],
          },
        },
        'recipePdfUrl': eski.url,
        'recipePdfPath': eski.path!,
        'recipePdfName': eski.name!,
      });

      expect(diet.recipesPerLine, isFalse);
      expect(diet.legacyRecipe?.url, eski.url);
      expect(diet.hasRecipe, isTrue);
      expect(diet.recipes.map((DietRecipe r) => r.url), <String>[eski.url]);
    });

    test('satır satır tarifli diyette her tarif bir kez listelenir', () async {
      final DietDocument diet = await storedDiet(<String, dynamic>{
        'subtitles': twoRecipeLunch(),
        'weekendSubtitles': <String, dynamic>{
          Meals.br.name: <String, dynamic>{
            'time': '09:00',
            'content': <Map<String, dynamic>>[
              <String, dynamic>{
                'content': 'Kek (*tarifi ektedir)',
                DietRecipe.lineField: <Map<String, String>>[kek.toMap()],
              },
            ],
          },
        },
        'recipePdfUrl': kek.url,
        'recipePdfPath': kek.path!,
        'recipePdfName': kek.name!,
        DietDocument.recipesPerLineField: true,
        'sourceFilePath': 'users/u1/dietSources/1/diyet.docx',
      });

      expect(diet.recipesPerLine, isTrue);
      expect(diet.legacyRecipe, isNull);
      expect(
          diet.recipes.map((DietRecipe r) => r.url), <String>[kek.url, salata.url]);
      expect(diet.toMap()[DietDocument.recipesPerLineField], isTrue);
    });

    test('silinirken bütün tarif PDF\'leri ve Word dosyası bulunur', () {
      final Set<String> paths =
          DietDocument.attachmentPathsOf(<String, dynamic>{
        'subtitles': twoRecipeLunch(),
        'recipePdfPath': kek.path,
        'sourceFilePath': 'users/u1/dietSources/1/diyet.docx',
      });

      expect(paths, <String>{
        kek.path!,
        salata.path!,
        'users/u1/dietSources/1/diyet.docx',
      });
      expect(DietDocument.attachmentPathsOf(null), isEmpty);
    });
  });

  group('bağlantılar', () {
    Future<List<String?>> pumpTile(
      WidgetTester tester, {
      required List<String> contents,
      required List<List<DietRecipe?>> lineRecipes,
      RecipeLinkHandler? onRecipeLink,
    }) async {
      final List<String?> opened = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DietMealTile(
                mealCategory: Meals.lunch,
                contents: contents,
                mealTime: const TimeOfDay(hour: 12, minute: 30),
                expansionKey: 'lunch',
                expanded: true,
                onExpansionChanged: (_) {},
                lineRecipes: lineRecipes,
                onRecipeLink: onRecipeLink ??
                    (DietRecipe? recipe) => recipe == null
                        ? null
                        : () => opened.add(recipe.url),
              ),
            ),
          ),
        ),
      );
      return opened;
    }

    testWidgets('aynı öğündeki iki ifade kendi PDF\'ini açar', (tester) async {
      final DietMenu menu = DietMenu.fromSubtitles(twoRecipeLunch());
      final List<String?> opened = await pumpTile(
        tester,
        contents: menu.linesOf(Meals.lunch),
        lineRecipes: menu.recipesOf(Meals.lunch),
      );

      final List<TextSpan> links = linkSpans(tester);
      expect(links, hasLength(2));
      tapLink(links[1]);
      tapLink(links[0]);
      expect(opened, <String>[salata.url, kek.url]);
    });

    testWidgets('bir satırdaki iki ifade de ayrı PDF açar', (tester) async {
      final List<String?> opened = await pumpTile(
        tester,
        contents: <String>[
          'Mercimek köftesi (*tarifi ektedir) veya nohut köftesi (*tarifi ektedir)',
        ],
        lineRecipes: <List<DietRecipe?>>[
          <DietRecipe?>[kek, salata],
        ],
      );

      final List<TextSpan> links = linkSpans(tester);
      expect(links.map((TextSpan s) => s.text),
          <String>['*tarifi ektedir', '*tarifi ektedir']);
      tapLink(links[0]);
      tapLink(links[1]);
      expect(opened, <String>[kek.url, salata.url]);
    });

    testWidgets('PDF\'i olmayan ifade düz metin kalır', (tester) async {
      await pumpTile(
        tester,
        contents: <String>['Kek (*tarifi ektedir)', 'Salata (*tarifi ektedir)'],
        lineRecipes: <List<DietRecipe?>>[
          <DietRecipe?>[kek],
          <DietRecipe?>[],
        ],
      );

      final List<TextSpan> links = linkSpans(tester);
      expect(links, hasLength(1));
      expect(find.text('Salata (*tarifi ektedir)'), findsOneWidget);
    });

    testWidgets('eski diyetin tek PDF\'i satırında PDF olmayan ifadeleri açar',
        (tester) async {
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (BuildContext c) {
        context = c;
        return const SizedBox();
      }));

      expect(openRecipeLinks(context)(null), isNull);
      expect(openRecipeLinks(context)(kek), isNotNull);
      expect(openRecipeLinks(context, fallback: eski)(null), isNotNull);
    });

    testWidgets('önizlemede bütün ifadeler bağlantıdır', (tester) async {
      int infoTaps = 0;
      await pumpTile(
        tester,
        contents: <String>['Kek (*tarifi ektedir)', 'Salata (*tarifi ektedir)'],
        lineRecipes: const <List<DietRecipe?>>[],
        onRecipeLink: (_) => () => infoTaps++,
      );

      final List<TextSpan> links = linkSpans(tester);
      expect(links, hasLength(2));
      tapLink(links[1]);
      expect(infoTaps, 1);
    });

    testWidgets('Planım görünümünde öğün açılınca bağlantılar çalışır',
        (tester) async {
      final List<String?> opened = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DietPlanView(
                weekday: DietMenu.fromSubtitles(twoRecipeLunch()),
                onRecipeLink: (DietRecipe? recipe) => recipe == null
                    ? null
                    : () => opened.add(recipe.url),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(Meals.lunch.displayLabel));
      await tester.pumpAndSettle();

      final List<TextSpan> links = linkSpans(tester);
      expect(links, hasLength(2));
      tapLink(links[0]);
      tapLink(links[1]);
      expect(opened, <String>[kek.url, salata.url]);
    });
  });
}
