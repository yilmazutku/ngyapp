import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/models/chat_load_test_run.dart';
import 'package:ngy_app/providers/chat_load_test_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String office = '0MvvbZsjbmNPW4QYShRNSOOtkE43';
  const String runA = 'RunAaaaaaaaa1';
  const String runB = 'RunBbbbbbbbb2';

  late FakeFirebaseFirestore db;
  late List<({String name, Map<String, dynamic> data})> calls;
  late Object? Function(String name, Map<String, dynamic> data) respond;
  late ChatLoadTestProvider provider;

  setUp(() {
    db = FakeFirebaseFirestore();
    calls = [];
    respond = (name, data) => {'runs': data.containsKey('runId') ? 1 : 2};
    provider = ChatLoadTestProvider(
      db: db,
      currentUid: () => office,
      callFunction: (name, data) async {
        calls.add((name: name, data: data));
        final Object? result = respond(name, data);
        if (result is Exception) throw result;
        return result;
      },
    );
  });

  tearDown(() => provider.dispose());

  DocumentReference<Map<String, dynamic>> run(String id) =>
      db.collection('chatLoadTests').doc(id);

  Future<bool> stopExists(String id) async =>
      (await run(id).collection('control').doc('stop').get()).exists;

  test('sohbet ofisi oturumu tanınır', () {
    expect(provider.isChatOffice, isTrue);
    expect(
      ChatLoadTestProvider(db: db, currentUid: () => 'baska').isChatOffice,
      isFalse,
    );
  });

  test('testler yeniden eskiye listelenir', () async {
    await run('eski').set({
      'status': 'completed',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
    });
    await run('yeni').set({
      'status': 'running',
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 10)),
    });
    final List<ChatLoadTestRun> runs = await provider.runsStream().first;
    expect([for (final ChatLoadTestRun r in runs) r.id], ['yeni', 'eski']);
    expect(runs.first.status, ChatLoadTestStatus.running);
  });

  test('durdurma süren testi iptal eder ve dur kaydı yazar', () async {
    await run(runA).set({'status': 'running'});
    expect(await provider.stopRun(runA), isTrue);
    expect((await run(runA).get()).get('status'), 'cancelled');
    expect((await run(runA).get()).get('finishedAt'), isA<Timestamp>());
    expect(await stopExists(runA), isTrue);

    await run(runB).set({'status': 'completed'});
    expect(await provider.stopRun(runB), isFalse);
    expect((await run(runB).get()).get('status'), 'completed');
    expect(await stopExists(runB), isTrue);
  });

  test('sürdürme yeni bir zincirin ilk halkasını açar', () async {
    await provider.resumeRun(runA);
    final QuerySnapshot<Map<String, dynamic>> ticks =
        await run(runA).collection('ticks').get();
    expect(ticks.docs, hasLength(1));
    final QueryDocumentSnapshot<Map<String, dynamic>> tick = ticks.docs.single;
    final String chain = tick.get('chain') as String;
    expect(chain, startsWith('r'));
    expect(tick.id, '${chain}_00000');
    expect(tick.get('fromIndex'), 0);
  });

  test(
      'temizlik testi durdurur, kullanıcıları verilen silme işleviyle siler, '
      'sonra sunucuya test kayıtlarını sildirir', () async {
    await run(runA).set({
      'status': 'running',
      'userCount': 2,
      'users': [
        {'uid': 'loadtest_${runA}_001'},
        {'uid': 'loadtest_${runA}_002'},
      ],
    });
    await db.collection('users').doc('loadtest_${runA}_003').set({
      'isLoadTestUser': true,
      'loadTestRunId': runA,
    });
    await db.collection('users').doc('gercekDanisan').set({
      'isLoadTestUser': true,
      'loadTestRunId': runA,
    });

    final List<String> deleted = [];
    final List<String> progress = [];
    final ChatLoadTestCleanupResult result = await provider.cleanup(
      runId: runA,
      deleteUser: (uid) async => deleted.add(uid),
      onProgress: progress.add,
    );

    expect((await run(runA).get()).get('status'), 'cancelled');
    expect(await stopExists(runA), isTrue);
    expect(deleted.toSet(), {
      'loadtest_${runA}_001',
      'loadtest_${runA}_002',
      'loadtest_${runA}_003',
    });
    expect(calls.single.name, 'cleanupChatLoadTests');
    expect(calls.single.data, {'runId': runA});
    expect(result.isComplete, isTrue);
    expect(result.deletedUsers, 3);
    expect(result.deletedRuns, 1);
    expect(progress.last, 'Test fotoğrafları ve kayıtları siliniyor...');
  });

  test('bütün test verisi: her test ve işaretli kullanıcılar', () async {
    await run(runA).set({'status': 'completed', 'userCount': 1});
    await run(runB).set({'status': 'running', 'userCount': 1});
    await db.collection('users').doc('loadtest_RunZzzzzzzzz9_001').set({
      'isLoadTestUser': true,
    });

    final List<String> deleted = [];
    final ChatLoadTestCleanupResult result = await provider.cleanup(
      deleteUser: (uid) async => deleted.add(uid),
    );

    expect((await run(runB).get()).get('status'), 'cancelled');
    expect(await stopExists(runA), isTrue);
    expect(deleted.toSet(), {
      'loadtest_${runA}_001',
      'loadtest_${runB}_001',
      'loadtest_RunZzzzzzzzz9_001',
    });
    expect(calls.single.data, isEmpty);
    expect(result.deletedRuns, 2);
  });

  test('silinemeyen kullanıcı varsa test kayıtları silinmez', () async {
    await run(runA).set({'status': 'completed', 'userCount': 3});
    final ChatLoadTestCleanupResult result = await provider.cleanup(
      runId: runA,
      deleteUser: (uid) async {
        if (uid.endsWith('_002')) throw Exception('ağ yok');
      },
    );
    expect(result.isComplete, isFalse);
    expect(result.deletedUsers, 2);
    expect(result.failedUsers, 1);
    expect(result.deletedRuns, 0);
    expect(calls, isEmpty);
  });

  test('sunucu temizliği başarısızsa hata döner', () async {
    respond = (name, data) => Exception('Sunucu hatası.');
    final ChatLoadTestCleanupResult result = await provider.cleanup(
      runId: runA,
      deleteUser: (uid) async {},
    );
    expect(result.isComplete, isFalse);
    expect(result.error, 'Sunucu hatası.');
  });

  test('yükleme dosya adı güvenli ve kısa', () {
    expect(ChatLoadTestProvider.uploadFileName('tabak.jpg'), 'tabak.jpg');
    expect(ChatLoadTestProvider.uploadFileName('../a/b.jpg'), 'b.jpg');
    expect(ChatLoadTestProvider.uploadFileName('.gizli.png'), 'gizli.png');
    expect(ChatLoadTestProvider.uploadFileName(''), 'foto.jpg');
    final String long = ChatLoadTestProvider.uploadFileName(
        '${'a' * 200}.jpeg');
    expect(long.length, ChatLoadTestProvider.maxFileNameLength);
    expect(long, endsWith('.jpeg'));
  });
}
