import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/services/fcm_service.dart';

void main() {
  const String client = 'danisan-1';
  final String nilay = FcmService.multiDeviceUids.first;

  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      db.collection('users').doc(uid);

  Future<Map<String, dynamic>> dataOf(String uid) async =>
      (await userDoc(uid).get()).data()!;

  /// Uygulamanın girişte yaptığı gibi: kayıt okunur, gerekirse güncellenir.
  Future<Map<String, Object>?> save(String uid, String token) async {
    final Map<String, Object>? update =
        FcmService.tokenSaveUpdate(uid, token, await dataOf(uid));
    if (update != null) await userDoc(uid).update(update);
    return update;
  }

  /// Uygulamanın çıkışta yaptığı gibi; [offline] ise kayıt okunamamıştır.
  Future<void> logout(String uid, String token, {bool offline = false}) async {
    if (offline) {
      await userDoc(uid).set(
        FcmService.tokenRemovalUpdate(uid, token, null)!,
        SetOptions(merge: true),
      );
      return;
    }
    final Map<String, Object>? update =
        FcmService.tokenRemovalUpdate(uid, token, await dataOf(uid));
    if (update != null) await userDoc(uid).update(update);
  }

  group('tek jetonlu hesap', () {
    setUp(() => userDoc(client).set({'name': 'Ayşe'}));

    test('en son giren cihazın jetonu yazılır, liste tutulmaz', () async {
      await save(client, 'tel');
      await save(client, 'tablet');

      final Map<String, dynamic> data = await dataOf(client);
      expect(data['fcmToken'], 'tablet');
      expect(data.containsKey('fcmTokens'), isFalse);
      expect(await save(client, 'tablet'), isNull);
    });

    test('çıkışta yalnızca kayıttaki jeton bu cihazınsa silinir', () async {
      await save(client, 'tablet');

      await logout(client, 'tel');
      expect((await dataOf(client))['fcmToken'], 'tablet');

      await logout(client, 'tablet');
      expect((await dataOf(client)).containsKey('fcmToken'), isFalse);
    });

    test('çevrimdışı çıkış eskisi gibi yalnızca jetonu siler', () {
      expect(FcmService.tokenRemovalUpdate(client, 'tel', null)!.keys,
          ['fcmToken']);
    });
  });

  group('birden çok cihazlı hesap (Nilay)', () {
    setUp(() => userDoc(nilay).set({'name': 'Nilay'}));

    test('her cihaz listeye eklenir, fcmToken en son gireni tutar', () async {
      await save(nilay, 'tel');
      await save(nilay, 'tablet');

      final Map<String, dynamic> data = await dataOf(nilay);
      expect(data['fcmTokens'], ['tel', 'tablet']);
      expect(data['fcmToken'], 'tablet');
    });

    test('açılan cihaz zaten kayıtlıysa liste tekrarlanmaz', () async {
      await save(nilay, 'tel');
      await save(nilay, 'tablet');

      expect(await save(nilay, 'tablet'), isNull);
      await save(nilay, 'tel');

      final Map<String, dynamic> data = await dataOf(nilay);
      expect(data['fcmTokens'], ['tel', 'tablet']);
      expect(data['fcmToken'], 'tel');
    });

    test('eski sürümün yazdığı tek jeton, cihaz güncellenince listeye girer',
        () async {
      await userDoc(nilay).update({'fcmToken': 'eski-surum'});

      await save(nilay, 'eski-surum');

      final Map<String, dynamic> data = await dataOf(nilay);
      expect(data['fcmTokens'], ['eski-surum']);
      expect(data['fcmToken'], 'eski-surum');
    });

    test('çıkışta yalnızca o cihaz listeden çıkar', () async {
      await save(nilay, 'tel');
      await save(nilay, 'tablet');

      await logout(nilay, 'tel');
      Map<String, dynamic> data = await dataOf(nilay);
      expect(data['fcmTokens'], ['tablet']);
      expect(data['fcmToken'], 'tablet');

      await logout(nilay, 'tablet');
      data = await dataOf(nilay);
      expect(data['fcmTokens'], isEmpty);
      expect(data.containsKey('fcmToken'), isFalse);
    });

    test('kayıtlı olmayan cihazdan çıkış kayda dokunmaz', () async {
      await save(nilay, 'tel');

      expect(
        FcmService.tokenRemovalUpdate(nilay, 'baska', await dataOf(nilay)),
        isNull,
      );
    });

    test('çevrimdışı çıkış bu cihazı listeden ve son cihaz alanından çıkarır',
        () async {
      await save(nilay, 'tel');
      await save(nilay, 'tablet');

      await logout(nilay, 'tablet', offline: true);

      final Map<String, dynamic> data = await dataOf(nilay);
      expect(data['fcmTokens'], ['tel']);
      expect(data.containsKey('fcmToken'), isFalse);
    });
  });
}
