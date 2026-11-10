import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/pages/chat_load_test_page.dart';
import 'package:ngy_app/providers/chat_load_test_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/services/frame_stats_monitor.dart';
import 'package:ngy_app/widgets/frame_stats_badge.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const String office = '0MvvbZsjbmNPW4QYShRNSOOtkE43';

  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());
  tearDown(FrameStatsOverlay.hide);

  DocumentReference<Map<String, dynamic>> run(String id) =>
      db.collection('chatLoadTests').doc(id);

  Future<void> seedRuns() async {
    final DateTime now = DateTime.now();
    await run('RunRunning001').set({
      'status': 'running',
      'createdAt': Timestamp.fromDate(now),
      'startAt': Timestamp.fromDate(now.subtract(const Duration(seconds: 30))),
      'heartbeatAt': Timestamp.fromDate(now),
      'userCount': 30,
      'photosPerUser': 3,
      'totalSteps': 90,
      'sentCount': 40,
      'failedCount': 2,
      'gapSeconds': 0.5,
      'order': 'roundRobin',
      'lastError': '12. mesaj zaman aşımına uğradı.',
    });
    await run('RunStalled002').set({
      'status': 'running',
      'createdAt':
          Timestamp.fromDate(now.subtract(const Duration(minutes: 20))),
      'startAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 19))),
      'heartbeatAt':
          Timestamp.fromDate(now.subtract(const Duration(minutes: 10))),
      'userCount': 5,
      'photosPerUser': 2,
      'totalSteps': 10,
      'sentCount': 3,
      'gapSeconds': 60,
      'order': 'perUser',
    });
    await run('RunDone000003').set({
      'status': 'completed',
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
      'startAt': Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
      'finishedAt':
          Timestamp.fromDate(now.subtract(const Duration(minutes: 50))),
      'userCount': 2,
      'photosPerUser': 1,
      'totalSteps': 2,
      'sentCount': 2,
      'gapSeconds': 1,
      'order': 'roundRobin',
    });
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required Size size,
    String uid = office,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
        ChangeNotifierProvider<ChatLoadTestProvider>(
          create: (_) => ChatLoadTestProvider(db: db, currentUid: () => uid),
        ),
      ],
      child: const MaterialApp(home: ChatLoadTestPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  for (final Size size in const [Size(360, 740), Size(1280, 900)]) {
    testWidgets('sayfa ${size.width.toInt()} px genişlikte taşmadan çizilir',
        (tester) async {
      await seedRuns();
      await pumpPage(tester, size: size);

      expect(tester.takeException(), isNull);
      expect(find.text(ChatLoadTestPage.title), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Tümünü Temizle'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  testWidgets('fotoğraf seçilmeden test başlatılamaz', (tester) async {
    await pumpPage(tester, size: const Size(1280, 900));
    expect(find.text('En az 1, en fazla 5 fotoğraf seçin.'), findsOneWidget);
    final ElevatedButton start = tester.widget<ElevatedButton>(find.ancestor(
      of: find.text('Testi Başlat'),
      matching: find.byWidgetPredicate((w) => w is ElevatedButton),
    ));
    expect(start.onPressed, isNull);
    await unmount(tester);
  });

  testWidgets('hatalı sayı girilince uyarı görünür', (tester) async {
    await pumpPage(tester, size: const Size(1280, 900));
    await tester.enterText(
        find.widgetWithText(TextField, 'Test kullanıcısı sayısı'), '');
    await tester.pump();
    expect(find.text('Sayıları kontrol edin.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('test listesi durumları ve düğmeleri', (tester) async {
    await seedRuns();
    await pumpPage(tester, size: const Size(1280, 2600));

    expect(find.text('Sürüyor'), findsNWidgets(2));
    expect(find.text('Tamamlandı'), findsOneWidget);
    expect(find.text('Gönderilen 40/90 · başarısız 2'), findsOneWidget);
    expect(find.text('12. mesaj zaman aşımına uğradı.'), findsOneWidget);
    expect(find.text('Durdur'), findsNWidgets(2));
    expect(find.text('Sürdür'), findsOneWidget);
    expect(find.text('Temizle'), findsOneWidget);
    expect(find.text('Sohbetler\'i Aç'), findsNWidgets(2));
    await unmount(tester);
  });

  testWidgets('ofis dışındaki admin sohbetleri açamaz, uyarı görür',
      (tester) async {
    await seedRuns();
    await pumpPage(tester, size: const Size(1280, 2600), uid: 'admin-2');
    expect(find.text('Sohbetler\'i Aç'), findsNothing);
    expect(find.textContaining('yalnızca sohbet ofisinin'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Durdur onaylanınca test iptal edilir', (tester) async {
    await seedRuns();
    await pumpPage(tester, size: const Size(1280, 2600));

    await tester.tap(find.text('Durdur').first);
    await tester.pumpAndSettle();
    expect(find.text('Test Durdurulsun mu?'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Durdur'),
    ));
    await tester.pumpAndSettle();

    expect((await run('RunRunning001').get()).get('status'), 'cancelled');
    expect(
      (await run('RunRunning001').collection('control').doc('stop').get())
          .exists,
      isTrue,
    );
    expect(find.text('Durduruldu'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Sürdür onaylanınca yeni zincir açılır', (tester) async {
    await seedRuns();
    await pumpPage(tester, size: const Size(1280, 2600));

    await tester.tap(find.text('Sürdür'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Sürdür'),
    ));
    await tester.pumpAndSettle();

    final QuerySnapshot<Map<String, dynamic>> ticks =
        await run('RunStalled002').collection('ticks').get();
    expect(ticks.docs, hasLength(1));
    expect(ticks.docs.single.get('fromIndex'), 0);
    await unmount(tester);
  });

  testWidgets('kare göstergesi açılıp kapanır', (tester) async {
    await pumpPage(tester, size: const Size(1280, 2600));

    final Finder toggle = find.widgetWithText(SwitchListTile, 'Göstergeyi göster');
    await tester.tap(toggle);
    await tester.pump();
    expect(FrameStatsMonitor.instance.isRunning, isTrue);
    expect(find.byType(FrameStatsBadge), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    expect(FrameStatsMonitor.instance.isRunning, isFalse);
    expect(find.byType(FrameStatsBadge), findsNothing);
    await unmount(tester);
  });
}
