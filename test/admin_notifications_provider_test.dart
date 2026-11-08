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

  Future<BloodTestReminderSync> sync(
    Map<DateTime, bool> testDates, {
    String userId = customer,
    String userName = 'Ayşe Yılmaz',
  }) =>
      provider.syncBloodTestReminders(
        userId: userId,
        userName: userName,
        testDates: testDates,
      );

  Future<List<String>> ids() async =>
      [
        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in (await notifications().get()).docs)
          doc.id,
      ];

  String reminderId(DateTime testDate, BloodTestReminderStage stage) =>
      AdminNotification.bloodTestReminderId(customer, testDate, stage);

  group('kan tahlili hatırlatmaları', () {
    test('iki hatırlatma kurulur', () async {
      final DateTime testDate = daysAgo(10);
      await sync({testDate: true});

      for (final BloodTestReminderStage stage
          in BloodTestReminderStage.values) {
        final Map<String, dynamic>? data =
            await docData(reminderId(testDate, stage));
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

    test('saatli tarih güne yuvarlanır', () async {
      final DateTime testDate = daysAgo(10);
      final BloodTestReminderSync result = await sync({
        testDate.add(const Duration(hours: 15, minutes: 30)): true,
      });
      expect(result.remindFor, testDate);
      expect(await ids(), hasLength(2));
      expect(await docData(reminderId(testDate, BloodTestReminderStage.dueDay)),
          isNotNull);
    });

    test('aynı tarihin tahlili yeniden yüklenince hatırlatma çoğalmaz, '
        'okundu bilgisi korunur', () async {
      final DateTime testDate = daysAgo(10);
      final String id = reminderId(testDate, BloodTestReminderStage.dueDay);
      await sync({testDate: true});
      await notifications().doc(id).update({'readBy.$admin': Timestamp.now()});

      await sync({testDate: true});

      final Map<String, dynamic>? data = await docData(id);
      expect((data![AdminNotification.readByField] as Map).keys, [admin]);
      expect(await ids(), hasLength(2));
    });

    test('hatırlatmalar bir kez yazılır; yazılan sayı döner', () async {
      final DateTime testDate = daysAgo(10);
      expect((await sync({testDate: true})).written, 2);
      expect((await sync({testDate: true})).written, 0);
    });

    test('yeni tahlil eski tahlilin bekleyen hatırlatmalarını siler, '
        'düşmüş olanlara dokunmaz', () async {
      final DateTime oldest = daysAgo(200);
      final DateTime oldTest = daysAgo(40);
      await sync({oldest: true});
      final String fired =
          reminderId(oldest, BloodTestReminderStage.dueDay);
      expect(await ids(), [fired]);
      await sync({oldest: true, oldTest: true});

      final DateTime newTest = daysAgo(2);
      final BloodTestReminderSync result =
          await sync({oldest: true, oldTest: true, newTest: true});

      expect(result.latestTestDate, newTest);
      expect(result.remindFor, newTest);
      expect(result.removed, 2);
      final List<String> left = await ids();
      expect(left, contains(fired));
      for (final BloodTestReminderStage stage
          in BloodTestReminderStage.values) {
        expect(left, contains(reminderId(newTest, stage)));
        expect(left, isNot(contains(reminderId(oldTest, stage))));
      }
    });

    test('dosyası kalmayan tarihin hatırlatmaları, düşmüş olsa da silinir',
        () async {
      final DateTime wrongDate = daysAgo(200);
      await sync({wrongDate: true});
      expect(await ids(), [reminderId(wrongDate, BloodTestReminderStage.dueDay)]);

      final DateTime corrected = daysAgo(30);
      final BloodTestReminderSync result = await sync({corrected: true});

      expect(result.removed, 1);
      expect(await ids(), unorderedEquals([
        for (final BloodTestReminderStage stage
            in BloodTestReminderStage.values)
          reminderId(corrected, stage),
      ]));
    });

    test('en yeni tahlil kaldırılınca önceki tahlilin hatırlatmaları '
        'yeniden kurulur', () async {
      final DateTime previous = daysAgo(40);
      final DateTime wrong = daysAgo(5);
      await sync({previous: true});
      await sync({previous: true, wrong: true});
      expect(await docData(reminderId(previous, BloodTestReminderStage.dueDay)),
          isNull);

      final BloodTestReminderSync result = await sync({previous: true});

      expect(result.remindFor, previous);
      expect(result.written, 2);
      expect(await ids(), unorderedEquals([
        for (final BloodTestReminderStage stage
            in BloodTestReminderStage.values)
          reminderId(previous, stage),
      ]));
    });

    test('en yeni tahlilde hatırlatma istenmezse bekleyenler silinir, '
        'düşmüş olan kalır', () async {
      final DateTime expired = daysAgo(120);
      final DateTime latest = daysAgo(10);
      await sync({expired: true});
      await sync({expired: true, latest: true});

      final BloodTestReminderSync result =
          await sync({expired: true, latest: false});

      expect(result.latestTestDate, latest);
      expect(result.remindFor, isNull);
      expect(result.written, 0);
      expect(await ids(), [reminderId(expired, BloodTestReminderStage.dueDay)]);
    });

    test('aynı tarihin dosyalarından biri hatırlatma isterse kurulur', () async {
      final DateTime testDate = daysAgo(10);
      final BloodTestReminderSync result = await sync({
        testDate: false,
        testDate.add(const Duration(hours: 1)): true,
      });
      expect(result.remindFor, testDate);
      expect(result.written, 2);
    });

    test('kan tahlili kalmayınca hepsi silinir', () async {
      await sync({daysAgo(10): true});
      final BloodTestReminderSync result = await sync({});
      expect(result.hasBloodTests, isFalse);
      expect(result.removed, 2);
      expect(await ids(), isEmpty);
    });

    test('başka danışanın ve simülatörün hatırlatmalarına dokunmaz', () async {
      await sync({daysAgo(10): true}, userId: 'baska', userName: 'Can Ak');
      await provider.addTestNotification(
        fireAt: DateTime.now().add(const Duration(minutes: 5)),
        kind: AdminTestNotificationKind.bloodTestDueDay,
        customers: const [
          NotificationCustomer(userId: customer, name: 'Ayşe Yılmaz'),
        ],
      );

      await sync({});

      expect(await ids(), hasLength(3));
    });

    test('silinen danışanın yalnızca bekleyen hatırlatmaları silinir', () async {
      await sync({daysAgo(10): true});
      await notifications().doc('fired').set({
        AdminNotification.typeField:
            AdminNotificationType.bloodTestReminder.value,
        AdminNotification.fireAtField: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(hours: 1))),
        AdminNotification.userIdField: customer,
      });

      await provider.removePendingNotificationsOfUser(customer);

      expect(await ids(), ['fired']);
    });
  });

  test('danışanın hatırlatmaları zamanına göre listelenir', () async {
    final DateTime testDate = daysAgo(10);
    await sync({testDate: true});
    await sync({testDate: true}, userId: 'baska', userName: 'Can Ak');

    final List<AdminNotification> reminders =
        await provider.remindersOf(customer).first;
    expect(reminders.map((n) => n.stage), [
      BloodTestReminderStage.dayBefore,
      BloodTestReminderStage.dueDay,
    ]);
    expect(reminders.every((n) => n.userId == customer), isTrue);
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

    test('çok sayıda ileri tarihli hatırlatma düşmüş bildirimleri gizlemez, '
        'yalnızca en yakınları kurulur', () async {
      final DateTime now = DateTime.now();
      await add('dusmus', now.subtract(const Duration(minutes: 1)));
      const int future = AdminNotificationsProvider.listLimit + 10;
      for (int i = 0; i < future; i++) {
        await add('ileri$i', now.add(Duration(days: i + 1)));
      }
      provider.start(admin, owner: home);
      await pumpEventQueue();

      expect(provider.notifications.map((n) => n.id), ['dusmus']);
      expect(provider.unreadCount, 1);
      expect(scheduler.scheduled.keys.toSet(), {
        for (int i = 0; i < AdminNotificationDelivery.maxScheduled; i++)
          'ileri$i',
      });
    });

    test('okundu bilgisi hemen yerelde görünür', () async {
      await add('a', DateTime.now().subtract(const Duration(minutes: 1)));
      provider.start(admin, owner: home);
      await pumpEventQueue();
      await provider.markRead('a');
      final Map<String, dynamic>? data = await docData('a');
      expect((data![AdminNotification.readByField] as Map)[admin],
          isA<Timestamp>());
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

    test('denemede verilen tahlil tarihi hatırlatma metnine yazılır',
        () async {
      final String? id = await provider.addTestNotification(
        fireAt: DateTime.now().add(const Duration(minutes: 2)),
        kind: AdminTestNotificationKind.bloodTestDueDay,
        customers: const [
          NotificationCustomer(userId: customer, name: 'Ayşe Yılmaz'),
        ],
        testDate: DateTime(2026, 8, 5, 15, 30),
      );
      final AdminNotification n =
          AdminNotification.fromDocument(await notifications().doc(id).get())!;
      expect(n.testDate, DateTime(2026, 8, 5));
      expect(n.body, contains('05.08.2026'));
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

    test('oturum kapanınca kurulu sistem bildirimleri cihazdan kalkar, '
        'açıkken bırakılınca kalır', () async {
      String? signedIn = admin;
      final AdminNotificationsProvider session = AdminNotificationsProvider(
        db: db,
        currentUid: () => signedIn,
        delivery: AdminNotificationDelivery(
          local: scheduler,
          banner: ({required title, required body, required data}) {},
          osShowsInForeground: false,
        ),
      );
      addTearDown(session.dispose);
      await add('yarin', DateTime.now().add(const Duration(days: 1)));

      session.start(admin, owner: home);
      await pumpEventQueue();
      expect(scheduler.scheduled.keys, ['yarin']);
      session.release(home);
      await pumpEventQueue();
      expect(scheduler.scheduled.keys, ['yarin']);

      session.start(admin, owner: home);
      await pumpEventQueue();
      signedIn = null;
      session.release(home);
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
