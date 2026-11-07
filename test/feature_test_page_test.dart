import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/models/feature_test_checklist.dart';
import 'package:ngy_app/models/feature_test_plan.dart';
import 'package:ngy_app/pages/feature_test_page.dart';
import 'package:ngy_app/providers/admin_notifications_provider.dart';
import 'package:ngy_app/providers/appointment_colors_provider.dart';
import 'package:ngy_app/providers/blood_test_provider.dart';
import 'package:ngy_app/providers/meal_photo_notifications_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/services/admin_notification_delivery.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoScheduler implements AdminNotificationScheduler {
  @override
  bool get isSupported => false;

  @override
  Future<bool> showNow({
    required String docId,
    required String title,
    required String body,
    String? notificationKey,
  }) async =>
      true;

  @override
  Future<bool> schedule({
    required String docId,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async =>
      false;

  @override
  Future<void> cancel(String docId) async {}

  @override
  Future<Set<String>> pendingDocIds() async => const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const String admin = 'admin-1';

  late FakeFirebaseFirestore db;
  late AdminNotificationsProvider notifications;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    notifications = AdminNotificationsProvider(
      db: db,
      currentUid: () => admin,
      delivery: AdminNotificationDelivery(
        local: _NoScheduler(),
        banner: ({required title, required body, required data}) {},
        osShowsInForeground: false,
      ),
    );
  });

  tearDown(() => notifications.dispose());

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 24000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AdminNotificationsProvider>.value(
              value: notifications),
          ChangeNotifierProvider(
              create: (_) => MealPhotoNotificationsProvider(db: db)),
          ChangeNotifierProvider(
            create: (_) =>
                BloodTestProvider(notifications: notifications, db: db),
          ),
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(
              create: (_) => AppointmentColorsProvider(db: db)),
        ],
        child: const MaterialApp(home: FeatureTestPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inStep(String stepId, Finder matching) => find.descendant(
      of: find.byKey(ValueKey<String>(stepId)), matching: matching);

  Future<Map<String, Object?>> stored() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final FeatureTestChecklist checklist =
        FeatureTestChecklist(platform: TargetPlatform.android);
    addTearDown(checklist.dispose);
    await checklist.load();
    return {
      'kilo.ekle': checklist.resultOf('kilo.ekle'),
      'kilo.kart': checklist.resultOf('kilo.kart'),
      'kilo.kart.note': checklist.noteOf('kilo.kart'),
      'raw': prefs.getString(FeatureTestChecklist.storageKey),
    };
  }

  testWidgets('sonuç ve not işaretlenir, filtrelenir, raporlanır, sıfırlanır',
      (WidgetTester tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpPage(tester);
    expect(find.textContaining('0 / '), findsOneWidget);
    expect(find.text('Sıfırla'), findsNothing);

    await tester
        .tap(inStep('kilo.ekle', find.byTooltip('Geçti olarak işaretle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / '), findsOneWidget);

    await tester
        .tap(inStep('kilo.kart', find.widgetWithText(ChoiceChip, 'Hatalı')));
    await tester.pumpAndSettle();
    expect(find.text('Not Ekle'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Not'), 'Kart görünmedi');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();
    expect(
        inStep('kilo.kart', find.text('Not: Kart görünmedi')), findsOneWidget);
    expect(find.textContaining('2 / '), findsOneWidget);

    final Map<String, Object?> saved = await stored();
    expect(saved['kilo.ekle'], FeatureTestResult.passed);
    expect(saved['kilo.kart'], FeatureTestResult.failed);
    expect(saved['kilo.kart.note'], 'Kart görünmedi');

    await tester.tap(find.widgetWithText(FilterChip, 'Hatalı (1)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('kilo.kart')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('kilo.ekle')), findsNothing);
    expect(find.byKey(const ValueKey<String>('kan')), findsNothing);

    await tester.tap(find.text('Raporu kopyala'));
    await tester.pumpAndSettle();
    expect(copied, contains('HATALI ADIMLAR (1)'));
    expect(copied, contains('Not: Kart görünmedi'));

    await tester
        .tap(find.widgetWithText(FilterChip, 'Tümü (${_totalSteps()})'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sıfırla'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Sıfırla'),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 / '), findsOneWidget);
    expect((await stored())['kilo.kart.note'], isNull);
  });

  testWidgets('kendi adımını ekleyip silebilir', (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey<String>('kilo')),
      matching: find.text('Adım ekle'),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Kaydet'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
            .onPressed,
        isNull);

    await tester.enterText(
        find.widgetWithText(TextField, 'Yapılacak'), 'Paketi sil');
    await tester.enterText(
        find.widgetWithText(TextField, 'Beklenen sonuç'), 'Tarih de silinir');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();
    expect(
        find.text('${featureTestSections.first.steps.length + 1}. Paketi sil'),
        findsOneWidget);
    expect(find.text('Kendi adımınız'), findsOneWidget);

    await tester.tap(find.byTooltip('Adımı sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Sil'),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paketi sil'), findsNothing);
  });

  testWidgets(
      'bildirim simülatörü yalnızca kurana görünen deneme bildirimi kurar',
      (WidgetTester tester) async {
    await pumpPage(tester);
    final Finder simulator = find.byKey(const ValueKey<String>('teslim'));
    await tester.tap(find.descendant(
      of: simulator,
      matching: find.widgetWithText(FilterChip, 'Hemen'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: simulator,
      matching: find.widgetWithText(FilledButton, 'Bildirimi kur'),
    ));
    await tester.pumpAndSettle();

    final List<AdminNotification> docs = [
      for (final doc in (await db
              .collection(AdminNotificationsProvider.collectionName)
              .get())
          .docs)
        AdminNotification.fromDocument(doc)!,
    ];
    expect(docs.map((n) => n.type), [AdminNotificationType.test]);
    expect(docs.single.onlyFor, admin);
    expect(docs.single.isTest, isTrue);
    expect(find.text('"Deneme" bildirimi zile düştü.'), findsWidgets);

    await tester.tap(find.descendant(
      of: simulator,
      matching: find.widgetWithText(FilterChip, 'Kan tahlili · 3 ay doldu'),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.descendant(
              of: simulator,
              matching: find.widgetWithText(FilledButton, 'Bildirimi kur'),
            ))
            .onPressed,
        isNull);
  });

  testWidgets('zaman makinesi gerçek kurallarla hızlandırılmış deneme '
      'bildirimleri kurar', (WidgetTester tester) async {
    await pumpPage(tester);
    final Finder machine = find.byKey(const ValueKey<String>('zaman'));
    expect(
        find.descendant(
            of: machine,
            matching: find.textContaining('Günlük taramada')),
        findsOneWidget);

    final DateTime before = DateTime.now();
    await tester.tap(find.descendant(
      of: machine,
      matching: find.widgetWithText(FilledButton, 'Başlat'),
    ));
    await tester.pumpAndSettle();

    final List<AdminNotification> first = [
      for (final doc in (await db
              .collection(AdminNotificationsProvider.collectionName)
              .get())
          .docs)
        AdminNotification.fromDocument(doc)!,
    ];
    expect(first.map((n) => n.type), [AdminNotificationType.missingBloodTests]);
    expect(first.single.isTest, isTrue);
    expect(first.single.onlyFor, admin);
    expect(first.single.customers.map((c) => c.name), ['Deneme Danışan']);
    expect(first.single.fireAt.isAfter(before), isTrue);
    expect(first.single.fireAt.isBefore(before.add(const Duration(minutes: 4))),
        isTrue);

    await tester.tap(find.descendant(
      of: machine,
      matching: find.widgetWithText(FilterChip, '2 gün sonra 3 ay doluyor'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: machine,
      matching: find.widgetWithText(FilledButton, 'Başlat'),
    ));
    await tester.pumpAndSettle();
    final List<AdminNotification> all = [
      for (final doc in (await db
              .collection(AdminNotificationsProvider.collectionName)
              .get())
          .docs)
        AdminNotification.fromDocument(doc)!,
    ];
    final List<AdminNotification> reminders = [
      for (final AdminNotification n in all)
        if (n.type == AdminNotificationType.bloodTestReminder) n,
    ]..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    expect(reminders.map((n) => n.stage), [
      BloodTestReminderStage.dayBefore,
      BloodTestReminderStage.dueDay,
    ]);
    expect(reminders.every((n) => n.isTest && n.userName == 'Deneme Danışan'),
        isTrue);
  });
}

int _totalSteps() => featureTestSections.fold(
    0, (int sum, FeatureTestSection section) => sum + section.steps.length);
