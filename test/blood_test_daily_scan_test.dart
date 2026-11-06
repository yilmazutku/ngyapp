import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/admin_notification.dart';
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

  test('ilk tarama: eski danışanlar "yok" işaretlenir, eksikler listelenir',
      () async {
    final DateTime now = DateTime.now();
    final DateTime old = now.subtract(const Duration(days: 60));
    await addUser('eski', name: 'Zeynep', surname: 'Kaya', createDate: old);
    await addUser('eski2', name: 'Ayşe', surname: 'Demir', createDate: old);
    await addUser('yeni', createDate: now.subtract(const Duration(days: 2)),
        present: false);
    await addUser('var', createDate: old, present: true);
    await addUser('simge', name: 'Simge', surname: 'Erdoğan', createDate: old);
    await addUser('silinecek', createDate: old, removalRequested: true);
    await addUser('admin', role: 'admin', createDate: old);

    expect(await provider.runDailyScan(uid: admin, now: now), isTrue);

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
  });

  test('aynı gün ikinci tarama yapılmaz', () async {
    final DateTime now = DateTime.now();
    await addUser('eski',
        createDate: now.subtract(const Duration(days: 30)));
    expect(await provider.runDailyScan(uid: admin, now: now), isTrue);
    expect(await provider.runDailyScan(uid: admin, now: now), isFalse);
  });

  test('eksik yoksa liste yazılmaz', () async {
    final DateTime now = DateTime.now();
    await addUser('var',
        createDate: now.subtract(const Duration(days: 30)), present: true);
    expect(await provider.runDailyScan(uid: admin, now: now), isTrue);
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

  test('Detay sekmesindeki seçim kaydedilir ve oturumda hatırlanır', () async {
    await addUser('d1', createDate: DateTime(2026));
    await provider.setBloodTestPresent(userId: 'd1', present: true);
    expect((await userData('d1'))['isBloodTestPresent'], isTrue);
    expect(provider.savedPresence('d1'), isTrue);
    expect(provider.savedPresence('d2'), isNull);
  });
}
