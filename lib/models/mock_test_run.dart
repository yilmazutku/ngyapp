import 'package:cloud_firestore/cloud_firestore.dart';

/// Mock test aracının OLUŞTURDUĞU dokümanlara konan işaret alanı.
///
/// Silme adımı asıl olarak çalıştırma kaydına ([MockTestRun]) bakar; bu alan
/// ikinci bir emniyet kilididir: işareti taşımayan bir diyet, kayıtta yanlışlıkla
/// görünse bile silinmez.
const String kMockTestDataField = 'isMockTestData';

/// Kopyalanan test diyetinin adının başına konan ön ek. Danışanın listesinde
/// hangi diyetin test amaçlı olduğu ilk bakışta anlaşılsın diye.
const String kMockDietNamePrefix = '[TEST] ';

/// Test aracının yüklediği fotoğrafların dosya adı ön eki.
///
/// Storage yolu indirme adresinin içinde geçtiği için, defter kaydı eksik
/// kalsa bile bir fotoğrafın test verisi olduğu bu ön ekten anlaşılabilir
/// (bkz. temizlemedeki tarama adımı).
const String kMockPhotoFilePrefix = 'mock_';

/// Test aracının yüklediği tek bir fotoğrafın izi.
///
/// Silme için gereken en küçük bilgi: hangi danışanın, hangi günün, hangi
/// öğününe ait hangi görsel. Fotoğraf tek tek adreslendiği için silme işlemi
/// aynı öğün dokümanındaki GERÇEK fotoğraflara dokunmaz.
class MockTestPhotoRef {
  final String userId;

  /// `yyyy-MM-dd` biçiminde gün anahtarı (öğün dokümanının yolu).
  final String dateKey;

  /// `Meals` enum adı (öğün dokümanının id'si).
  final String mealName;

  /// Storage indirme adresi; hem dosyayı hem de listedeki kaydı bulmaya yarar.
  final String url;

  const MockTestPhotoRef({
    required this.userId,
    required this.dateKey,
    required this.mealName,
    required this.url,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'dateKey': dateKey,
        'mealName': mealName,
        'url': url,
      };

  static MockTestPhotoRef? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final String userId = (raw['userId'] ?? '') as String;
    final String dateKey = (raw['dateKey'] ?? '') as String;
    final String mealName = (raw['mealName'] ?? '') as String;
    final String url = (raw['url'] ?? '') as String;
    if (userId.isEmpty || dateKey.isEmpty || mealName.isEmpty || url.isEmpty) {
      return null;
    }
    return MockTestPhotoRef(
      userId: userId,
      dateKey: dateKey,
      mealName: mealName,
      url: url,
    );
  }
}

/// Test aracının bir danışana kopyaladığı geçici diyetin izi.
class MockTestDietRef {
  final String userId;
  final String docId;

  /// Sonuç/onay ekranlarında gösterilen ad.
  final String displayName;

  const MockTestDietRef({
    required this.userId,
    required this.docId,
    required this.displayName,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'docId': docId,
        'displayName': displayName,
      };

  static MockTestDietRef? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final String userId = (raw['userId'] ?? '') as String;
    final String docId = (raw['docId'] ?? '') as String;
    if (userId.isEmpty || docId.isEmpty) return null;
    return MockTestDietRef(
      userId: userId,
      docId: docId,
      displayName: (raw['displayName'] ?? '') as String,
    );
  }
}

/// Tek bir "test verisi yükle" çalıştırmasının kaydı.
///
/// `admininput/mockTestData/runs/{runId}` altında tutulur. Kayıt, temizleme
/// butonunun ne sileceğinin tek kaynağıdır: uygulama kapansa, gün değişse bile
/// üretilen veri buradan bulunup silinebilir.
class MockTestRun {
  final String runId;
  final DateTime createdAt;

  /// Çalıştırmayı yapan yönetici (uid).
  final String? createdBy;

  /// Ekranda gösterilen danışan adları.
  final List<String> clientNames;

  /// Çalıştırmanın hedeflediği danışanlar. Tek tek kayıtlar eksik kalsa bile
  /// temizleme adımı nereye bakacağını bu listeden bilir.
  final List<String> userIds;

  /// Fotoğrafların yüklendiği gün (`yyyy-MM-dd`). Tarama adımı bu günle
  /// sınırlıdır.
  final String dateKey;

  final List<MockTestPhotoRef> photos;
  final List<MockTestDietRef> diets;

  const MockTestRun({
    required this.runId,
    required this.createdAt,
    required this.createdBy,
    required this.clientNames,
    required this.userIds,
    required this.dateKey,
    required this.photos,
    required this.diets,
  });

  factory MockTestRun.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};

    List<T> parseList<T>(Object? raw, T? Function(Object?) parse) {
      if (raw is! List) return <T>[];
      final List<T> parsed = [];
      for (final Object? item in raw) {
        final T? value = parse(item);
        if (value != null) parsed.add(value);
      }
      return parsed;
    }

    return MockTestRun(
      runId: doc.id,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] as String?,
      clientNames: (data['clientNames'] is List)
          ? List<String>.from(data['clientNames'] as List)
          : const <String>[],
      userIds: (data['userIds'] is List)
          ? List<String>.from(data['userIds'] as List)
          : const <String>[],
      dateKey: (data['dateKey'] ?? '') as String,
      photos: parseList<MockTestPhotoRef>(
          data['photos'], MockTestPhotoRef.fromMap),
      diets:
          parseList<MockTestDietRef>(data['diets'], MockTestDietRef.fromMap),
    );
  }
}
