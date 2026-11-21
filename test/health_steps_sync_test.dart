import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/providers/daily_data_provider.dart';
import 'package:ngy_app/services/health_steps_sync.dart';
import 'package:ngy_app/widgets/health_steps_auto_sync.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'health_fakes.dart';

class _CountingSync extends HealthStepsSync {
  _CountingSync() : super(health: FakeHealthSteps());

  final List<String> calls = <String>[];

  @override
  Future<void> syncIfDue(String userId, DailyDataProvider provider) async {
    calls.add(userId);
  }
}

void main() {
  const String userId = 'u1';
  const String nilay = '0MvvbZsjbmNPW4QYShRNSOOtkE43';
  const String lastSyncKey = '${HealthStepsSync.lastSyncKeyPrefix}$userId';

  DateTime day(int d) => DateTime(2026, 11, d);

  late FakeFirebaseFirestore db;
  late ScriptedDailyDataProvider provider;
  late DateTime clock;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = FakeFirebaseFirestore();
    provider = ScriptedDailyDataProvider(db);
    clock = DateTime(2026, 11, 21, 10);
  });

  String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> saveDoc(DateTime d, Map<String, Object> data) =>
      db.doc('users/$userId/dailyData/${dayKey(d)}').set(data);

  Future<Map<String, dynamic>?> readDoc(DateTime d) async =>
      (await db.doc('users/$userId/dailyData/${dayKey(d)}').get()).data();

  Future<int?> lastSync() async =>
      (await SharedPreferences.getInstance()).getInt(lastSyncKey);

  HealthStepsSync syncWith(FakeHealthSteps health) =>
      HealthStepsSync(health: health, clock: () => clock);

  group('DailyDataProvider', () {
    test('saveStepsIfHigher yeni güne yalnızca adımı yazar ve haber verir',
        () async {
      int notified = 0;
      provider.addListener(() => notified++);

      expect(await provider.saveStepsIfHigher(userId, day(21), 5000), 5000);
      expect(await readDoc(day(21)), <String, Object>{'steps': 5000});
      expect(notified, 1);
    });

    test('saveStepsIfHigher kayıtlı adımı düşürmez, suya dokunmaz', () async {
      int notified = 0;
      provider.addListener(() => notified++);
      await saveDoc(day(21), <String, Object>{'waterIntake': 2.0, 'steps': 12000});

      expect(await provider.saveStepsIfHigher(userId, day(21), 8000), 12000);
      expect(await provider.saveStepsIfHigher(userId, day(21), 12000), 12000);
      expect(notified, 0);

      expect(await provider.saveStepsIfHigher(userId, day(21), 13000), 13000);
      expect(await readDoc(day(21)),
          <String, Object>{'waterIntake': 2.0, 'steps': 13000});
      expect(notified, 1);
    });

    test('her alanın kaydı olup olmadığı ayrı ayrı okunur', () async {
      await saveDoc(day(20), <String, Object>{'steps': 4000});
      await saveDoc(day(19), <String, Object>{'waterIntake': 1.5});

      final DailyData none =
          await provider.fetchDailyDataForDate(userId, date: day(21));
      final DailyData stepsOnly =
          await provider.fetchDailyDataForDate(userId, date: day(20));
      final DailyData waterOnly =
          await provider.fetchDailyDataForDate(userId, date: day(19));

      expect((none.hasWater, none.hasSteps), (false, false));
      expect((stepsOnly.hasWater, stepsOnly.hasSteps), (false, true));
      expect((waterOnly.hasWater, waterOnly.hasSteps), (true, false));
    });
  });

  group('HealthStepsSync', () {
    test('ilk eşitlemede son 7 gün okunur; sağlıktaki fazlaysa yalnızca adım '
        'yazılır, elle girilen yüksek değer ve su korunur', () async {
      await saveDoc(day(20), <String, Object>{'waterIntake': 2.0, 'steps': 3000});
      await saveDoc(day(19), <String, Object>{'waterIntake': 1.0, 'steps': 15000});
      final FakeHealthSteps health = FakeHealthSteps({
        day(21): 5000,
        day(20): 9000,
        day(19): 9000,
        day(18): 4000,
        day(17): 0,
        day(16): null,
        day(15): 2000,
      });
      int notified = 0;
      provider.addListener(() => notified++);

      await syncWith(health).syncIfDue(userId, provider);

      expect(health.asked, <DateTime>[
        for (int d = 15; d <= 21; d++) day(d),
      ]);
      expect(await readDoc(day(21)), <String, Object>{'steps': 5000});
      expect(await readDoc(day(20)),
          <String, Object>{'waterIntake': 2.0, 'steps': 9000});
      expect(await readDoc(day(19)),
          <String, Object>{'waterIntake': 1.0, 'steps': 15000});
      expect(await readDoc(day(18)), <String, Object>{'steps': 4000});
      expect(await readDoc(day(17)), isNull);
      expect(await readDoc(day(16)), isNull);
      expect(await readDoc(day(15)), <String, Object>{'steps': 2000});
      expect(await lastSync(), clock.millisecondsSinceEpoch);
      expect(notified, 4);
    });

    test('son kayıttan 5 dakika geçmeden tekrar okunmaz; 5 dakika geçince '
        'dün ve bugün tazelenir', () async {
      final FakeHealthSteps health = FakeHealthSteps({day(21): 5000});
      final HealthStepsSync sync = syncWith(health);
      await sync.syncIfDue(userId, provider);
      health.asked.clear();

      clock = clock.add(const Duration(minutes: 4, seconds: 59));
      health.steps[day(21)] = 6000;
      await sync.syncIfDue(userId, provider);
      expect(health.asked, isEmpty);
      expect(await readDoc(day(21)), <String, Object>{'steps': 5000});

      clock = clock.add(const Duration(seconds: 1));
      await sync.syncIfDue(userId, provider);
      expect(health.asked, <DateTime>[day(20), day(21)]);
      expect(await readDoc(day(21)), <String, Object>{'steps': 6000});
      expect(await lastSync(), clock.millisecondsSinceEpoch);
    });

    test('uygulama günlerce açılmadıysa son eşitlemenin gününden bugüne '
        'kadar okunur, en fazla 7 gün', () async {
      final FakeHealthSteps health = FakeHealthSteps({day(21): 100});

      SharedPreferences.setMockInitialValues(<String, Object>{
        lastSyncKey: DateTime(2026, 11, 18, 22).millisecondsSinceEpoch,
      });
      await syncWith(health).syncIfDue(userId, provider);
      expect(health.asked, <DateTime>[day(18), day(19), day(20), day(21)]);

      health.asked.clear();
      SharedPreferences.setMockInitialValues(<String, Object>{
        lastSyncKey: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      });
      await syncWith(health).syncIfDue(userId, provider);
      expect(health.asked, <DateTime>[for (int d = 15; d <= 21; d++) day(d)]);
    });

    test('sağlık uygulamasına erişim yoksa hiçbir şey yazılmaz, zaman '
        'kaydedilmez; izin verilince 5 dakika beklemeden eşitlenir', () async {
      final FakeHealthSteps health = FakeHealthSteps();
      final HealthStepsSync sync = syncWith(health);

      await sync.syncIfDue(userId, provider);
      expect(provider.stepsSyncDays, isEmpty);
      expect(await lastSync(), isNull);

      health.steps[day(21)] = 4200;
      clock = clock.add(const Duration(minutes: 1));
      await sync.syncIfDue(userId, provider);
      expect(await readDoc(day(21)), <String, Object>{'steps': 4200});
      expect(await lastSync(), clock.millisecondsSinceEpoch);
    });

    test('iOS\'ta izin reddedilince adımlar 0 gelir: veritabanına hiç '
        'dokunulmaz', () async {
      final FakeHealthSteps health = FakeHealthSteps({
        for (int d = 15; d <= 21; d++) day(d): 0,
      });

      await syncWith(health).syncIfDue(userId, provider);

      expect(health.asked, hasLength(7));
      expect(provider.stepsSyncDays, isEmpty);
      expect(await lastSync(), isNull);
    });

    test('admin hesabında ve desteklenmeyen cihazda hiç çalışmaz (izin de '
        'sorulmaz)', () async {
      final FakeHealthSteps health = FakeHealthSteps({day(21): 5000});

      await syncWith(health).syncIfDue(nilay, provider);
      expect(health.asked, isEmpty);

      health.supported = false;
      await syncWith(health).syncIfDue(userId, provider);
      expect(health.asked, isEmpty);
      expect(await readDoc(day(21)), isNull);
    });

    test('yazma başarısız olursa (bağlantı yok) zaman kaydedilmez, sonraki '
        'açılışta yeniden denenir', () async {
      final FakeHealthSteps health = FakeHealthSteps({day(21): 5000});
      final HealthStepsSync sync = syncWith(health);
      provider.stepsSyncFailures = 1;

      await sync.syncIfDue(userId, provider);
      expect(await readDoc(day(21)), isNull);
      expect(await lastSync(), isNull);

      await sync.syncIfDue(userId, provider);
      expect(await readDoc(day(21)), <String, Object>{'steps': 5000});
    });

    test('aynı anda gelen tetiklemeler tek eşitleme yapar', () async {
      final Completer<int?> slow = Completer<int?>();
      final FakeHealthSteps health = FakeHealthSteps({day(21): slow.future});
      final HealthStepsSync sync = syncWith(health);

      final Future<void> first = sync.syncIfDue(userId, provider);
      final Future<void> second = sync.syncIfDue(userId, provider);
      await Future<void>.delayed(Duration.zero);
      slow.complete(3000);
      await Future.wait(<Future<void>>[first, second]);

      expect(health.asked, hasLength(7));
      expect(provider.stepsSyncDays, <DateTime>[day(21)]);
    });

    test('cihaz saati geri alınmışsa (son kayıt gelecekte görünüyorsa) '
        'eşitleme yapılır', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        lastSyncKey: clock.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      });
      final FakeHealthSteps health = FakeHealthSteps({day(21): 700});

      await syncWith(health).syncIfDue(userId, provider);

      expect(await readDoc(day(21)), <String, Object>{'steps': 700});
    });
  });

  group('HealthStepsAutoSync (uygulama açılışı ve ön plana gelme)', () {
    Future<void> pumpAutoSync(
        WidgetTester tester, String uid, HealthStepsSync sync) {
      return tester.pumpWidget(
        ChangeNotifierProvider<DailyDataProvider>.value(
          value: provider,
          child: HealthStepsAutoSync(
            userId: uid,
            sync: sync,
            child: const SizedBox(),
          ),
        ),
      );
    }

    Future<void> backgroundAndResume(WidgetTester tester) async {
      for (final AppLifecycleState state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
    }

    testWidgets('ana sayfa açılınca bir kez, her ön plana gelişte yeniden '
        'tetiklenir', (WidgetTester tester) async {
      final _CountingSync sync = _CountingSync();
      await pumpAutoSync(tester, userId, sync);
      await tester.pump();
      expect(sync.calls, <String>[userId]);

      await backgroundAndResume(tester);
      expect(sync.calls, <String>[userId, userId]);

      await backgroundAndResume(tester);
      expect(sync.calls, hasLength(3));
    });

    testWidgets('başka hesapla girilince o hesap için tetiklenir',
        (WidgetTester tester) async {
      final _CountingSync sync = _CountingSync();
      await pumpAutoSync(tester, userId, sync);
      await tester.pump();
      await pumpAutoSync(tester, 'u2', sync);

      expect(sync.calls, <String>[userId, 'u2']);
    });

    testWidgets('uçtan uca: açılışta kaydedilir; 1 dk sonra ön plana gelince '
        'okunmaz, 6 dk sonra tazelenir', (WidgetTester tester) async {
      final FakeHealthSteps health = FakeHealthSteps({day(21): 5000});
      await tester.runAsync(() async {
        await pumpAutoSync(tester, userId, syncWith(health));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(await tester.runAsync(() => readDoc(day(21))),
          <String, Object>{'steps': 5000});
      final int afterOpen = health.asked.length;

      clock = clock.add(const Duration(minutes: 1));
      health.steps[day(21)] = 6500;
      await tester.runAsync(() async {
        await backgroundAndResume(tester);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(health.asked.length, afterOpen);

      clock = clock.add(const Duration(minutes: 5));
      await tester.runAsync(() async {
        await backgroundAndResume(tester);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(health.asked.length, greaterThan(afterOpen));
      expect(await tester.runAsync(() => readDoc(day(21))),
          <String, Object>{'steps': 6500});
    });
  });
}
