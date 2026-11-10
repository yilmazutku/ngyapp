import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/chat_load_test_run.dart';
import 'package:ngy_app/models/meal_model.dart';

void main() {
  ChatLoadTestConfig config({
    int users = 30,
    int perUser = 3,
    double gap = 2,
    int delay = 15,
  }) =>
      ChatLoadTestConfig(
        userCount: users,
        photosPerUser: perUser,
        gapSeconds: gap,
        startDelaySeconds: delay,
        order: ChatLoadTestOrder.roundRobin,
      );

  group('ChatLoadTestConfig', () {
    test('geçerli ayarlar ve sınırlar', () {
      expect(config().validate(2), isNull);
      expect(config().validate(0), isNotNull);
      expect(config().validate(6), isNotNull);
      expect(config(users: 0).validate(1), isNotNull);
      expect(config(users: 101).validate(1), isNotNull);
      expect(config(perUser: 0).validate(1), isNotNull);
      expect(config(perUser: 11).validate(1), isNotNull);
      expect(config(gap: -1).validate(1), isNotNull);
      expect(config(gap: 601).validate(1), isNotNull);
      expect(config(gap: double.nan).validate(1), isNotNull);
      expect(config(delay: 601).validate(1), isNotNull);
      expect(config(gap: 0).validate(1), isNull);
      expect(config(gap: 0.5).validate(1), isNull);
    });

    test('iki saati aşan test reddedilir', () {
      expect(config(users: 100, perUser: 10, gap: 8).validate(1), isNotNull);
      expect(config(users: 100, perUser: 10, gap: 7).validate(1), isNull);
    });

    test('toplam mesaj ve süre', () {
      final ChatLoadTestConfig c = config(users: 40, perUser: 3, gap: 0.5);
      expect(c.totalMessages, 120);
      expect(c.sendDuration, const Duration(milliseconds: 59500));
      expect(config(users: 1, perUser: 1).sendDuration, Duration.zero);
    });

    test('fotoğraflar ve öğünler sırayla dağıtılır', () {
      final List<ChatLoadTestSlot> slots = config(perUser: 8).slotsFor(3);
      expect([for (final ChatLoadTestSlot s in slots) s.photoIndex],
          [0, 1, 2, 0, 1, 2, 0, 1]);
      expect([for (final ChatLoadTestSlot s in slots) s.meal], [
        ...Meals.dietValues,
        Meals.dietValues[0],
        Meals.dietValues[1],
      ]);
      expect(slots[2].toMap(), {
        'photo': 2,
        'meal': Meals.lunch.name,
        'caption': Meals.lunch.chatCaption,
        'summary': Meals.lunch.chatSummary,
      });
    });

    test('sunucuya giden istek', () {
      final Map<String, dynamic> request = config(perUser: 2).toRequest(
        runId: 'run1',
        photos: [
          {'path': 'chatLoadTests/run1/p0_a.jpg'},
        ],
        utcOffsetMinutes: 180,
      );
      expect(request['runId'], 'run1');
      expect(request['userCount'], 30);
      expect(request['gapSeconds'], 2.0);
      expect(request['order'], 'roundRobin');
      expect(request['utcOffsetMinutes'], 180);
      expect(request.containsKey('notify'), isFalse);
      expect((request['slots'] as List).length, 2);
    });
  });

  group('ChatLoadTestUsers', () {
    test('test UID biçimi', () {
      expect(ChatLoadTestUsers.uidOf('Run1234567890', 0),
          'loadtest_Run1234567890_001');
      expect(ChatLoadTestUsers.isTestUserUid('loadtest_Run1234567890_001'),
          isTrue);
      expect(ChatLoadTestUsers.isTestUserUid('0MvvbZsjbmNPW4QYShRNSOOtkE43'),
          isFalse);
      expect(ChatLoadTestUsers.isTestUserUid('loadtest_x_001'), isFalse);
      expect(ChatLoadTestUsers.isTestUserUid('loadtest_Run1234567890_01'),
          isFalse);
      expect(
          ChatLoadTestUsers.isTestUserUid('xloadtest_Run1234567890_001'),
          isFalse);
    });
  });

  group('ChatLoadTestRun', () {
    final DateTime start = DateTime(2026, 11, 10, 14);

    test('kayıttan okunur', () {
      final ChatLoadTestRun run = ChatLoadTestRun.fromMap('Run1234567890', {
        'status': 'running',
        'createdAt': Timestamp.fromDate(start),
        'startAt': Timestamp.fromDate(start),
        'heartbeatAt': Timestamp.fromDate(start),
        'userCount': 3,
        'photosPerUser': 2,
        'totalSteps': 6,
        'sentCount': 4,
        'failedCount': 1,
        'gapSeconds': 1.5,
        'order': 'perUser',
        'lastError': 'hata',
        'users': [
          {'uid': 'loadtest_Run1234567890_001', 'name': 'A Test 01'},
          {'uid': 'bozuk'},
          'x',
        ],
      });
      expect(run.status, ChatLoadTestStatus.running);
      expect(run.status.isActive, isTrue);
      expect(run.order, ChatLoadTestOrder.perUser);
      expect(run.processedCount, 5);
      expect(run.progress, closeTo(5 / 6, 1e-9));
      expect(run.estimatedEndAt, start.add(const Duration(milliseconds: 7500)));
      expect(run.lastError, 'hata');
      expect(run.listedUserIds, ['loadtest_Run1234567890_001', 'bozuk']);
      expect(run.testUserIds, ['loadtest_Run1234567890_001']);
    });

    test('kullanıcı listesi yoksa UID\'ler kullanıcı sayısından', () {
      final ChatLoadTestRun run = ChatLoadTestRun.fromMap('Run1234567890', {
        'status': 'failed',
        'userCount': 2,
      });
      expect(run.testUserIds,
          ['loadtest_Run1234567890_001', 'loadtest_Run1234567890_002']);
    });

    test('sunucuya ulaşmamış testin kullanıcısı yok', () {
      final ChatLoadTestRun run = ChatLoadTestRun.fromMap('Run1234567890', {
        'status': 'failed',
        'requestedUserCount': 30,
      });
      expect(run.testUserIds, isEmpty);
      expect(run.displayUserCount, 30);
    });

    test('bilinmeyen alanlar güvenle okunur', () {
      final ChatLoadTestRun run =
          ChatLoadTestRun.fromMap('id', {'status': 'garip', 'totalSteps': 0});
      expect(run.status, ChatLoadTestStatus.unknown);
      expect(run.status.isActive, isFalse);
      expect(run.progress, 0);
      expect(run.estimatedEndAt, isNull);
      expect(ChatLoadTestRun.fromMap('id', {'sentCount': 9, 'totalSteps': 3})
          .progress, 1);
    });

    test('yalnızca süren ve uzun süredir sessiz test durmuş sayılır', () {
      ChatLoadTestRun run(String status, DateTime heartbeat) =>
          ChatLoadTestRun.fromMap('id', {
            'status': status,
            'heartbeatAt': Timestamp.fromDate(heartbeat),
          });
      final DateTime now = start.add(const Duration(minutes: 7));
      expect(run('running', start).isStalled(now), isTrue);
      expect(run('running', now.subtract(const Duration(minutes: 5)))
          .isStalled(now), isFalse);
      expect(run('completed', start).isStalled(now), isFalse);
      expect(run('cancelled', start).isStalled(now), isFalse);
    });
  });

  test('başlatma sonucu okunur', () {
    final ChatLoadTestStartResult result = ChatLoadTestStartResult.fromResult(
      'run1',
      <String, dynamic>{
        'userCount': 30,
        'totalSteps': 90,
        'startAtMs': 1794303861608,
      },
    );
    expect(result.userCount, 30);
    expect(result.totalSteps, 90);
    expect(result.startAt,
        DateTime.fromMillisecondsSinceEpoch(1794303861608));
    expect(ChatLoadTestStartResult.fromResult('run1', null).totalSteps, 0);
  });
}
