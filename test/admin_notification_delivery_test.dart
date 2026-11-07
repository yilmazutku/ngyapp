import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/admin_notification.dart';
import 'package:ngy_app/services/admin_notification_delivery.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduler implements AdminNotificationScheduler {
  _FakeScheduler({this.isSupported = true});

  @override
  final bool isSupported;

  final Map<String, DateTime> scheduled = {};

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

class _GatedScheduler extends _FakeScheduler {
  final Completer<void> gate = Completer<void>();

  @override
  Future<bool> schedule({
    required String docId,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    await gate.future;
    return super.schedule(
      docId: docId,
      title: title,
      body: body,
      fireAt: fireAt,
    );
  }
}

void main() {
  const String uid = 'admin-1';
  final DateTime now = DateTime(2026, 11, 6, 9, 0, 5);

  late _FakeScheduler scheduler;
  late List<String> banners;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    scheduler = _FakeScheduler();
    banners = [];
  });

  AdminNotificationDelivery delivery({required bool android}) =>
      AdminNotificationDelivery(
        local: scheduler,
        banner: ({required title, required body, required data}) =>
            banners.add(title),
        osShowsInForeground: android,
      );

  AdminNotification notification(String id, DateTime fireAt,
          {bool read = false}) =>
      AdminNotification(
        id: id,
        type: AdminNotificationType.bloodTestReminder,
        title: id,
        body: '',
        fireAt: fireAt,
        readBy: read ? {uid: now} : const {},
      );

  for (final bool android in [false, true]) {
    final String platform = android ? 'Android' : 'iOS';

    test('$platform: kurulu bildirim uygulama öndeyken düşünce', () async {
      final AdminNotificationDelivery d = delivery(android: android);
      await d.attach(uid);
      final AdminNotification reminder =
          notification('r', now.add(const Duration(hours: 1)));
      await d.syncUpcoming([reminder]);
      expect(scheduler.scheduled.keys, ['r']);

      final AdminNotification due = notification('r', now);
      await d.announce(
        due: [due],
        now: now,
        inForeground: true,
        becameDueInForeground: {'r'},
      );
      expect(banners, android ? isEmpty : ['r']);

      await d.announce(
        due: [due],
        now: now,
        inForeground: true,
        becameDueInForeground: const {},
      );
      expect(banners, android ? isEmpty : ['r'], reason: 'iki kez duyurulmaz');
    });

    test('$platform: kurulu bildirim uygulama kapalıyken düştüyse şerit çıkmaz',
        () async {
      final AdminNotificationDelivery d = delivery(android: android);
      await d.attach(uid);
      await d.syncUpcoming(
          [notification('r', now.add(const Duration(minutes: 1)))]);

      await d.announce(
        due: [notification('r', now.add(const Duration(minutes: 1)))],
        now: now.add(const Duration(hours: 2)),
        inForeground: true,
        becameDueInForeground: const {},
      );
      expect(banners, isEmpty);
    });

    test('$platform: bu cihazda kurulmamış yeni bildirim açılınca duyurulur',
        () async {
      final AdminNotificationDelivery d = delivery(android: android);
      await d.attach(uid);
      await d.announce(
        due: [notification('liste', now)],
        now: now,
        inForeground: false,
        becameDueInForeground: const {},
      );
      expect(banners, isEmpty, reason: 'arka planda şerit gösterilmez');

      await d.announce(
        due: [notification('liste', now)],
        now: now.add(const Duration(minutes: 3)),
        inForeground: true,
        becameDueInForeground: const {},
      );
      expect(banners, ['liste']);
    });
  }

  test('okunmuş ya da 24 saatten eski bildirim duyurulmaz', () async {
    final AdminNotificationDelivery d = delivery(android: false);
    await d.attach(uid);
    await d.announce(
      due: [
        notification('okunmus', now, read: true),
        notification('eski', now.subtract(const Duration(hours: 25))),
      ],
      now: now,
      inForeground: true,
      becameDueInForeground: const {},
    );
    expect(banners, isEmpty);
  });

  test('aynı anda birden çok bildirim tek şeritte toplanır', () async {
    final AdminNotificationDelivery d = delivery(android: false);
    await d.attach(uid);
    await d.announce(
      due: [notification('a', now), notification('b', now)],
      now: now,
      inForeground: true,
      becameDueInForeground: const {},
    );
    expect(banners, ['2 yeni sistem bildirimi']);
  });

  test('duyurulanlar cihazda saklanır: yeniden açılışta tekrar çıkmaz',
      () async {
    final AdminNotificationDelivery first = delivery(android: false);
    await first.attach(uid);
    await first.announce(
      due: [notification('a', now)],
      now: now,
      inForeground: true,
      becameDueInForeground: const {},
    );
    expect(banners, ['a']);

    final AdminNotificationDelivery second = delivery(android: false);
    await second.attach(uid);
    await second.announce(
      due: [notification('a', now)],
      now: now,
      inForeground: true,
      becameDueInForeground: const {},
    );
    expect(banners, ['a']);
  });

  test('silinen bildirimin kurulumu kalkar', () async {
    final AdminNotificationDelivery d = delivery(android: true);
    await d.attach(uid);
    await d.syncUpcoming([
      notification('a', now.add(const Duration(days: 1))),
      notification('b', now.add(const Duration(days: 2))),
    ]);
    await d.syncUpcoming([notification('b', now.add(const Duration(days: 2)))]);
    expect(scheduler.scheduled.keys, ['b']);
  });

  test('yerel bildirimi olmayan platformda (Windows) yalnızca şerit', () async {
    scheduler = _FakeScheduler(isSupported: false);
    final AdminNotificationDelivery d = delivery(android: false);
    await d.attach(uid);
    await d.syncUpcoming([notification('a', now.add(const Duration(hours: 1)))]);
    expect(scheduler.scheduled, isEmpty);

    await d.announce(
      due: [notification('a', now)],
      now: now,
      inForeground: true,
      becameDueInForeground: {'a'},
    );
    expect(banners, ['a']);
  });

  test('art arda gelen eşitlemeler sırayla uygulanır, silinen bildirim kalmaz',
      () async {
    final _GatedScheduler gated = _GatedScheduler();
    final AdminNotificationDelivery d = AdminNotificationDelivery(
      local: gated,
      banner: ({required title, required body, required data}) {},
      osShowsInForeground: false,
    );
    await d.attach(uid);

    final Future<void> added =
        d.syncUpcoming([notification('r', now.add(const Duration(hours: 1)))]);
    final Future<void> removed = d.syncUpcoming(const []);
    await pumpEventQueue();
    gated.gate.complete();
    await Future.wait([added, removed]);

    expect(gated.scheduled, isEmpty);
  });

  test('düşmüş ama henüz gösterilmemiş bildirim iptal edilmez, silinen edilir',
      () async {
    final AdminNotificationDelivery d = delivery(android: true);
    await d.attach(uid);
    await d.syncUpcoming([
      notification('a', now.add(const Duration(minutes: 1))),
      notification('b', now.add(const Duration(minutes: 2))),
    ]);
    expect(scheduler.scheduled.keys.toSet(), {'a', 'b'});

    await d.syncUpcoming(const [], inFlight: {'a'});
    expect(scheduler.scheduled.keys, ['a'], reason: 'b silindi');
  });

  test('en fazla ${AdminNotificationDelivery.maxScheduled} yakın bildirim '
      'kurulur', () async {
    final AdminNotificationDelivery d = delivery(android: false);
    await d.attach(uid);
    final List<AdminNotification> upcoming = [
      for (int i = 0; i < AdminNotificationDelivery.maxScheduled + 5; i++)
        notification('n$i', now.add(Duration(hours: i + 1))),
    ];
    await d.syncUpcoming(upcoming);
    expect(scheduler.scheduled.keys.toSet(), {
      for (int i = 0; i < AdminNotificationDelivery.maxScheduled; i++) 'n$i',
    });

    await d.syncUpcoming(upcoming.skip(1).toList());
    expect(scheduler.scheduled.keys.toSet(), {
      for (int i = 1; i <= AdminNotificationDelivery.maxScheduled; i++) 'n$i',
    });
  });

  test('oturum kapanınca kurulumlar temizlenir; yeniden girişte kaçan '
      'bildirim şeritle duyurulur', () async {
    final AdminNotificationDelivery first = delivery(android: false);
    await first.attach(uid);
    await first
        .syncUpcoming([notification('r', now.add(const Duration(minutes: 5)))]);
    expect(scheduler.scheduled.keys, ['r']);

    first.detach(clearDevice: true);
    await first.syncUpcoming(const []);
    expect(scheduler.scheduled, isEmpty);

    final AdminNotificationDelivery second = delivery(android: false);
    await second.attach(uid);
    await second.announce(
      due: [notification('r', now.add(const Duration(minutes: 5)))],
      now: now.add(const Duration(minutes: 10)),
      inForeground: true,
      becameDueInForeground: const {},
    );
    expect(banners, ['r']);
  });

  test('dışarıdan iptal edilen kurulum yeniden kurulur', () async {
    final AdminNotificationDelivery d = delivery(android: false);
    await d.attach(uid);
    final List<AdminNotification> upcoming = [
      notification('r', now.add(const Duration(hours: 1))),
    ];
    await d.syncUpcoming(upcoming);
    scheduler.scheduled.clear();
    await d.syncUpcoming(upcoming);
    expect(scheduler.scheduled.keys, ['r']);
  });

  test('oturum açıkken bırakılınca kurulumlar cihazda kalır', () async {
    final AdminNotificationDelivery d = delivery(android: true);
    await d.attach(uid);
    await d.syncUpcoming([notification('r', now.add(const Duration(hours: 1)))]);
    d.detach();
    await d.syncUpcoming(const []);
    expect(scheduler.scheduled.keys, ['r']);
  });
}
