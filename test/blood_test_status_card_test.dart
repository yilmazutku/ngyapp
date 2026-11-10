import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/test_attachment.dart';
import 'package:ngy_app/providers/test_provider.dart';
import 'package:ngy_app/utils/calendar_day.dart';
import 'package:ngy_app/utils/date_formatter.dart';
import 'package:ngy_app/widgets/blood_test_status_card.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const String customer = 'danisan-1';

  late FakeFirebaseFirestore db;
  late TestProvider tests;

  setUp(() {
    db = FakeFirebaseFirestore();
    tests = TestProvider(db: db);
  });

  tearDown(() => tests.dispose());

  Future<void> seedFile(String id, Map<String, dynamic> extra,
          {required DateTime uploadedAt}) =>
      db.collection('users').doc(customer).collection('tests').doc(id).set({
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
        TestAttachment.bloodTestDateField: calendarDayToTimestamp(testDate),
        TestAttachment.bloodTestReminderField: true,
      };

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<TestProvider>.value(
      value: tests,
      child: const MaterialApp(
        home: Scaffold(body: BloodTestStatusCard(userId: customer)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'yüklü değilken nereden yükleneceğini söyler, taşınınca hemen '
      '"Yüklü" olur ve yüklenme ile tahlil tarihini gösterir',
      (WidgetTester tester) async {
    final DateTime uploadedAt = DateTime(2025, 12, 1, 14, 30);
    await seedFile('eski', {}, uploadedAt: uploadedAt);
    await seedFile('diyet', {TestAttachment.isBloodTestField: false},
        uploadedAt: DateTime(2026, 1, 1));
    await pumpCard(tester);

    expect(find.text('Kan tahlili'), findsOneWidget);
    expect(find.text('Yüklü değil'), findsOneWidget);
    expect(find.textContaining('Kan Tahlili bölümünden yüklenir'),
        findsOneWidget);
    expect(find.textContaining('türü belirtilmemiş 1 doküman var'),
        findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Evet'), findsNothing);

    final DateTime testDate = DateTime(2025, 11, 20);
    await tests.updateDocumentCategory(
      userId: customer,
      docIds: ['eski'],
      bloodTest: BloodTestInfo(testDate: testDate, wantsReminder: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yüklü'), findsOneWidget);
    expect(find.text('Yüklü değil'), findsNothing);
    expect(
        find.text(
            'Yüklenme: ${DateFormatter.formatLongDateTime(uploadedAt)}'),
        findsOneWidget);
    expect(
        find.text('Tahlil tarihi: ${DateFormatter.formatLongDate(testDate)}'),
        findsOneWidget);
    expect(find.textContaining('türü belirtilmemiş'), findsNothing);
  });

  testWidgets('birden çok tahlilde en yeni tarihli tahlilin yüklenmesini '
      'gösterir', (WidgetTester tester) async {
    final DateTime newestUpload = DateTime(2026, 11, 2, 10, 15);
    await seedFile('ekim', bloodTest(DateTime(2026, 10, 14)),
        uploadedAt: newestUpload);
    await seedFile('eylul', bloodTest(DateTime(2026, 9, 1)),
        uploadedAt: DateTime(2026, 11, 5, 9));
    await pumpCard(tester);

    expect(find.text('Yüklü'), findsOneWidget);
    expect(
        find.text(
            'Yüklenme: ${DateFormatter.formatLongDateTime(newestUpload)}'),
        findsOneWidget);
    expect(
        find.text('Tahlil tarihi: '
            '${DateFormatter.formatLongDate(DateTime(2026, 10, 14))}'),
        findsOneWidget);
  });
}
