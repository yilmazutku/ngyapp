import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/providers/admin_notifications_provider.dart';
import 'package:ngy_app/services/admin_notification_delivery.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduler implements AdminNotificationScheduler {
  final Map<String, DateTime> scheduled = {};

  @override
  bool get isSupported => true;

  @override
  Future<bool> schedule({
    required String docId,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    scheduled[docId] = fireAt;
    return true;
  }

  @override
  Future<void> cancel(String docId) async => scheduled.remove(docId);

  @override
  Future<Set<String>> pendingDocIds() async => scheduled.keys.toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const String admin = 'admin-1';
  const String customer = 'danisan-1';

  late FakeFirebaseFirestore db;
  late _FakeScheduler scheduler;
  late List<String> banners;
  late AdminNotificationsProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    scheduler = _FakeScheduler();
    banners = [];
    provider = AdminNotificationsProvider(
      db: db,
      currentUid: () => admin,
      delivery: AdminNotificationDelivery(
        local: scheduler,
        banner: ({required title, required body, required data}) =>
            banners.add(title),
        osShowsInForeground: false,
      ),
    );
  });

  tearDown(() => provider.dispose());

  CollectionReference<Map<String, dynamic>> notifications() =>
      db.collection(AdminNotificationsProvider.collectionName);

  Future<Map<String, dynamic>?> docData(String id) async =>
      (await notifications().doc(id).get()).data();

  DateTime daysAgo(int days) {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day - days);
  }

  group('kan tahlili hatırlatmaları', () {
    test('iki hatırlatma kurulur', () async {
      final DateTime testDate = daysAgo(10);
      await provider.addBloodTestReminders(
        userId: customer,
        userName: 'Ayşe Yılmaz',
        testDate: testDate,
      );

      for (final BloodTestReminderStage stage
          in BloodTestReminderStage.values) {
        final Map<String, dynamic>? data = await docData(
            AdminNotification.bloodTestReminderId(customer, testDate, stage));
        expect(data, isNotNull, reason: '$stage');
        expect(data![AdminNotification.typeField],
            AdminNotificationType.bloodTestReminder.value);
        expect(data[AdminNotification.userNameField], 'Ayşe Yılmaz');
        expect(data[AdminNotification.stageField], stage.value);
        expect((data[AdminNotification.fireAtField] as Timestamp).toDate(),
            BloodTestReminderSchedule.fireTime(testDate, stage));
        expect(data[AdminNotification.createdByField], admin);
      }
    });

    test('aynı tarihin tahlili yeniden yüklenince hatırlatma çoğalmaz, '
        'okundu bilgisi korunur', () async {
      final DateTime testDate = daysAgo(10);
      final String id = AdminNotification.bloodTestReminderId(
          customer, testDate, BloodTestReminderStage.dueDay);
      await provider.addBloodTestReminders(
          userId: customer, userName: 'Ayşe', testDate: testDate);
      await notifications().doc(id).update({'readBy.$admin': Timestamp.now()});

      await provider.addBloodTestReminders(
          userId: customer, userName: 'Ayşe', testDate: testDate);

      final Map<String, dynamic>? data = await docData(id);
      expect((data![AdminNotification.readByField] as Map).keys, [admin]);
      expect((await notifications().get()).docs, hasLength(2));
    });

    test('yeni tahlil eski tahlilin bekleyen hatırlatmalarını siler, '
        'düşmüş olanlara dokunmaz', () async {
      final DateTime oldTest = daysAgo(40);
      await provider.addBloodTestReminders(
          userId: customer, userName: 'Ayşe', testDate: oldTest);
      await notifications().doc('fired').set({
        AdminNotification.typeField:
            AdminNotificationType.bloodTestReminder.value,
        AdminNotification.fireAtField:
            Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
        AdminNotification.userIdField: customer,
        AdminNotification.testDateField: Timestamp.fromDate(daysAgo(200)),
      });

      final DateTime newTest = daysAgo(2);
      await provider.addBloodTestReminders(
          userId: customer, userName: 'Ayşe', testDate: newTest);

      final List<String> ids =
          (await notifications().get()).docs.map((d) => d.id).toList();
      expect(ids, contains('fired'));
      for (final BloodTestReminderStage stage
          in BloodTestReminderStage.values) {
        expect(ids,
            contains(AdminNotification.bloodTestReminderId(customer, newTest, stage)));
        expect(ids,
            isNot(contains(AdminNotification.bloodTestReminderId(customer, oldTest, stage))));
      }
    });

    test('tahlilin hatırlatmaları silinir', () async {
      final DateTime testDate = daysAgo(10);
      await provider.addBloodTestReminders(
          userId: customer, userName: 'Ayşe', testDate: testDate);
      await provider.removeBloodTestReminders(
          userId: customer, testDate: testDate);
      expect((await notifications().get()).docs, isEmpty);
    });

    test('silinen danışanın yalnızca bekleyen hatırlatmaları silinir', () async {
      await provider.addBloodTestReminders(
          userId: customer, userName: 'Ayşe', testDate: daysAgo(10));
      await notifications().doc('fired').set({
        AdminNotification.typeField:
            AdminNotificationType.bloodTestReminder.value,
        AdminNotification.fireAtField: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(hours: 1))),
        AdminNotification.userIdField: customer,
      });

      await provider.removePendingNotificationsOfUser(customer);

      expect((await notifications().get()).docs.map((d) => d.id), ['fired']);
    });
  });

  test('günün eksik tahlil listesi yeniden yazılınca okundu bilgisi kalır',
      () async {
    const String day = '2026-11-06';
    final DateTime at = DateTime(2026, 11, 6, 9, 30);
    const List<NotificationCustomer> first = [
      NotificationCustomer(userId: 'u1', name: 'Ayşe Yılmaz'),
    ];
    await provider.saveMissingBloodTestList(day: day, customers: first, at: at);
    final String id = AdminNotification.missingBloodTestsId(day);
    await notifications().doc(id).update({'readBy.$admin': Timestamp.now()});

    await provider.saveMissingBloodTestList(
      day: day,
      customers: const [
        NotificationCustomer(userId: 'u1', name: 'Ayşe Yılmaz'),
        NotificationCustomer(userId: 'u2', name: 'Can Ak'),
      ],
      at: at,
    );

    final AdminNotification n =
        AdminNotification.fromDocument(await notifications().doc(id).get())!;
    expect(n.type, AdminNotificationType.missingBloodTests);
    expect(n.title, 'Kan tahlili eksik danışanlar (2)');
    expect(n.customers.map((c) => c.name), ['Ayşe Yılmaz', 'Can Ak']);
    expect(n.isReadBy(admin), isTrue);
  });

  group('zil listesi', () {
    final Object home = Object();

    Future<void> add(String id, DateTime fireAt, {bool read = false}) =>
        notifications().doc(id).set({
          AdminNotification.typeField:
              AdminNotificationType.bloodTestReminder.value,
          AdminNotification.titleField: id,
          AdminNotification.bodyField: '',
          AdminNotification.fireAtField: Timestamp.fromDate(fireAt),
          AdminNotification.readByField: {
            if (read) admin: Timestamp.now(),
          },
        });

    test('yalnızca düşmüş bildirimler, okunmamış sayısı ve okundu işareti',
        () async {
      final DateTime now = DateTime.now();
      await add('eski-okunmus', now.subtract(const Duration(days: 3)),
          read: true);
      await add('yeni', now.subtract(const Duration(minutes: 5)));
      await add('yarin', now.add(const Duration(days: 1)));
      await notifications().doc('bozuk').set({'type': 'bilinmeyen'});

      provider.start(admin, owner: home);
      await pumpEventQueue();

      expect(provider.notifications.map((n) => n.id),
          ['yeni', 'eski-okunmus']);
      expect(provider.unreadCount, 1);
      expect(scheduler.scheduled.keys, ['yarin']);
      expect(banners, ['yeni']);

      await provider.markRead('yeni');
      await pumpEventQueue();
      expect(provider.unreadCount, 0);
    });

    test('tümünü okundu say', () async {
      final DateTime now = DateTime.now();
      await add('a', now.subtract(const Duration(hours: 1)));
      await add('b', now.subtract(const Duration(hours: 2)));
      provider.start(admin, owner: home);
      await pumpEventQueue();
      expect(provider.unreadCount, 2);

      await provider.markAllRead();
      await pumpEventQueue();
      expect(provider.unreadCount, 0);
    });

    test('yerine yenisi gelen eksik tahlil listesi okunmuş sayılır', () async {
      final DateTime now = DateTime.now();
      const List<NotificationCustomer> customers = [
        NotificationCustomer(userId: 'u1', name: 'Ayşe Yılmaz'),
      ];
      await provider.saveMissingBloodTestList(
          day: 'dun',
          customers: customers,
          at: now.subtract(const Duration(days: 1)));
      await provider.saveMissingBloodTestList(
          day: 'bugun', customers: customers, at: now);
      provider.start(admin, owner: home);
      await pumpEventQueue();
      expect(provider.unreadCount, 2);

      await provider.supersedeMissingBloodTestLists(
          exceptId: AdminNotification.missingBloodTestsId('bugun'));
      await pumpEventQueue();
      expect(provider.unreadCount, 1);
      expect(
          provider.isRead(provider.notifications
              .firstWhere((n) => n.id.endsWith('dun'))),
          isTrue);
    });

    test('eski bildirimler sayfa sayfa yüklenir', () async {
      final DateTime now = DateTime.now();
      const int total = AdminNotificationsProvider.listLimit + 5;
      for (int i = 0; i < total; i++) {
        await add('n$i', now.subtract(Duration(hours: i + 1)));
      }
      provider.start(admin, owner: home);
      await pumpEventQueue();
      expect(provider.notifications, hasLength(AdminNotificationsProvider.listLimit));
      expect(provider.canLoadOlder, isTrue);

      await provider.loadOlder();
      expect(provider.notifications, hasLength(total));
      expect(provider.notifications.last.id, 'n${total - 1}');
      expect(provider.canLoadOlder, isFalse);

      await provider.markRead('n${total - 1}');
      expect(provider.isRead(provider.notifications.last), isTrue);
    });

    test('deneme bildirimi yalnızca kuran admine görünür ve silinebilir',
        () async {
      final DateTime now = DateTime.now();
      await provider.addTestNotification(
          fireAt: now.subtract(const Duration(seconds: 1)));
      provider.start(admin, owner: home);
      await pumpEventQueue();
      expect(provider.notifications.map((n) => n.type),
          [AdminNotificationType.test]);
      expect(provider.unreadCount, 1);

      final AdminNotificationsProvider other = AdminNotificationsProvider(
        db: db,
        currentUid: () => 'admin-2',
        delivery: AdminNotificationDelivery(
          local: _FakeScheduler(),
          banner: ({required title, required body, required data}) {},
          osShowsInForeground: false,
        ),
      );
      addTearDown(other.dispose);
      other.start('admin-2', owner: home);
      await pumpEventQueue();
      expect(other.notifications, isEmpty);

      expect(await provider.removeTestNotifications(), 1);
      await pumpEventQueue();
      expect(provider.notifications, isEmpty);
    });

    test('simülatör türleri gerçekleri gibi yazılır, yalnızca denemeler silinir',
        () async {
      final DateTime now = DateTime.now();
      const NotificationCustomer ayse =
          NotificationCustomer(userId: customer, name: 'Ayşe Yılmaz');
      const NotificationCustomer can =
          NotificationCustomer(userId: 'u2', name: 'Can Ak');
      await provider.saveMissingBloodTestList(
        day: '2026-11-05',
        customers: const [can],
        at: now.subtract(const Duration(minutes: 5)),
      );
      await provider.addTestNotification(
        fireAt: now.subtract(const Duration(seconds: 3)),
        kind: AdminTestNotificationKind.bloodTestDueDay,
        customers: const [ayse],
      );
      await provider.addTestNotification(
        fireAt: now.subtract(const Duration(seconds: 2)),
        kind: AdminTestNotificationKind.bloodTestDayBefore,
        customers: const [ayse],
      );
      await provider.addTestNotification(
        fireAt: now.subtract(const Duration(seconds: 1)),
        kind: AdminTestNotificationKind.missingBloodTests,
        customers: const [ayse, can],
      );

      provider.start(admin, owner: home);
      await pumpEventQueue();
      final List<AdminNotification> list = provider.notifications;
      expect(list.map((n) => n.type), [
        AdminNotificationType.missingBloodTests,
        AdminNotificationType.bloodTestReminder,
        AdminNotificationType.bloodTestReminder,
        AdminNotificationType.missingBloodTests,
      ]);
      expect(list.map((n) => n.isTest), [true, true, true, false]);
      expect(list.first.customers.map((c) => c.name), ['Ayşe Yılmaz', 'Can Ak']);
      expect(list.first.title, 'Kan tahlili eksik danışanlar (2)');
      expect(list[1].stage, BloodTestReminderStage.dayBefore);
      expect(list[1].title, 'Kan tahlili yarın 3 ayı dolduruyor');
      expect(list[2].stage, BloodTestReminderStage.dueDay);
      expect(list[2].title, 'Kan tahlilinin üzerinden 3 ay geçti');
      expect(list[2].userId, customer);
      expect(list[2].body, startsWith('Ayşe Yılmaz · '));
      expect(provider.unreadCount, 4);

      expect(await provider.removeTestNotifications(), 3);
      await pumpEventQueue();
      expect(provider.notifications.map((n) => n.isTest), [false]);
    });

    test('kan tahlili denemesi danışansız kurulmaz', () async {
      await expectLater(
        provider.addTestNotification(
          fireAt: DateTime.now(),
          kind: AdminTestNotificationKind.bloodTestDueDay,
        ),
        throwsArgumentError,
      );
      expect((await notifications().get()).docs, isEmpty);
    });

    test('silinen deneme bildiriminin kurulu sistem bildirimi iptal edilir',
        () async {
      provider.start(admin, owner: home);
      await pumpEventQueue();
      final String? id = await provider.addTestNotification(
          fireAt: DateTime.now().add(const Duration(minutes: 5)));
      await pumpEventQueue();
      expect(scheduler.scheduled.keys, [id]);

      await provider.removeTestNotifications();
      await pumpEventQueue();
      expect(scheduler.scheduled, isEmpty);
    });

    test('dinlemeyi yalnızca başlatan bırakabilir', () async {
      await add('a', DateTime.now().subtract(const Duration(hours: 1)));
      final Object oldHome = Object();
      final Object newHome = Object();
      provider.start(admin, owner: oldHome);
      provider.start(admin, owner: newHome);
      await pumpEventQueue();

      provider.release(oldHome);
      await pumpEventQueue();
      expect(provider.notifications, hasLength(1));

      provider.release(newHome);
      expect(provider.notifications, isEmpty);
    });
  });
}
