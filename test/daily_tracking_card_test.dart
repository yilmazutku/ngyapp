import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/providers/daily_data_provider.dart';
import 'package:ngy_app/services/health_steps_service.dart';
import 'package:ngy_app/widgets/daily_tracking_card.dart';
import 'package:provider/provider.dart';

class _FakeHealthSteps extends HealthStepsService {
  _FakeHealthSteps(this.steps);

  final Map<DateTime, FutureOr<int?>> steps;
  final List<DateTime> asked = <DateTime>[];

  @override
  Future<int?> stepsForDay(DateTime day) async {
    asked.add(day);
    return steps[day];
  }
}

void main() {
  const String userId = 'u1';
  final DateTime today = DateTime(2026, 11, 21, 10, 30);
  final DateTime todayDay = DateTime(2026, 11, 21);
  final DateTime yesterday = DateTime(2026, 11, 20);

  late FakeFirebaseFirestore db;
  late DailyDataProvider provider;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() async {
    db = FakeFirebaseFirestore();
    provider = DailyDataProvider(firestore: db);
    await db.doc('users/$userId/dailyData/2026-11-21').set({
      'waterIntake': 1.5,
      'steps': 4000,
    });
  });

  Future<void> pumpCard(WidgetTester tester, _FakeHealthSteps health) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DailyDataProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: DailyTrackingCard(
                userId: userId,
                today: today,
                onShowHistory: () {},
                healthSteps: health,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder savedField(int index) => find
      .byWidgetPredicate((Widget w) =>
          w is InputDecorator && w.decoration.labelText == 'Kayıtlı')
      .at(index);

  void expectSaved(String water, String steps) {
    expect(find.descendant(of: savedField(0), matching: find.text(water)),
        findsOneWidget);
    expect(find.descendant(of: savedField(1), matching: find.text(steps)),
        findsOneWidget);
  }

  String stepsInput(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  IconButton dayButton(WidgetTester tester, IconData icon) => tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, icon));

  const String fromHealth = 'Adım sayısı sağlık uygulamasından alındı.';

  test('adım yalnızca Android ve iOS\'ta okunur, Mac\'teki iPad uygulamasında okunmaz',
      () {
    for (final TargetPlatform platform in TargetPlatform.values) {
      expect(
        HealthStepsService.supportedOn(platform, iosAppOnMac: false),
        platform == TargetPlatform.android || platform == TargetPlatform.iOS,
        reason: '$platform',
      );
      expect(
        HealthStepsService.supportedOn(platform, iosAppOnMac: true),
        platform == TargetPlatform.android,
        reason: '$platform',
      );
    }
  });

  test('isSupported cihazın platformuna göre karar verir (iOS dahil)', () {
    try {
      for (final TargetPlatform platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          const HealthStepsService().isSupported,
          platform == TargetPlatform.android || platform == TargetPlatform.iOS,
          reason: '$platform',
        );
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'sağlık uygulamasındaki adım girişe gelir, kayıtlı değerler sağda ayrı durur',
      (WidgetTester tester) async {
    final _FakeHealthSteps health =
        _FakeHealthSteps(<DateTime, int?>{todayDay: 5234});
    await pumpCard(tester, health);

    expect(find.text('Bugün'), findsOneWidget);
    expect(stepsInput(tester), '5234');
    expectSaved('1.5L', '4.000');
    expect(find.text(fromHealth), findsOneWidget);
    expect(health.asked, <DateTime>[todayDay]);
    expect(dayButton(tester, Icons.chevron_right).onPressed, isNull);
  });

  testWidgets('sağlık uygulamasından adım gelmezse girişte kayıtlı adım durur',
      (WidgetTester tester) async {
    await pumpCard(tester, _FakeHealthSteps(<DateTime, int?>{todayDay: 0}));

    expect(stepsInput(tester), '4000');
    expectSaved('1.5L', '4.000');
    expect(find.text(fromHealth), findsNothing);
  });

  testWidgets('geçmiş güne geçilip girilen su ve adım o günün kaydına yazılır',
      (WidgetTester tester) async {
    final _FakeHealthSteps health = _FakeHealthSteps(<DateTime, int?>{
      todayDay: 5234,
      yesterday: 8000,
    });
    await pumpCard(tester, health);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(find.text('Dün'), findsOneWidget);
    expect(dayButton(tester, Icons.chevron_right).onPressed, isNotNull);
    expectSaved('—', '—');
    expect(stepsInput(tester), '8000');

    tester.widget<Slider>(find.byType(Slider)).onChanged!(2.5);
    await tester.pump();

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Günlük verileriniz başarıyla kaydedildi.'),
        findsOneWidget);
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();

    expectSaved('2.5L', '8.000');
    expect(
      (await db.doc('users/$userId/dailyData/2026-11-20').get()).data(),
      <String, Object>{'waterIntake': 2.5, 'steps': 8000},
    );
    expect(
      (await db.doc('users/$userId/dailyData/2026-11-21').get()).data(),
      <String, Object>{'waterIntake': 1.5, 'steps': 4000},
    );

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('19 Kasım Perşembe'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('Dün'), findsOneWidget);
    expectSaved('2.5L', '8.000');
  });

  testWidgets('elle girilen adım sonradan gelen sağlık değeriyle ezilmez',
      (WidgetTester tester) async {
    final Completer<int?> pending = Completer<int?>();
    await pumpCard(
      tester,
      _FakeHealthSteps(<DateTime, FutureOr<int?>>{todayDay: pending.future}),
    );

    await tester.enterText(find.byType(TextField), '1200');
    pending.complete(9000);
    await tester.pumpAndSettle();

    expect(stepsInput(tester), '1200');
    expect(find.text(fromHealth), findsNothing);
    expectSaved('1.5L', '4.000');
  });

  testWidgets('dar telefon ekranında kart taşmaz',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final _FakeHealthSteps health = _FakeHealthSteps(<DateTime, int?>{
      todayDay: 123456,
      DateTime(2026, 11, 19): 98765,
    });
    await pumpCard(tester, health);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('19 Kasım Perşembe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sağlıktan gelen adım değiştirilince kaynak notu kalkar',
      (WidgetTester tester) async {
    await pumpCard(
        tester, _FakeHealthSteps(<DateTime, int?>{todayDay: 5234}));
    expect(find.text(fromHealth), findsOneWidget);

    await tester.enterText(find.byType(TextField), '5000');
    await tester.pump();

    expect(find.text(fromHealth), findsNothing);
  });
}
