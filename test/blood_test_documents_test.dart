import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/models/blood_test_status.dart';
import 'package:ngy_app/models/test_attachment.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/admin_notifications_provider.dart';
import 'package:ngy_app/providers/blood_test_provider.dart';
import 'package:ngy_app/providers/test_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const String customer = 'danisan-1';

  late FakeFirebaseFirestore db;
  late TestProvider tests;
  late AdminNotificationsProvider notifications;
  late BloodTestProvider bloodTests;

  setUp(() async {
    db = FakeFirebaseFirestore();
    tests = TestProvider(db: db);
    notifications =
        AdminNotificationsProvider(db: db, currentUid: () => 'admin-1');
    bloodTests = BloodTestProvider(notifications: notifications, db: db);
    await db.collection('users').doc(customer).set({
      'name': 'Ayşe',
      'surname': 'Yılmaz',
      'email': 'ayse@x.com',
      'role': 'customer',
      'createDate': Timestamp.fromDate(DateTime(2025, 1, 1)),
      UserModel.bloodTestPresentField: false,
    });
    await db
        .collection('users')
        .doc(customer)
        .collection('subscriptions')
        .add({'status': 'active'});
  });

  tearDown(() {
    bloodTests.dispose();
    notifications.dispose();
    tests.dispose();
  });

  CollectionReference<Map<String, dynamic>> files() =>
      db.collection('users').doc(customer).collection('tests');

  DateTime daysAgo(int days) {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day - days);
  }

  Future<void> seed(String id, Map<String, dynamic> extra,
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

  Map<String, dynamic> bloodTest(DateTime testDate, {bool reminder = true}) => {
        TestAttachment.isBloodTestField: true,
        TestAttachment.bloodTestDateField: Timestamp.fromDate(testDate),
        TestAttachment.bloodTestReminderField: reminder,
      };

  Future<bool?> presence() async => (await db
          .collection('users')
          .doc(customer)
          .get())
      .data()?[UserModel.bloodTestPresentField] as bool?;

  Future<List<String>> reminderIds() async => [
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in (await db
                .collection(AdminNotificationsProvider.collectionName)
                .get())
            .docs)
          doc.id,
      ];

  group('dokümanlar', () {
    test('türü sorulmadan yüklenenler Diğer\'de, kan tahlilleri tarihe göre',
        () async {
      await seed('eski', {}, uploadedAt: DateTime(2026, 1, 5));
      await seed('diger', {TestAttachment.isBloodTestField: false},
          uploadedAt: DateTime(2026, 3, 1));
      await seed('kan-eski', bloodTest(DateTime(2026, 2, 1)),
          uploadedAt: DateTime(2026, 9, 1));
      await seed('kan-yeni', bloodTest(DateTime(2026, 8, 1), reminder: false),
          uploadedAt: DateTime(2026, 8, 2));
      await seed('tarihsiz', {TestAttachment.isBloodTestField: true},
          uploadedAt: DateTime(2026, 4, 1));

      final List<TestAttachment> all =
          await tests.fetchTestAttachments(customer);
      final List<TestAttachment> blood =
          TestAttachment.ofCategory(all, DocumentCategory.bloodTest);
      final List<TestAttachment> other =
          TestAttachment.ofCategory(all, DocumentCategory.other);

      expect(blood.map((f) => f.docId), ['tarihsiz', 'kan-yeni', 'kan-eski']);
      expect(other.map((f) => f.docId), ['diger', 'eski']);
      expect(other.last.isUnclassified, isTrue);
      expect(other.first.isUnclassified, isFalse);
      expect(blood[1].bloodTestDate, DateTime(2026, 8, 1));
      expect(blood[1].bloodTestReminder, isFalse);
      expect(blood.first.bloodTestDate, isNull);
      expect(TestAttachment.latestTestDate(all), DateTime(2026, 8, 1));
      expect(TestAttachment.testDatesOf(all),
          [DateTime(2026, 8, 1), DateTime(2026, 2, 1)]);
      expect(TestAttachment.reminderWishesOf(all), {
        DateTime(2026, 8, 1): false,
        DateTime(2026, 2, 1): true,
      });
    });

    test('Diğer\'den kan tahliline taşınır, geri taşınınca tarihi silinir',
        () async {
      await seed('a', {}, uploadedAt: DateTime(2026, 1, 5));
      await seed('b', {}, uploadedAt: DateTime(2026, 1, 6));

      await tests.updateDocumentCategory(
        userId: customer,
        docIds: ['a', 'b'],
        bloodTest: BloodTestInfo(
            testDate: DateTime(2026, 10, 3, 14, 20), wantsReminder: true),
      );
      final Map<String, dynamic> marked = (await files().doc('a').get()).data()!;
      expect(marked[TestAttachment.isBloodTestField], isTrue);
      expect((marked[TestAttachment.bloodTestDateField] as Timestamp).toDate(),
          DateTime(2026, 10, 3));
      expect(marked[TestAttachment.bloodTestReminderField], isTrue);
      expect(marked[TestAttachment.fileNameField], 'a.pdf');
      expect(
          (await files().doc('b').get()).data()![TestAttachment.isBloodTestField],
          isTrue);

      await tests.updateDocumentCategory(userId: customer, docIds: ['a']);
      final Map<String, dynamic> moved = (await files().doc('a').get()).data()!;
      expect(moved[TestAttachment.isBloodTestField], isFalse);
      expect(moved.containsKey(TestAttachment.bloodTestDateField), isFalse);
      expect(moved.containsKey(TestAttachment.bloodTestReminderField), isFalse);
      expect(
          TestAttachment.fromMap('a', moved).category, DocumentCategory.other);
    });
  });

  test('en yeni kan tahlili: en geç tarih, aynı tarihte en son yüklenen',
      () {
    TestAttachment file(String id, DateTime? testDate, DateTime uploadedAt,
            {bool? mark = true}) =>
        TestAttachment.fromMap(id, {
          TestAttachment.uploadTimeField: Timestamp.fromDate(uploadedAt),
          if (mark != null) TestAttachment.isBloodTestField: mark,
          if (testDate != null)
            TestAttachment.bloodTestDateField: Timestamp.fromDate(testDate),
        });

    expect(TestAttachment.latestBloodTest([]), isNull);
    expect(
        TestAttachment.latestBloodTest([
          file('diger', null, DateTime(2026, 11, 1), mark: false),
          file('eski', null, DateTime(2026, 11, 2), mark: null),
        ]),
        isNull);
    expect(
        TestAttachment.latestBloodTest([
          file('tarihsiz', null, DateTime(2026, 11, 5)),
          file('ekim1', DateTime(2026, 10, 1), DateTime(2026, 10, 2)),
          file('ekim2', DateTime(2026, 10, 1), DateTime(2026, 10, 3)),
          file('eylul', DateTime(2026, 9, 1), DateTime(2026, 11, 4)),
        ])!.docId,
        'ekim2');
    expect(
        TestAttachment.latestBloodTest([
          file('tarihsiz', null, DateTime(2026, 11, 5)),
        ])!.docId,
        'tarihsiz');
  });

  group('3 ay hatırlatması yalnızca aktif danışana', () {
    Future<void> setPackages(String status) async {
      final QuerySnapshot<Map<String, dynamic>> packages = await db
          .collection('users')
          .doc(customer)
          .collection('subscriptions')
          .get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in packages.docs) {
        await doc.reference.update({'status': status});
      }
    }

    test('paketi bitmiş danışana kurulmaz, aktif paket eklenince kurulur',
        () async {
      final DateTime testDate = daysAgo(10);
      await setPackages('completed');
      await seed('k1', bloodTest(testDate), uploadedAt: DateTime(2026, 1, 6));

      final BloodTestReminderSync sync =
          await bloodTests.syncReminders(userId: customer, userName: 'Ayşe');
      expect(sync.remindersAllowed, isFalse);
      expect(sync.remindFor, isNull);
      expect(await reminderIds(), isEmpty);
      expect(await presence(), isTrue);

      await setPackages('frozen');
      final BloodTestReminderSync? refreshed =
          await bloodTests.refreshRemindersOf(customer);
      expect(refreshed!.remindersAllowed, isTrue);
      expect(await reminderIds(), unorderedEquals([
        for (final BloodTestReminderStage stage
            in BloodTestReminderStage.values)
          AdminNotification.bloodTestReminderId(customer, testDate, stage),
      ]));
    });

    test('paket durumu değişince bekleyen hatırlatmalar hemen güncellenir',
        () async {
      final StreamController<String> changes = StreamController<String>();
      addTearDown(changes.close);
      final BloodTestProvider listening = BloodTestProvider(
        notifications: notifications,
        db: db,
        packageStatusChanges: changes.stream,
      );
      addTearDown(listening.dispose);
      final DateTime testDate = daysAgo(10);
      await seed('k1', bloodTest(testDate), uploadedAt: DateTime(2026, 1, 6));
      await listening.syncReminders(userId: customer, userName: 'Ayşe');
      expect(await reminderIds(), hasLength(2));

      await setPackages('completed');
      changes.add(customer);
      await pumpEventQueue();
      expect(await reminderIds(), isEmpty);

      await setPackages('active_kt');
      changes.add(customer);
      await pumpEventQueue();
      expect(await reminderIds(), hasLength(2));
    });
  });

  group('hatırlatma ve "doküman mevcut" eşitlemesi', () {
    test('en yeni kan tahlilinin hatırlatması kurulur, danışan "yüklü" olur',
        () async {
      final DateTime older = daysAgo(60);
      final DateTime latest = daysAgo(10);
      await seed('eski', {}, uploadedAt: DateTime(2026, 1, 5));
      await seed('k1', bloodTest(older), uploadedAt: DateTime(2026, 1, 6));
      await seed('k2', bloodTest(latest), uploadedAt: DateTime(2026, 1, 7));

      final BloodTestReminderSync sync =
          await bloodTests.syncReminders(userId: customer, userName: 'Ayşe');

      expect(sync.latestTestDate, latest);
      expect(sync.remindFor, latest);
      expect(await reminderIds(), unorderedEquals([
        for (final BloodTestReminderStage stage
            in BloodTestReminderStage.values)
          AdminNotification.bloodTestReminderId(customer, latest, stage),
      ]));
      expect(await presence(), isTrue);
    });

    test('Diğer\'e taşınan tahlil takipten çıkar, önceki tahlil geri gelir',
        () async {
      final DateTime older = daysAgo(40);
      final DateTime wrong = daysAgo(3);
      await seed('k1', bloodTest(older), uploadedAt: DateTime(2026, 1, 6));
      await seed('k2', bloodTest(wrong), uploadedAt: DateTime(2026, 1, 7));
      await bloodTests.syncReminders(userId: customer, userName: 'Ayşe');

      await tests.updateDocumentCategory(userId: customer, docIds: ['k2']);
      final BloodTestReminderSync sync =
          await bloodTests.syncReminders(userId: customer, userName: 'Ayşe');

      expect(sync.latestTestDate, older);
      expect(sync.remindFor, older);
      expect(sync.written, 2);
      expect(await reminderIds(), unorderedEquals([
        for (final BloodTestReminderStage stage
            in BloodTestReminderStage.values)
          AdminNotification.bloodTestReminderId(customer, older, stage),
      ]));
    });

    test('kan tahlili kalmayınca hatırlatmalar silinir, danışan "yüklü değil" '
        'olur',
        () async {
      await seed('k1', bloodTest(daysAgo(10)), uploadedAt: DateTime(2026, 1, 6));
      await bloodTests.syncReminders(userId: customer, userName: 'Ayşe');
      expect(await reminderIds(), hasLength(2));

      await tests.updateDocumentCategory(userId: customer, docIds: ['k1']);
      final BloodTestReminderSync sync =
          await bloodTests.syncReminders(userId: customer, userName: 'Ayşe');

      expect(sync.hasBloodTests, isFalse);
      expect(await reminderIds(), isEmpty);
      expect(await presence(), isFalse);
    });

    test('Doküman Kontrol kayıttaki işarete değil dosyalara bakar', () async {
      await db.collection('users').doc(customer).update({
        UserModel.bloodTestPresentField: true,
      });
      await seed('diger', {TestAttachment.isBloodTestField: false},
          uploadedAt: DateTime(2026, 1, 6));

      final BloodTestReport report =
          await bloodTests.checkAllCustomers(now: DateTime.now());

      expect(report.statuses.single.kind, BloodTestStatusKind.missingFirst);
    });

    test('Doküman Kontrol, Diğer\'e taşınan tahlilin tarihine bakmaz',
        () async {
      await seed('k1', bloodTest(daysAgo(200)),
          uploadedAt: DateTime(2026, 1, 6));
      await seed('k2', bloodTest(daysAgo(5)), uploadedAt: DateTime(2026, 1, 7));
      await tests.updateDocumentCategory(userId: customer, docIds: ['k2']);
      await bloodTests.syncReminders(userId: customer, userName: 'Ayşe');

      final DateTime now = DateTime.now();
      final BloodTestReport report =
          await bloodTests.checkAllCustomers(now: now);
      expect(report.statuses.single.lastTestDate, daysAgo(200));
    });
  });
}
