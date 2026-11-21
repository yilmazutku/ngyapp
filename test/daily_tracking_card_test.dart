import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/providers/daily_data_provider.dart';
import 'package:ngy_app/services/health_steps_service.dart';
import 'package:ngy_app/services/ios_app_on_mac.dart';
import 'package:ngy_app/widgets/daily_tracking_card.dart';
import 'package:provider/provider.dart';

import 'health_fakes.dart';

void main() {
  const String userId = 'u1';
  final DateTime now = DateTime(2026, 11, 21, 10, 30);
  final DateTime today = DateTime(2026, 11, 21);
  final DateTime yesterday = DateTime(2026, 11, 20);
  final DateTime twoDaysAgo = DateTime(2026, 11, 19);

  const String unsaved = 'Kaydedilmemiş değişiklik var';
  const MethodChannel platformInfo = MethodChannel('ngy_app/platform_info');

  late FakeFirebaseFirestore db;
  late ScriptedDailyDataProvider provider;

  setUpAll(() => initializeDateFormatting('tr_TR'));

  setUp(() {
    db = FakeFirebaseFirestore();
    provider = ScriptedDailyDataProvider(db);
  });

  String dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Future<void> saveDoc(DateTime day, double water, int steps) => db
      .doc('users/$userId/dailyData/${dayKey(day)}')
      .set(<String, Object>{'waterIntake': water, 'steps': steps});

  Future<Map<String, dynamic>?> readDoc(DateTime day) async =>
      (await db.doc('users/$userId/dailyData/${dayKey(day)}').get()).data();

  Future<void> pumpCard(WidgetTester tester, FakeHealthSteps health) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DailyDataProvider>.value(
        value: provider,
        child: MaterialApp(
          locale: const Locale('tr', 'TR'),
          supportedLocales: const <Locale>[Locale('tr', 'TR')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: DailyTrackingCard(
                userId: userId,
                today: now,
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
        findsOneWidget,
        reason: 'Kayıtlı su');
    expect(find.descendant(of: savedField(1), matching: find.text(steps)),
        findsOneWidget,
        reason: 'Kayıtlı adım');
  }

  TextField stepsField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  String stepsInput(WidgetTester tester) =>
      stepsField(tester).controller!.text;

  double waterInput(WidgetTester tester) =>
      tester.widget<Slider>(find.byType(Slider)).value;

  Future<void> setWater(WidgetTester tester, double liters) async {
    tester.widget<Slider>(find.byType(Slider)).onChanged!(liters);
    await tester.pump();
  }

  Future<void> typeSteps(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  IconButton dayButton(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

  Future<void> tapDay(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
  }

  Future<void> closeDialog(WidgetTester tester) async {
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
  }

  Finder healthUsed(String steps) =>
      find.text('Sağlık uygulamasından alındı: $steps adım');

  Finder healthAvailable(String steps) =>
      find.text('Sağlık uygulamasında: $steps adım');

  group('HealthStepsService', () {
    tearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platformInfo, null);
      await loadIosAppOnMac();
    });

    test('adım yalnızca Android ve iOS\'ta okunur; Mac\'teki iPad '
        'uygulamasında okunmaz', () {
      for (final TargetPlatform platform in TargetPlatform.values) {
        expect(
          HealthStepsService.supportedOn(platform, iosAppOnMac: false),
          platform == TargetPlatform.android ||
              platform == TargetPlatform.iOS,
          reason: '$platform',
        );
        expect(
          HealthStepsService.supportedOn(platform, iosAppOnMac: true),
          platform == TargetPlatform.android,
          reason: '$platform',
        );
      }
    });

    test('desteklenmeyen platformlarda sağlık uygulamasına hiç dokunulmaz '
        '(iOS dahil her platform denenir)', () async {
      for (final TargetPlatform platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        final FakeHealth health = FakeHealth()..permitted = true;
        final HealthStepsService service = HealthStepsService(health: health);
        final bool supported = platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS;

        expect(service.isSupported, supported, reason: '$platform');
        expect(await service.stepsForDay(today), supported ? 1234 : null,
            reason: '$platform');
        expect(health.calls > 0, supported, reason: '$platform');
      }
    });

    test('Mac\'teki iPad uygulamasında adım okunmaz', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              platformInfo, (MethodCall call) async => true);
      await loadIosAppOnMac();
      final FakeHealth health = FakeHealth(iosLike: true);
      final HealthStepsService service = HealthStepsService(health: health);

      expect(service.isSupported, isFalse);
      expect(await service.stepsForDay(today), isNull);
      expect(health.calls, 0);
    });

    test('Android: izin zaten varsa sorulmaz; günün 00:00\'ından ertesi '
        'günün 00:00\'ına kadarki adım okunur', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final FakeHealth health = FakeHealth()
        ..permitted = true
        ..steps = 7500;
      final HealthStepsService service = HealthStepsService(health: health);

      expect(await service.stepsForDay(DateTime(2026, 11, 20, 18, 45)), 7500);
      expect(health.requests, 0);
      expect(health.intervals.single,
          (DateTime(2026, 11, 20), DateTime(2026, 11, 21)));

      await service.stepsForDay(DateTime(2026, 12, 31));
      expect(health.intervals.last,
          (DateTime(2026, 12, 31), DateTime(2027, 1, 1)));
    });

    test('Android: izin yoksa bir kez sorulur, verilince bir daha sorulmaz',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final FakeHealth health = FakeHealth();
      final HealthStepsService service = HealthStepsService(health: health);

      expect(await service.stepsForDay(today), 1234);
      expect(await service.stepsForDay(yesterday), 1234);
      expect(health.requests, 1);
    });

    test('Android: izin reddedilirse tekrar tekrar sorulmaz; kullanıcı '
        'izni ayarlardan verince uygulama kapanmadan okunur', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final FakeHealth health = FakeHealth()..grantOnRequest = false;
      final HealthStepsService service = HealthStepsService(health: health);

      expect(await service.stepsForDay(today), isNull);
      expect(await service.stepsForDay(yesterday), isNull);
      expect(health.requests, 1);

      health.permitted = true;
      expect(await service.stepsForDay(today), 1234);
      expect(health.requests, 1);
    });

    test('Android: Health Connect yoksa izin sorulmaz; sonradan kurulunca '
        'okunur', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final FakeHealth health = FakeHealth()..available = false;
      final HealthStepsService service = HealthStepsService(health: health);

      expect(await service.stepsForDay(today), isNull);
      expect(health.requests, 0);
      expect(health.intervals, isEmpty);

      health.available = true;
      expect(await service.stepsForDay(today), 1234);
      expect(health.requests, 1);
    });

    test('iOS: izin durumu bilinemediği için bir kez sorulur, sonra '
        'sorulmadan okunur', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final FakeHealth health = FakeHealth(iosLike: true)..steps = 3210;
      final HealthStepsService service = HealthStepsService(health: health);

      expect(await service.stepsForDay(today), 3210);
      expect(await service.stepsForDay(yesterday), 3210);
      expect(await service.stepsForDay(twoDaysAgo), 3210);
      expect(health.requests, 1);
    });

    test('iOS: izin reddedilince sağlık 0 döner; tekrar sorulmaz',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final FakeHealth health = FakeHealth(iosLike: true)..steps = 0;
      final HealthStepsService service = HealthStepsService(health: health);

      expect(await service.stepsForDay(today), 0);
      expect(await service.stepsForDay(yesterday), 0);
      expect(health.requests, 1);
    });

    test('aynı anda gelen istekler için izin tek kez sorulur', () async {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final FakeHealth health =
            FakeHealth(iosLike: platform == TargetPlatform.iOS)
              ..requestGate = Completer<void>();
        final HealthStepsService service = HealthStepsService(health: health);

        final Future<int?> first = service.stepsForDay(today);
        final Future<int?> second = service.stepsForDay(yesterday);
        await Future<void>.delayed(Duration.zero);
        health.requestGate!.complete();

        expect(await first, 1234, reason: '$platform');
        expect(await second, 1234, reason: '$platform');
        expect(health.requests, 1, reason: '$platform');
      }
    });

    test('sağlık uygulaması hata verirse adım boş döner, uygulama düşmez',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final FakeHealth readError = FakeHealth()
        ..permitted = true
        ..stepsError = PlatformException(code: 'STEPS_ERROR');
      expect(await HealthStepsService(health: readError).stepsForDay(today),
          isNull);

      final FakeHealth permissionError = FakeHealth()
        ..permissionError = PlatformException(code: 'NO_CLIENT');
      expect(
          await HealthStepsService(health: permissionError)
              .stepsForDay(today),
          isNull);
    });
  });

  group('Günlük Takip kartı: sağlıktaki adım kendiliğinden kaydedilir', () {
    testWidgets('kayıt yok, sağlıkta veri yok: giriş 0, Kayıtlı "—", '
        'not ve uyarı yok', (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps());

      expect(find.text('Bugün'), findsOneWidget);
      expect(stepsInput(tester), '0');
      expect(waterInput(tester), 0);
      expectSaved('—', '—');
      expect(find.textContaining('Sağlık uygulama'), findsNothing);
      expect(find.text(unsaved), findsNothing);
      expect(await readDoc(today), isNull);
    });

    testWidgets('kayıt yok, sağlıkta 5.234: yalnızca adım kaydedilir, su '
        'kaydı açılmaz', (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps({today: 5234}));

      expect(stepsInput(tester), '5234');
      expectSaved('—', '5.234');
      expect(healthUsed('5.234'), findsOneWidget);
      expect(find.text('Kullan'), findsNothing);
      expect(find.text(unsaved), findsNothing);
      expect(await readDoc(today), <String, Object>{'steps': 5234});
    });

    testWidgets('kayıtlı 4.000, sağlıkta daha çok (5.234): 5.234 kaydedilir, '
        'su olduğu gibi kalır', (WidgetTester tester) async {
      await saveDoc(today, 1.5, 4000);
      await pumpCard(tester, FakeHealthSteps({today: 5234}));

      expect(stepsInput(tester), '5234');
      expect(waterInput(tester), 1.5);
      expectSaved('1.5L', '5.234');
      expect(healthUsed('5.234'), findsOneWidget);
      expect(find.text(unsaved), findsNothing);
      expect(await readDoc(today),
          <String, Object>{'waterIntake': 1.5, 'steps': 5234});
    });

    testWidgets('kayıtlı 12.000 (elle), sağlıkta daha az (8.000): kayıt '
        'düşürülmez; su düzeltilip kaydedilince de adım 12.000 kalır',
        (WidgetTester tester) async {
      await saveDoc(yesterday, 1.0, 12000);
      await pumpCard(tester, FakeHealthSteps({yesterday: 8000}));
      await tapDay(tester, Icons.chevron_left);

      expect(stepsInput(tester), '12000');
      expectSaved('1.0L', '12.000');
      expect(healthAvailable('8.000'), findsOneWidget);
      expect(find.text('Kullan'), findsOneWidget);
      expect(find.text(unsaved), findsNothing);
      expect(await readDoc(yesterday),
          <String, Object>{'waterIntake': 1.0, 'steps': 12000});

      await setWater(tester, 2.0);
      await tapSave(tester);
      await closeDialog(tester);
      expect(await readDoc(yesterday),
          <String, Object>{'waterIntake': 2.0, 'steps': 12000});
    });

    testWidgets('"Kullan" sağlıktaki daha düşük değeri girişe koyar; '
        'Kaydet ile kaydedilir', (WidgetTester tester) async {
      await saveDoc(today, 1.0, 12000);
      await pumpCard(tester, FakeHealthSteps({today: 8000}));

      await tester.tap(find.text('Kullan'));
      await tester.pump();

      expect(stepsInput(tester), '8000');
      expect(healthUsed('8.000'), findsOneWidget);
      expect(find.text('Kullan'), findsNothing);
      expect(find.text(unsaved), findsOneWidget);
      expectSaved('1.0L', '12.000');

      await tapSave(tester);
      await closeDialog(tester);
      expectSaved('1.0L', '8.000');
      expect(await readDoc(today),
          <String, Object>{'waterIntake': 1.0, 'steps': 8000});
    });

    testWidgets('kayıtlı ile sağlıktaki eşitse hiçbir şey yazılmaz',
        (WidgetTester tester) async {
      await saveDoc(today, 2.5, 6000);
      await pumpCard(tester, FakeHealthSteps({today: 6000}));

      expect(stepsInput(tester), '6000');
      expect(healthUsed('6.000'), findsOneWidget);
      expect(find.text(unsaved), findsNothing);
      expect(provider.stepsSyncDays, isEmpty);
    });

    testWidgets('sağlıktan 0 ya da hiç değer gelmezse (izin yok) girişte '
        'kayıtlı değer kalır, not çıkmaz, bir şey yazılmaz',
        (WidgetTester tester) async {
      for (final int? value in <int?>[0, null]) {
        await saveDoc(today, 1.0, 4000);
        await pumpCard(tester, FakeHealthSteps({today: value}));

        expect(stepsInput(tester), '4000', reason: '$value');
        expect(find.textContaining('Sağlık uygulama'), findsNothing,
            reason: '$value');
        expect(find.text(unsaved), findsNothing, reason: '$value');
        await tester.pumpWidget(const SizedBox());
      }
      expect(provider.stepsSyncDays, isEmpty);
    });

    testWidgets('kullanıcı elle yazmaya başladıysa sonradan gelen sağlık '
        'değeri girişi ezmez ve kaydedilmez; "Kullan" ile alınabilir',
        (WidgetTester tester) async {
      await saveDoc(today, 1.0, 4000);
      final Completer<int?> pending = Completer<int?>();
      await pumpCard(tester, FakeHealthSteps({today: pending.future}));

      await typeSteps(tester, '1200');
      pending.complete(9000);
      await tester.pumpAndSettle();

      expect(stepsInput(tester), '1200');
      expect(healthAvailable('9.000'), findsOneWidget);
      expect(await readDoc(today),
          <String, Object>{'waterIntake': 1.0, 'steps': 4000});

      await tester.tap(find.text('Kullan'));
      await tester.pump();
      expect(stepsInput(tester), '9000');
    });

    testWidgets('sağlıktan gelen değer elle değiştirilince not "Kullan"a '
        'döner ve kaydedilmemiş uyarısı çıkar', (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps({today: 5234}));
      expect(healthUsed('5.234'), findsOneWidget);

      await typeSteps(tester, '5000');

      expect(healthUsed('5.234'), findsNothing);
      expect(healthAvailable('5.234'), findsOneWidget);
      expect(find.text('Kullan'), findsOneWidget);
      expect(find.text(unsaved), findsOneWidget);
    });

    testWidgets('bağlantı yoksa (otomatik kayıt başarısız) sağlıktaki değer '
        'girişte durur, Kaydet ile kaydedilebilir', (WidgetTester tester) async {
      await saveDoc(today, 1.0, 4000);
      provider.stepsSyncFailures = 1;
      await pumpCard(tester, FakeHealthSteps({today: 5234}));

      expect(stepsInput(tester), '5234');
      expectSaved('1.0L', '4.000');
      expect(find.text(unsaved), findsOneWidget);

      await tapSave(tester);
      await closeDialog(tester);
      expectSaved('1.0L', '5.234');
      expect(find.text(unsaved), findsNothing);
    });

    testWidgets('arka plandaki eşitleme adımı kaydedince açık kart yenilenir; '
        'kaydedilmemiş su girişi korunur', (WidgetTester tester) async {
      await saveDoc(today, 1.0, 4000);
      final FakeHealthSteps health = FakeHealthSteps({today: 4000});
      await pumpCard(tester, health);
      await setWater(tester, 2.5);

      health.steps[today] = 7000;
      await provider.saveStepsIfHigher(userId, today, 7000);
      await tester.pumpAndSettle();

      expectSaved('1.0L', '7.000');
      expect(stepsInput(tester), '7000');
      expect(healthUsed('7.000'), findsOneWidget);
      expect(waterInput(tester), 2.5);
      expect(find.text(unsaved), findsOneWidget);
    });

    testWidgets('arka plandaki eşitleme elle yazılan adımı ezmez',
        (WidgetTester tester) async {
      await saveDoc(today, 1.0, 4000);
      final FakeHealthSteps health = FakeHealthSteps({today: 4000});
      await pumpCard(tester, health);
      await typeSteps(tester, '4500');

      health.steps[today] = 7000;
      await provider.saveStepsIfHigher(userId, today, 7000);
      await tester.pumpAndSettle();

      expectSaved('1.0L', '7.000');
      expect(stepsInput(tester), '4500');
      expect(healthAvailable('7.000'), findsOneWidget);
    });

    testWidgets('kayıtlı su 5 litreyi aşıyorsa sürgü 5\'te durur, sağda '
        'gerçek değer görünür, uyarı çıkmaz', (WidgetTester tester) async {
      await saveDoc(today, 6.0, 0);
      await pumpCard(tester, FakeHealthSteps());

      expect(waterInput(tester), 5.0);
      expectSaved('6.0L', '0');
      expect(find.text(unsaved), findsNothing);
    });
  });

  group('Günlük Takip kartı: geçmiş günler', () {
    testWidgets('geçmiş güne girilen su ve adım yalnızca o günün kaydına '
        'yazılır', (WidgetTester tester) async {
      await saveDoc(today, 1.5, 4000);
      final FakeHealthSteps health =
          FakeHealthSteps({today: 5234, yesterday: 8000});
      await pumpCard(tester, health);
      expect(await readDoc(today),
          <String, Object>{'waterIntake': 1.5, 'steps': 5234});

      expect(dayButton(tester, Icons.chevron_right).onPressed, isNull);
      await tapDay(tester, Icons.chevron_left);

      expect(find.text('Dün'), findsOneWidget);
      expect(dayButton(tester, Icons.chevron_right).onPressed, isNotNull);
      expectSaved('—', '8.000');
      expect(stepsInput(tester), '8000');
      expect(health.asked, <DateTime>[today, yesterday]);

      await setWater(tester, 2.5);
      await tapSave(tester);
      expect(find.text('Günlük verileriniz başarıyla kaydedildi.'),
          findsOneWidget);
      await closeDialog(tester);

      expectSaved('2.5L', '8.000');
      expect(await readDoc(yesterday),
          <String, Object>{'steps': 8000, 'waterIntake': 2.5});
      expect(await readDoc(today),
          <String, Object>{'waterIntake': 1.5, 'steps': 5234});

      await tapDay(tester, Icons.chevron_left);
      expect(find.text('19 Kasım Perşembe'), findsOneWidget);
      await tapDay(tester, Icons.chevron_right);
      await tapDay(tester, Icons.chevron_right);
      expect(find.text('Bugün'), findsOneWidget);
      expectSaved('1.5L', '5.234');
      expect(stepsInput(tester), '5234');
    });

    testWidgets('takvimden gün seçilir; takvim bugünden sonrasını ve 1 '
        'yıldan eskisini göstermez', (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps({DateTime(2026, 11, 15): 4321}));

      await tester.tap(find.text('Bugün'));
      await tester.pumpAndSettle();
      final DatePickerDialog picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.lastDate, today);
      expect(picker.firstDate, DateTime(2025, 11, 21));

      await tester.tap(find.text('15'));
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();

      expect(find.text('15 Kasım Pazar'), findsOneWidget);
      expect(stepsInput(tester), '4321');
      expect(await readDoc(DateTime(2026, 11, 15)),
          <String, Object>{'steps': 4321});
    });

    testWidgets('1 yıl öncesine gelince önceki gün düğmesi kapanır',
        (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps());

      await tester.tap(find.text('Bugün'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(DatePickerDialog),
              matching: find.byType(TextField)),
          '21.11.2025');
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();

      expect(find.text('21 Kasım 2025 Cuma'), findsOneWidget);
      expect(dayButton(tester, Icons.chevron_left).onPressed, isNull);
      expect(dayButton(tester, Icons.chevron_right).onPressed, isNotNull);
    });

    testWidgets('hızlı gün değişiminde önceki günün geç gelen sonuçları '
        'yeni güne yazılmaz ve önceki güne de kaydedilmez',
        (WidgetTester tester) async {
      await saveDoc(yesterday, 3.0, 11111);
      final Completer<int?> lateHealth = Completer<int?>();
      provider.fetchGates[yesterday] = Completer<void>();
      await pumpCard(tester, FakeHealthSteps({
        yesterday: lateHealth.future,
        twoDaysAgo: 3000,
      }));

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      provider.fetchGates[yesterday]!.complete();
      lateHealth.complete(99999);
      await tester.pumpAndSettle();

      expect(find.text('19 Kasım Perşembe'), findsOneWidget);
      expect(stepsInput(tester), '3000');
      expect(waterInput(tester), 0);
      expectSaved('—', '3.000');
      expect(healthUsed('3.000'), findsOneWidget);
      expect(await readDoc(yesterday),
          <String, Object>{'waterIntake': 3.0, 'steps': 11111});
    });
  });

  group('Günlük Takip kartı: kaydedilmeden gün değiştirme', () {
    testWidgets('elle değişiklik varken başka güne geçilince sorulur; '
        '"Kaydetme" değişikliği atar ve geçer', (WidgetTester tester) async {
      await saveDoc(today, 1.0, 4000);
      await pumpCard(tester, FakeHealthSteps());

      await setWater(tester, 3.0);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(find.text('Kaydedilmemiş değişiklik'), findsOneWidget);
      expect(
          find.text(
              'Bugün için girdiğiniz değerler kaydedilmedi. Kaydedilsin mi?'),
          findsOneWidget);

      await tester.tap(find.text('Kaydetme'));
      await tester.pumpAndSettle();

      expect(find.text('Dün'), findsOneWidget);
      expect(await readDoc(today),
          <String, Object>{'waterIntake': 1.0, 'steps': 4000});

      await tapDay(tester, Icons.chevron_right);
      expect(waterInput(tester), 1.0);
    });

    testWidgets('"Kaydet" önce kaydeder sonra geçer (ayrıca başarı '
        'penceresi çıkmaz)', (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps());

      await typeSteps(tester, '7000');
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet').last);
      await tester.pumpAndSettle();

      expect(find.text('Dün'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(await readDoc(today),
          <String, Object>{'waterIntake': 0.0, 'steps': 7000});
    });

    testWidgets('pencerenin dışına dokunmak değişikliği atmaz, soru açık kalır',
        (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps());

      await setWater(tester, 2.0);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.text('Kaydedilmemiş değişiklik'), findsOneWidget);
    });

    testWidgets('takvimden gün seçerken de sorulur', (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps());

      await setWater(tester, 2.0);
      await tester.tap(find.text('Bugün'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();

      expect(find.text('Kaydedilmemiş değişiklik'), findsOneWidget);
      await tester.tap(find.text('Kaydetme'));
      await tester.pumpAndSettle();
      expect(find.text('15 Kasım Pazar'), findsOneWidget);
    });

    testWidgets('sağlıktan gelen değer zaten kaydedildiği için gün '
        'değişirken sorulmaz', (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps({today: 5234}));
      expect(find.text(unsaved), findsNothing);

      await tapDay(tester, Icons.chevron_left);
      expect(find.text('Dün'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      await tapDay(tester, Icons.chevron_right);
      expect(stepsInput(tester), '5234');
      expectSaved('—', '5.234');
    });

    testWidgets('değer eski hâline getirildiyse sorulmaz',
        (WidgetTester tester) async {
      await saveDoc(today, 1.0, 4000);
      await pumpCard(tester, FakeHealthSteps());

      await setWater(tester, 3.0);
      await setWater(tester, 1.0);
      await typeSteps(tester, '4500');
      await typeSteps(tester, '4000');
      expect(find.text(unsaved), findsNothing);

      await tapDay(tester, Icons.chevron_left);
      expect(find.text('Dün'), findsOneWidget);
    });

    testWidgets('geçerken kayıt başarısız olursa gün değişmez, hata gösterilir',
        (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps());

      await setWater(tester, 2.0);
      provider.saveFailures = 1;
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet').last);
      await tester.pumpAndSettle();

      expect(find.text('Veriler kaydedilirken bir hata oluştu.'),
          findsOneWidget);
      await closeDialog(tester);
      expect(find.text('Bugün'), findsOneWidget);
      expect(waterInput(tester), 2.0);
      expect(find.text(unsaved), findsOneWidget);
    });
  });

  group('Günlük Takip kartı: hatalar ve giriş kuralları', () {
    testWidgets('kayıtlı veriler yüklenemezse giriş ve Kaydet kapalı; '
        '"Tekrar dene" ile yüklenir', (WidgetTester tester) async {
      await saveDoc(today, 1.5, 4000);
      provider.fetchFailures = 1;
      await pumpCard(tester, FakeHealthSteps({today: 5234}));

      expect(find.text('Kayıtlı veriler yüklenemedi.'), findsOneWidget);
      expect(stepsField(tester).enabled, isFalse);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(
          tester
              .widget<ButtonStyleButton>(find.ancestor(
                  of: find.text('Kaydet'),
                  matching: find.byWidgetPredicate(
                      (Widget w) => w is ButtonStyleButton)))
              .onPressed,
          isNull);
      expect(provider.stepsSyncDays, isEmpty);

      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();

      expect(find.text('Kayıtlı veriler yüklenemedi.'), findsNothing);
      expectSaved('1.5L', '5.234');
      expect(stepsInput(tester), '5234');
    });

    testWidgets('kaydetme başarısız olursa hata gösterilir, Kayıtlı alanı '
        'değişmez; tekrar Kaydet ile kaydedilir', (WidgetTester tester) async {
      await saveDoc(today, 1.0, 4000);
      await pumpCard(tester, FakeHealthSteps());

      await setWater(tester, 2.0);
      provider.saveFailures = 1;
      await tapSave(tester);
      expect(find.text('Veriler kaydedilirken bir hata oluştu.'),
          findsOneWidget);
      await closeDialog(tester);
      expectSaved('1.0L', '4.000');
      expect(find.text(unsaved), findsOneWidget);

      await tapSave(tester);
      await closeDialog(tester);
      expectSaved('2.0L', '4.000');
      expect(find.text(unsaved), findsNothing);
    });

    testWidgets('adım alanına yalnızca rakam girilir, en çok 6 hane; boş '
        'bırakılırsa 0 kaydedilir', (WidgetTester tester) async {
      await saveDoc(today, 1.0, 4000);
      await pumpCard(tester, FakeHealthSteps());

      await typeSteps(tester, '12a.3-4');
      expect(stepsInput(tester), '1234');

      await typeSteps(tester, '12345678');
      expect(stepsInput(tester), '123456');

      await typeSteps(tester, '');
      await tapSave(tester);
      await closeDialog(tester);
      expect(stepsInput(tester), '0');
      expect(await readDoc(today),
          <String, Object>{'waterIntake': 1.0, 'steps': 0});
    });

    testWidgets('alana dokununca tek başına duran 0 silinir, boş bırakılınca '
        'geri gelir', (WidgetTester tester) async {
      await pumpCard(tester, FakeHealthSteps());

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(stepsInput(tester), '');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(stepsInput(tester), '0');
      expect(find.text(unsaved), findsNothing);
    });
  });

  testWidgets('dar telefon ekranında (360 px) kart taşmaz',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await saveDoc(yesterday, 4.5, 123456);
    await pumpCard(tester, FakeHealthSteps({today: 123456, yesterday: 98765}));
    expect(tester.takeException(), isNull);

    await tapDay(tester, Icons.chevron_left);
    expect(healthAvailable('98.765'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await typeSteps(tester, '5');
    expect(find.text(unsaved), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Dün'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
