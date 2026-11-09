import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/models/blood_test_scan.dart';
import 'package:ngy_app/models/blood_test_status.dart';
import 'package:ngy_app/providers/admin_notifications_provider.dart';
import 'package:ngy_app/providers/blood_test_provider.dart';
import 'package:ngy_app/utils/date_formatter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const String admin = 'admin-1';

  late FakeFirebaseFirestore db;
  late BloodTestProvider provider;

  setUp(() {
    db = FakeFirebaseFirestore();
    provider = BloodTestProvider(
      db: db,
      notifications: AdminNotificationsProvider(
        db: db,
        currentUid: () => admin,
      ),
    );
  });

  Future<void> addUser(
    String id, {
    String name = 'Ad',
    String surname = 'Soyad',
    String role = 'customer',
    required DateTime createDate,
    bool? present,
    bool removalRequested = false,
  }) =>
      db.collection('users').doc(id).set({
        'name': name,
        'surname': surname,
        'email': '$id@x.com',
        'role': role,
        'createDate': Timestamp.fromDate(createDate),
        if (present != null) 'isBloodTestPresent': present,
        if (removalRequested) 'isUserRequestedRemoval': true,
      });

  Future<Map<String, dynamic>> userData(String id) async =>
      (await db.collection('users').doc(id).get()).data()!;

  Future<void> addBloodTest(String userId, DateTime? date) =>
      db.collection('users').doc(userId).collection('tests').add({
        'fileName': 'tahlil.pdf',
        'isBloodTest': true,
        if (date != null) 'bloodTestDate': Timestamp.fromDate(date),
      });

  test('ilk tarama: eski danışanlar "yok" işaretlenir, eksikler listelenir',
      () async {
    final DateTime now = DateTime.now();
    final DateTime old = now.subtract(const Duration(days: 60));
    await addUser('eski', name: 'Zeynep', surname: 'Kaya', createDate: old);
    await addUser('eski2', name: 'Ayşe', surname: 'Demir', createDate: old);
    await addUser('yeni', createDate: now.subtract(const Duration(days: 2)),
        present: false);
    await addUser('var', createDate: old, present: true);
    await addBloodTest('var', now.subtract(const Duration(days: 20)));
    await addUser('simge', name: 'Simge', surname: 'Erdoğan', createDate: old);
    await addUser('silinecek', createDate: old, removalRequested: true);
    await addUser('admin', role: 'admin', createDate: old);

    expect(await provider.runDailyScan(uid: admin, now: now), 2);

    final String today = DateFormatter.formatIsoDate(now);
    final AdminNotification digest = AdminNotification.fromDocument(await db
        .collection(AdminNotificationsProvider.collectionName)
        .doc(AdminNotification.missingBloodTestsId(today))
        .get())!;
    expect(digest.customers.map((c) => c.name),
        ['Ayşe Demir', 'Zeynep Kaya']);
    expect(digest.isDueAt(now), isTrue);

    expect((await userData('eski'))['isBloodTestPresent'], isFalse);
    expect((await userData('simge'))['isBloodTestPresent'], isFalse);
    expect((await userData('admin')).containsKey('isBloodTestPresent'),
        isFalse);
    expect((await userData('var'))['isBloodTestPresent'], isTrue);

    final Map<String, dynamic> state =
        (await db.collection('adminState').doc('bloodTests').get()).data()!;
    expect(state['lastScanDay'], today);
    expect(state['lastScanBy'], admin);
    expect(state['presenceInitializedAt'], isA<Timestamp>());
    expect(state['presenceFromDocumentsAt'], isA<Timestamp>());
  });

  test('ilk taramada elle verilmiş işaretler bir kez dosyalara göre düzeltilir',
      () async {
    final DateTime now = DateTime.now();
    final DateTime old = now.subtract(const Duration(days: 60));
    await addUser('elle', name: 'Elle', surname: 'Evet', createDate: old,
        present: true);
    await addUser('dosyali', createDate: old, present: false);
    await addBloodTest('dosyali', now.subtract(const Duration(days: 10)));
    await addUser('dogru', createDate: old, present: true);
    await addBloodTest('dogru', now.subtract(const Duration(days: 40)));
    await addUser('diger', createDate: old, present: true);
    await db.collection('users').doc('diger').collection('tests').add({
      'fileName': 'diyet.pdf',
      'isBloodTest': false,
    });

    expect(await provider.runDailyScan(uid: admin, now: now), 2);
    expect((await userData('elle'))['isBloodTestPresent'], isFalse);
    expect((await userData('diger'))['isBloodTestPresent'], isFalse);
    expect((await userData('dosyali'))['isBloodTestPresent'], isTrue);
    expect((await userData('dogru'))['isBloodTestPresent'], isTrue);

    await db.collection('users').doc('elle').update({'isBloodTestPresent': true});
    await provider.runDailyScan(
        uid: admin, now: now.add(const Duration(days: 1)));
    expect((await userData('elle'))['isBloodTestPresent'], isTrue);
  });

  test('aynı gün ikinci tarama yapılmaz', () async {
    final DateTime now = DateTime.now();
    await addUser('eski',
        createDate: now.subtract(const Duration(days: 30)));
    expect(await provider.runDailyScan(uid: admin, now: now), 1);
    expect(await provider.runDailyScan(uid: admin, now: now), isNull);
    expect(
        await provider.runDailyScan(uid: admin, now: now, force: true), 1);
  });

  test('eksik yoksa liste yazılmaz', () async {
    final DateTime now = DateTime.now();
    await addUser('var',
        createDate: now.subtract(const Duration(days: 30)), present: true);
    await addBloodTest('var', now.subtract(const Duration(days: 5)));
    expect(await provider.runDailyScan(uid: admin, now: now), 0);
    expect(
        (await db.collection(AdminNotificationsProvider.collectionName).get())
            .docs,
        isEmpty);
  });

  test('sonraki taramalarda alansız açılan yeni danışan da işaretlenir',
      () async {
    final DateTime now = DateTime.now();
    await addUser('eski', createDate: now.subtract(const Duration(days: 30)),
        present: true);
    await addBloodTest('eski', now.subtract(const Duration(days: 5)));
    await provider.runDailyScan(uid: admin, now: now);

    await addUser('alansiz', createDate: now);
    await provider.runDailyScan(
        uid: admin, now: now.add(const Duration(days: 1)));
    expect((await userData('alansiz'))['isBloodTestPresent'], isFalse);

    await provider.runDailyScan(
        uid: admin, now: now.add(const Duration(days: 8)));
    final String day =
        DateFormatter.formatIsoDate(now.add(const Duration(days: 8)));
    final AdminNotification digest = AdminNotification.fromDocument(await db
        .collection(AdminNotificationsProvider.collectionName)
        .doc(AdminNotification.missingBloodTestsId(day))
        .get())!;
    expect(digest.customers.map((c) => c.userId), ['alansiz']);
  });

  test('yeni günün listesi gelince eskisi okunmuş sayılır', () async {
    final DateTime now = DateTime.now();
    await addUser('eski', createDate: now.subtract(const Duration(days: 30)));
    await provider.runDailyScan(uid: admin, now: now);
    final DateTime tomorrow = now.add(const Duration(days: 1));
    await provider.runDailyScan(uid: admin, now: tomorrow);

    Future<AdminNotification> digestOf(DateTime day) async =>
        AdminNotification.fromDocument(await db
            .collection(AdminNotificationsProvider.collectionName)
            .doc(AdminNotification.missingBloodTestsId(
                DateFormatter.formatIsoDate(day)))
            .get())!;
    expect((await digestOf(now)).superseded, isTrue);
    expect((await digestOf(tomorrow)).superseded, isFalse);
  });

  test('kan tahlili işareti kaydedilir', () async {
    await addUser('d1', createDate: DateTime(2026));
    await provider.setBloodTestPresent(userId: 'd1', present: true);
    expect((await userData('d1'))['isBloodTestPresent'], isTrue);
    await provider.setBloodTestPresent(userId: 'd1', present: false);
    expect((await userData('d1'))['isBloodTestPresent'], isFalse);
  });

  test('önizleme hiçbir şey yazmadan listeyi ve bekleyenleri gösterir',
      () async {
    final DateTime now = DateTime.now();
    final DateTime old = now.subtract(const Duration(days: 60));
    final DateTime fresh = now.subtract(const Duration(days: 2));
    await addUser('eski', name: 'Zeynep', surname: 'Kaya', createDate: old);
    await addUser('hayir',
        name: 'Ayşe', surname: 'Demir', createDate: old, present: false);
    await addUser('yeni',
        name: 'Can', surname: 'Ak', createDate: fresh, present: false);
    await addUser('var', createDate: old, present: true);
    await addUser('silinecek', createDate: old, removalRequested: true);
    await addUser('admin', role: 'admin', createDate: old);

    final BloodTestScanPreview today = await provider.previewScan(at: now);
    expect(today.missing.map((c) => c.userId), ['hayir', 'eski']);
    expect(today.waiting.map((w) => w.customer.userId), ['yeni']);
    expect(today.waiting.single.listedFrom,
        fresh.add(BloodTestProvider.uploadGracePeriod));
    expect(today.unrecordedCount, 2);

    final BloodTestScanPreview later = await provider.previewScan(
        at: now.add(const Duration(days: 8)));
    expect(later.missing.map((c) => c.name),
        ['Ayşe Demir', 'Can Ak', 'Zeynep Kaya']);
    expect(later.waiting, isEmpty);

    expect((await userData('eski')).containsKey('isBloodTestPresent'),
        isFalse);
    expect(
        (await db.collection(AdminNotificationsProvider.collectionName).get())
            .docs,
        isEmpty);
    expect((await provider.fetchScanState()).hasScanned, isFalse);
  });

  test('son tarama bilgisi okunur', () async {
    final DateTime now = DateTime.now();
    await addUser('eski', createDate: now.subtract(const Duration(days: 30)));
    await provider.runDailyScan(uid: admin, now: now);

    final BloodTestScanState state = await provider.fetchScanState();
    expect(state.hasScanned, isTrue);
    expect(state.lastScanDay, DateFormatter.formatIsoDate(now));
    expect(state.lastScanBy, admin);
    expect(state.lastScanAt, isNotNull);
    expect(state.presenceInitializedAt, isNotNull);
  });

  test('bütün danışanların kan tahlili durumu, gecikmişler en üstte', () async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    Future<void> addTest(String userId, DateTime date) => db
        .collection('users')
        .doc(userId)
        .collection('tests')
        .add({
          'fileName': 'tahlil.pdf',
          'isBloodTest': true,
          'bloodTestDate': Timestamp.fromDate(date),
        });

    await addUser('ilk', name: 'İlk', surname: 'Eksik',
        createDate: now.subtract(const Duration(days: 20)));
    await addUser('eski', name: 'Eski', surname: 'Tahlil',
        createDate: now.subtract(const Duration(days: 300)), present: true);
    await addTest('eski', DateTime(today.year, today.month - 5, today.day));
    await addTest('eski', DateTime(today.year, today.month - 4, today.day));
    await addUser('yeni', name: 'Yeni', surname: 'Danışan',
        createDate: now.subtract(const Duration(days: 2)), present: false);
    await addUser('guncel', name: 'Güncel', surname: 'Danışan',
        createDate: now.subtract(const Duration(days: 300)), present: true);
    await addTest('guncel', today.subtract(const Duration(days: 5)));
    await addUser('tarihsiz', name: 'Tarihsiz', surname: 'Danışan',
        createDate: now.subtract(const Duration(days: 300)), present: true);
    await addBloodTest('tarihsiz', null);
    await addUser('elle', name: 'Elle', surname: 'Evet',
        createDate: now.subtract(const Duration(days: 300)), present: true);
    await addUser('silinecek', createDate: now, removalRequested: true);
    await addUser('admin', role: 'admin', createDate: now);

    final List<int> progress = [];
    final BloodTestReport report = await provider.checkAllCustomers(
      now: now,
      onProgress: (done, total) => progress.add(done),
    );
    expect(report.statuses.map((s) => s.customer.userId),
        ['elle', 'eski', 'ilk', 'yeni', 'tarihsiz', 'guncel']);
    expect(report.statuses.map((s) => s.kind), [
      BloodTestStatusKind.missingFirst,
      BloodTestStatusKind.expired,
      BloodTestStatusKind.missingFirst,
      BloodTestStatusKind.waitingFirst,
      BloodTestStatusKind.undated,
      BloodTestStatusKind.upToDate,
    ]);
    expect(report.statuses[1].lastTestDate,
        DateTime(today.year, today.month - 4, today.day));
    expect(report.countOf(BloodTestStatusGroup.overdue), 3);
    expect(progress.last, 6);
    expect(provider.lastReport, same(report));
  });
}
