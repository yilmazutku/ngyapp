import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/models/test_attachment.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/admin_notifications_provider.dart';
import 'package:ngy_app/providers/blood_test_provider.dart';
import 'package:ngy_app/providers/test_provider.dart';
import 'package:ngy_app/tabs/tests_tab.dart';
import 'package:ngy_app/utils/date_formatter.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const String customer = 'danisan-1';

  late FakeFirebaseFirestore db;
  late AdminNotificationsProvider notifications;

  DateTime daysAgo(int days) {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day - days);
  }

  Future<void> seedUser({required bool present}) =>
      db.collection('users').doc(customer).set({
        'name': 'Ayşe',
        'surname': 'Yılmaz',
        'email': 'ayse@x.com',
        'role': 'customer',
        UserModel.bloodTestPresentField: present,
      });

  CollectionReference<Map<String, dynamic>> files() =>
      db.collection('users').doc(customer).collection('tests');

  Future<void> seedFile(String id, Map<String, dynamic> extra,
          {required DateTime uploadedAt}) =>
      files().doc(id).set({
        TestAttachment.urlField: 'https://example.com/$id.pdf',
        TestAttachment.fileNameField: '$id.pdf',
        TestAttachment.uploadTimeField: Timestamp.fromDate(uploadedAt),
        TestAttachment.storagePathField: '',
        TestAttachment.contentTypeField: 'application/pdf',
        TestAttachment.isImageField: false,
        ...extra,
      });

  Map<String, dynamic> bloodTest(DateTime testDate) => {
        TestAttachment.isBloodTestField: true,
        TestAttachment.bloodTestDateField: Timestamp.fromDate(testDate),
        TestAttachment.bloodTestReminderField: true,
      };

  Future<Map<String, dynamic>> fileData(String id) async =>
      (await files().doc(id).get()).data()!;

  Future<List<String>> reminderIds() async => [
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in (await db
                .collection(AdminNotificationsProvider.collectionName)
                .get())
            .docs)
          doc.id,
      ];

  List<String> remindersOf(DateTime testDate) => [
        for (final BloodTestReminderStage stage
            in BloodTestReminderStage.values)
          AdminNotification.bloodTestReminderId(customer, testDate, stage),
      ];

  setUp(() {
    db = FakeFirebaseFirestore();
    notifications =
        AdminNotificationsProvider(db: db, currentUid: () => 'admin-1');
  });

  tearDown(() => notifications.dispose());

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TestProvider(db: db)),
        ChangeNotifierProvider<AdminNotificationsProvider>.value(
            value: notifications),
        ChangeNotifierProvider(
          create: (_) =>
              BloodTestProvider(notifications: notifications, db: db),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: TestsTab(userId: customer, userName: 'Ayşe Yılmaz'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder inFile(String id, Finder matching) =>
      find.descendant(of: find.byKey(ValueKey<String>(id)), matching: matching);

  FilledButton filled(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

  Future<void> closeInfo(WidgetTester tester, String containing) async {
    expect(find.textContaining(containing), findsOneWidget);
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'eski doküman Diğer\'de; kalemle kan tahliline taşınır, tarihi aynı '
      'tarihli dosyalarla düzeltilir, geri taşınınca "Hayır" önerilir',
      (WidgetTester tester) async {
    final DateTime testDate = daysAgo(20);
    await seedUser(present: false);
    await seedFile('eski', {}, uploadedAt: DateTime(2026, 1, 5));
    await seedFile('diyet', {TestAttachment.isBloodTestField: false},
        uploadedAt: DateTime(2026, 2, 5));
    await seedFile('kan', bloodTest(testDate), uploadedAt: DateTime(2026, 3, 5));
    await pumpTab(tester);

    expect(find.text('Kan Tahlili (1)'), findsOneWidget);
    expect(find.text('Diğer (2)'), findsOneWidget);
    expect(find.text('Kan Tahlili Yükle'), findsOneWidget);
    expect(find.text('kan.pdf'), findsOneWidget);
    expect(find.text('eski.pdf'), findsNothing);
    expect(
        inFile('kan',
            find.text('Tahlil tarihi: ${DateFormatter.formatNumericDate(testDate)}')),
        findsOneWidget);
    expect(inFile('kan', find.textContaining('Hatırlatma: ')), findsOneWidget);

    await tester.tap(find.text('Diğer (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Doküman Yükle'), findsOneWidget);
    expect(find.text('eski.pdf'), findsOneWidget);
    expect(find.text('diyet.pdf'), findsOneWidget);
    expect(find.textContaining('1 dokümanın türü belirtilmemiş'), findsOneWidget);
    expect(find.byTooltip('Düzenle'), findsNWidgets(2));

    await tester.tap(inFile('eski', find.byTooltip('Düzenle')));
    await tester.pumpAndSettle();
    expect(find.text('Dokümanı Düzenle'), findsOneWidget);
    expect(find.text('Bu bir kan tahlili mi?'), findsOneWidget);
    expect(filled(tester, 'Kaydet').onPressed, isNull);

    await tester.tap(find.text('Evet'));
    await tester.pumpAndSettle();
    expect(find.text('Tarih seçin'), findsOneWidget);
    expect(filled(tester, 'Kan Tahlili\'ne Taşı').onPressed, isNull);
    await tester.tap(find.widgetWithText(
        ChoiceChip, DateFormatter.formatNumericDate(testDate)));
    await tester.pumpAndSettle();
    expect(find.text(DateFormatter.formatLongDate(testDate)), findsOneWidget);
    await tester.tap(find.text('Kan Tahlili\'ne Taşı'));
    await tester.pumpAndSettle();
    await closeInfo(tester, 'Kan Tahlili sekmesine taşındı');

    final Map<String, dynamic> moved = await fileData('eski');
    expect(moved[TestAttachment.isBloodTestField], isTrue);
    expect((moved[TestAttachment.bloodTestDateField] as Timestamp).toDate(),
        testDate);
    expect(find.text('Kan Tahlili (2)'), findsOneWidget);
    expect(find.text('Diğer (1)'), findsOneWidget);
    expect(find.textContaining('türü belirtilmemiş'), findsNothing);
    expect(await reminderIds(), unorderedEquals(remindersOf(testDate)));
    expect((await db.collection('users').doc(customer).get())
        .data()![UserModel.bloodTestPresentField], isTrue);

    await tester.tap(find.text('Kan Tahlili (2)'));
    await tester.pumpAndSettle();
    await tester.tap(inFile('kan', find.byTooltip('Düzenle')));
    await tester.pumpAndSettle();
    expect(
        find.text('Aynı tarihli (${DateFormatter.formatNumericDate(testDate)}) '
            'diğer 1 dosyaya da uygula'),
        findsOneWidget);
    expect(filled(tester, 'Kaydet').onPressed, isNull);
    await tester.tap(find.text('Tahlilin Yapıldığı Tarih'));
    await tester.pumpAndSettle();
    final int pickedDay = testDate.day == 1 ? 2 : 1;
    await tester.tap(find.text('$pickedDay'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final DateTime corrected =
        DateTime(testDate.year, testDate.month, pickedDay);
    expect(find.text(DateFormatter.formatLongDate(corrected)), findsOneWidget);
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    await closeInfo(tester, '2 dosya');

    for (final String id in ['kan', 'eski']) {
      expect(
          ((await fileData(id))[TestAttachment.bloodTestDateField] as Timestamp)
              .toDate(),
          corrected,
          reason: id);
    }
    expect(await reminderIds(), unorderedEquals(remindersOf(corrected)));

    await tester.tap(inFile('kan', find.byTooltip('Düzenle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hayır'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dosya Diğer sekmesine taşınır'), findsOneWidget);
    expect(
        find.text('Aynı tarihli (${DateFormatter.formatNumericDate(corrected)}) '
            'diğer 1 dosyayı da taşı'),
        findsOneWidget);
    await tester.tap(find.text('Diğer\'e Taşı'));
    await tester.pumpAndSettle();
    await closeInfo(tester, '2 dosya Diğer sekmesine taşındı');

    expect(find.text('Kan Tahlili Kalmadı'), findsOneWidget);
    await tester.tap(find.text('"Hayır" olarak işaretle'));
    await tester.pumpAndSettle();
    expect((await db.collection('users').doc(customer).get())
        .data()![UserModel.bloodTestPresentField], isFalse);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Kan Tahlili (0)'), findsOneWidget);
    expect(find.text('Diğer (3)'), findsOneWidget);
    expect(find.text('Henüz kan tahlili yüklenmedi.'), findsOneWidget);
    expect(await reminderIds(), isEmpty);
    final Map<String, dynamic> back = await fileData('kan');
    expect(back[TestAttachment.isBloodTestField], isFalse);
    expect(back.containsKey(TestAttachment.bloodTestDateField), isFalse);
  });

  testWidgets(
      'kan tahlili yokken eski dokümanlara yol gösterir; "Hayır" seçilen '
      'eski doküman Diğer olarak kaydedilir', (WidgetTester tester) async {
    await seedUser(present: false);
    await seedFile('eski', {}, uploadedAt: DateTime(2026, 1, 5));
    await pumpTab(tester);

    expect(find.text('Kan Tahlili (0)'), findsOneWidget);
    expect(find.textContaining('türü belirtilmemiş 1 doküman var'),
        findsOneWidget);
    await tester.tap(find.text('Diğer sekmesine git'));
    await tester.pumpAndSettle();
    expect(find.text('eski.pdf'), findsOneWidget);

    expect(find.text('Düzenle'), findsNothing);
    final TestGesture mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(inFile('eski', find.byTooltip('Düzenle'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Düzenle'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.text('Düzenle'), findsNothing);

    await tester.tap(inFile('eski', find.byTooltip('Düzenle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('türü sorulmadan yüklendiği için'),
        findsOneWidget);
    await tester.tap(find.text('Hayır'));
    await tester.pumpAndSettle();
    expect(find.textContaining('türü sorulmadan yüklendiği için'),
        findsNothing);
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    await closeInfo(tester, '"Diğer" olarak kaydedildi');

    expect((await fileData('eski'))[TestAttachment.isBloodTestField], isFalse);
    expect(find.textContaining('türü belirtilmemiş'), findsNothing);
    expect(find.text('Kan Tahlili Kalmadı'), findsNothing);
    expect(await reminderIds(), isEmpty);
  });

  testWidgets(
      'son kan tahlili silinince hatırlatması kalkar, "Evet" kalabilir',
      (WidgetTester tester) async {
    final DateTime testDate = daysAgo(10);
    await seedUser(present: true);
    await seedFile('kan', bloodTest(testDate), uploadedAt: DateTime(2026, 3, 5));
    await notifications.syncBloodTestReminders(
      userId: customer,
      userName: 'Ayşe Yılmaz',
      testDates: {testDate: true},
    );
    await pumpTab(tester);

    await tester.tap(inFile('kan', find.text('Sil')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 ay hatırlatması da kaldırılır'),
        findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Sil')));
    await tester.pumpAndSettle();
    await closeInfo(tester, 'Bu tahlilin 3 ay hatırlatması kaldırıldı');

    expect(await reminderIds(), isEmpty);
    expect(find.text('Kan Tahlili Kalmadı'), findsOneWidget);
    await tester.tap(find.text('"Evet" kalsın'));
    await tester.pumpAndSettle();
    expect((await db.collection('users').doc(customer).get())
        .data()![UserModel.bloodTestPresentField], isTrue);
    expect(find.text('Kan Tahlili (0)'), findsOneWidget);
  });
}
