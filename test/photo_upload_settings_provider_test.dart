import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/providers/photo_upload_settings_provider.dart';
import 'package:ngy_app/utils/storage_upload.dart';

void main() {
  late FakeFirebaseFirestore db;
  late PhotoUploadSettingsProvider provider;
  late DocumentReference<Map<String, dynamic>> doc;

  final UploadImageProfile defaultProfile = UploadImageProfile.current;

  setUp(() {
    db = FakeFirebaseFirestore();
    provider = PhotoUploadSettingsProvider(firestore: db);
    doc = db
        .collection(PhotoUploadSettingsProvider.collection)
        .doc(PhotoUploadSettingsProvider.docId);
  });

  tearDown(() {
    provider.dispose();
    UploadImageProfile.current = defaultProfile;
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('ayar admininput/photoUpload dokümanının compact alanıdır', () {
    expect(doc.path, 'admininput/photoUpload');
    expect(PhotoUploadSettingsProvider.compactField, 'compact');
    expect(PhotoUploadSettingsProvider.defaultCompact, isTrue);
  });

  test('alan true ya da yoksa küçük, false ise eski ölçü seçilir', () {
    UploadImageProfile of(Map<String, dynamic>? data) =>
        PhotoUploadSettingsProvider.profileOf(data);

    expect(of(null), UploadImageProfile.compact);
    expect(of({}), UploadImageProfile.compact);
    expect(of({'compact': true}), UploadImageProfile.compact);
    expect(of({'compact': false}), UploadImageProfile.standard);
  });

  test('değer metin ya da sayı olarak girilse de seçilen ölçü uygulanır', () {
    UploadImageProfile of(Object? value) =>
        PhotoUploadSettingsProvider.profileOf({'compact': value});

    for (final Object value in ['true', 'True', ' TRUE ', '1', 1, 1.0]) {
      expect(of(value), UploadImageProfile.compact, reason: '$value');
    }
    for (final Object value in ['false', 'False', ' FALSE ', '0', 0, 0.0]) {
      expect(of(value), UploadImageProfile.standard, reason: '$value');
    }
    for (final Object? value in ['', 'belki', null, <String>[]]) {
      expect(of(value), UploadImageProfile.compact, reason: '$value');
    }
  });

  test('alan elle değiştirilince ölçü uygulama yeniden açılmadan değişir',
      () async {
    await doc.set({'compact': false});
    provider.start(seedsDefault: false);
    await provider.ensureLoaded();
    expect(UploadImageProfile.current, UploadImageProfile.standard);

    await doc.update({'compact': true});
    await settle();
    expect(UploadImageProfile.current, UploadImageProfile.compact);

    await doc.update({'compact': false});
    await settle();
    expect(UploadImageProfile.current, UploadImageProfile.standard);
  });

  test('admin oturumu eksik alanı true olarak yazar', () async {
    provider.start(seedsDefault: true);
    await provider.ensureLoaded();
    await settle();

    expect((await doc.get()).data(), {'compact': true});
    expect(UploadImageProfile.current, UploadImageProfile.compact);
  });

  test('admin oturumu dokümandaki diğer alanlara dokunmaz', () async {
    await doc.set({'not': 'deneme'});
    provider.start(seedsDefault: true);
    await provider.ensureLoaded();
    await settle();

    expect((await doc.get()).data(), {'not': 'deneme', 'compact': true});
  });

  test('admin oturumu elle false yapılmış alanı geri çevirmez', () async {
    await doc.set({'compact': false});
    provider.start(seedsDefault: true);
    await provider.ensureLoaded();
    await settle();

    expect((await doc.get()).data(), {'compact': false});
    expect(UploadImageProfile.current, UploadImageProfile.standard);
  });

  test('admin oturumu metin olarak girilmiş değerin üstüne yazmaz', () async {
    await doc.set({'compact': 'false'});
    provider.start(seedsDefault: true);
    await provider.ensureLoaded();
    await settle();

    expect((await doc.get()).data(), {'compact': 'false'});
    expect(UploadImageProfile.current, UploadImageProfile.standard);
  });

  test('danışan oturumu Firestore\'a yazmaz', () async {
    provider.start(seedsDefault: false);
    await provider.ensureLoaded();
    await settle();

    expect((await doc.get()).exists, isFalse);
    expect(UploadImageProfile.current, UploadImageProfile.compact);
  });

  test('yeniden başlatmak ikinci bir dinleyici açmaz; admin olunca yazar',
      () async {
    provider.start(seedsDefault: false);
    await provider.ensureLoaded();
    await settle();
    expect((await doc.get()).exists, isFalse);

    provider.start(seedsDefault: true);
    await doc.set({'not': 'deneme'});
    await settle();
    await settle();

    expect((await doc.get()).data(), {'not': 'deneme', 'compact': true});
  });

  testWidgets('ayar okunamazsa beklemesi süreyle sınırlıdır', (tester) async {
    bool done = false;
    provider.ensureLoaded().then((_) => done = true);

    await tester.pump(
      PhotoUploadSettingsProvider.loadTimeout - const Duration(seconds: 1),
    );
    expect(done, isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(done, isTrue);
    expect(UploadImageProfile.current, UploadImageProfile.compact);
  });
}
