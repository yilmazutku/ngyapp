import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/mock_test_run.dart';
import 'diet_provider.dart';
import 'meal_state_and_upload_manager.dart';

final Logger logger = Logger.forClass(MockTestDataProvider);

/// Mock test aracının ürettiği verinin defterini tutar ve tek tuşla siler.
///
/// Neden defter: test fotoğrafları gerçek yükleme yoluyla yazıldığı için
/// danışanın gerçek fotoğraflarından ayırt edilemez. Bu yüzden üretilen her
/// fotoğraf ve her geçici diyet `admininput/mockTestData/runs/{runId}` altına
/// tek tek kaydedilir; temizleme adımı **yalnızca bu kayıttakileri** siler.
/// Böylece danışanın gerçek verisine hiçbir koşulda dokunulmaz.
///
/// Kayıt her danışan bitince güncellenir; uygulama ortada kapansa bile o ana
/// kadar üretilen veri kayıtlı ve silinebilir durumda kalır.
class MockTestDataProvider extends ChangeNotifier {
  /// Kayıt yolu, mevcut `admininput/events/items` düzeniyle aynı biçimde
  /// kurulur: yönetici tarafının yazabildiği, kullanıcı verisinden ayrı bir yer.
  static const String _rootCollection = 'admininput';
  static const String _rootDoc = 'mockTestData';
  static const String _runsCollection = 'runs';

  static final DateFormat _dateKeyFormat = DateFormat('yyyy-MM-dd');

  CollectionReference<Map<String, dynamic>> get _runsRef =>
      FirebaseFirestore.instance
          .collection(_rootCollection)
          .doc(_rootDoc)
          .collection(_runsCollection);

  /// Yeni bir çalıştırma kaydı açar ve id'sini döner.
  ///
  /// Kayıt, tek tek üretilenlerden ÖNCE açılır ve hedef danışanlarla günü
  /// baştan yazar; böylece tek tek kayıtlar eksik kalsa bile temizleme adımı
  /// nereye bakacağını bilir (bkz. [_sweepUser]).
  Future<String> startRun({
    String? createdBy,
    required List<String> clientNames,
    required List<String> userIds,
    required DateTime date,
  }) async {
    final DocumentReference<Map<String, dynamic>> doc = await _runsRef.add({
      'createdAt': Timestamp.now(),
      if (createdBy != null) 'createdBy': createdBy,
      'clientNames': clientNames,
      'userIds': userIds,
      'dateKey': _dateKeyFormat.format(date),
      'photos': <Map<String, dynamic>>[],
      'diets': <Map<String, dynamic>>[],
    });
    logger.info('Mock test run started. runId={} clients={} date={}',
        [doc.id, clientNames.length, _dateKeyFormat.format(date)]);
    return doc.id;
  }

  /// Bir danışan için üretilenleri kayda ekler.
  ///
  /// Her danışan bitince çağrılır; arrayUnion kullanıldığı için aynı kaydın
  /// iki kez eklenmesi listeyi bozmaz.
  Future<void> recordArtifacts({
    required String runId,
    List<MockTestPhotoRef> photos = const [],
    List<MockTestDietRef> diets = const [],
  }) async {
    if (photos.isEmpty && diets.isEmpty) return;

    await _runsRef.doc(runId).update({
      if (photos.isNotEmpty)
        'photos':
            FieldValue.arrayUnion(photos.map((ref) => ref.toMap()).toList()),
      if (diets.isNotEmpty)
        'diets':
            FieldValue.arrayUnion(diets.map((ref) => ref.toMap()).toList()),
    });
  }

  /// Kayıtlı çalıştırmalar, yeniden eskiye.
  Future<List<MockTestRun>> fetchRuns() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _runsRef.orderBy('createdAt', descending: true).get();

    final List<MockTestRun> runs = [];
    for (final doc in snapshot.docs) {
      try {
        runs.add(MockTestRun.fromDocument(doc));
      } catch (e) {
        logger.err('Error parsing mock test run {}: {}', [doc.id, e]);
      }
    }
    logger.info('Fetched {} mock test run(s)', [runs.length]);
    return runs;
  }

  /// Kayıtlı test verisini siler.
  ///
  /// [userIds] verilirse yalnızca o danışanların verisi silinir (yeni bir
  /// çalıştırmadan önce eskisini temizlemek için); null ise TÜM kayıtlı test
  /// verisi silinir (sayfadaki temizleme butonu).
  ///
  /// Silinemeyen bir öğe kayıtta bırakılır: buton tekrar çalıştırıldığında o
  /// öğe yeniden denenir, sonuçta hiçbir test verisi sessizce sistemde kalmaz.
  Future<MockCleanupResult> cleanup({
    required MealManager mealManager,
    required DietProvider dietProvider,
    Set<String>? userIds,
    void Function(String message)? onProgress,
  }) async {
    final List<MockTestRun> runs = await fetchRuns();
    final MockCleanupResult result = MockCleanupResult();

    for (final MockTestRun run in runs) {
      final List<MockTestPhotoRef> remainingPhotos = [];
      final List<MockTestDietRef> remainingDiets = [];

      for (final MockTestPhotoRef photo in run.photos) {
        if (userIds != null && !userIds.contains(photo.userId)) {
          remainingPhotos.add(photo);
          continue;
        }

        onProgress?.call('Fotoğraflar siliniyor (${result.deletedPhotos + 1})...');
        final bool deleted = await _deletePhoto(mealManager, photo);
        if (deleted) {
          result.deletedPhotos++;
        } else {
          result.failedPhotos++;
          remainingPhotos.add(photo);
        }
      }

      for (final MockTestDietRef diet in run.diets) {
        if (userIds != null && !userIds.contains(diet.userId)) {
          remainingDiets.add(diet);
          continue;
        }

        onProgress?.call('Test diyetleri siliniyor (${result.deletedDiets + 1})...');
        try {
          final bool deleted = await dietProvider.deleteMockTestDiet(
            userId: diet.userId,
            docId: diet.docId,
          );
          // deleted == false: doküman yok ya da test işareti taşımıyor. İkisinde
          // de kayıtta tutmanın anlamı yok; silinecek bir şey kalmamıştır.
          result.deletedDiets += deleted ? 1 : 0;
        } catch (e) {
          logger.err('Could not delete mock diet {} of user {}: {}',
              [diet.docId, diet.userId, e]);
          result.failedDiets++;
          remainingDiets.add(diet);
        }
      }

      // Güvenlik ağı: kayda geçememiş (ör. yazma anında kesinti olmuş) test
      // verisi varsa yakalanır. Tarama yalnızca bu çalıştırmanın danışanları
      // ve günüyle sınırlıdır; dosya adı ön eki taşımayan hiçbir fotoğrafa ve
      // test işareti taşımayan hiçbir diyete dokunulmaz.
      bool sweepClean = true;
      for (final String userId in run.userIds) {
        if (userIds != null && !userIds.contains(userId)) {
          sweepClean = false; // bu danışan bu turda kapsam dışı
          continue;
        }
        final bool ok = await _sweepUser(
          mealManager: mealManager,
          dietProvider: dietProvider,
          userId: userId,
          dateKey: run.dateKey,
          result: result,
          onProgress: onProgress,
        );
        if (!ok) sweepClean = false;
      }

      if (remainingPhotos.isEmpty && remainingDiets.isEmpty && sweepClean) {
        await deleteRunRecord(run.runId);
        result.deletedRuns++;
      } else if (remainingPhotos.length != run.photos.length ||
          remainingDiets.length != run.diets.length) {
        await updateRunRecord(run.runId,
            photos: remainingPhotos, diets: remainingDiets);
      }
    }

    notifyListeners();
    logger.info(
        'Mock cleanup done. photos={} failedPhotos={} diets={} failedDiets={} runs={}',
        [
          result.deletedPhotos,
          result.failedPhotos,
          result.deletedDiets,
          result.failedDiets,
          result.deletedRuns,
        ]);
    return result;
  }

  /// Çalıştırma kaydını siler (her şeyi silinmiş çalıştırma için).
  Future<void> deleteRunRecord(String runId) => _runsRef.doc(runId).delete();

  /// Çalıştırma kaydını, silinemeyen/kapsam dışı kalan öğelerle günceller.
  Future<void> updateRunRecord(
    String runId, {
    required List<MockTestPhotoRef> photos,
    required List<MockTestDietRef> diets,
  }) =>
      _runsRef.doc(runId).update({
        'photos': photos.map((ref) => ref.toMap()).toList(),
        'diets': diets.map((ref) => ref.toMap()).toList(),
      });

  /// Bir danışanda kalmış olabilecek test verisini tarar ve siler.
  ///
  /// İki kaynağa bakar:
  /// 1. [dateKey] gününün öğün kayıtlarında, dosya adı [kMockPhotoFilePrefix]
  ///    ile başlayan görseller (yani bu aracın yüklediği fotoğraflar).
  /// 2. Danışanın [kMockTestDataField] işaretli diyetleri.
  ///
  /// Hepsi silinebildiyse `true` döner.
  Future<bool> _sweepUser({
    required MealManager mealManager,
    required DietProvider dietProvider,
    required String userId,
    required String dateKey,
    required MockCleanupResult result,
    void Function(String message)? onProgress,
  }) async {
    bool allClean = true;

    if (dateKey.isNotEmpty) {
      try {
        final List<MealModel> meals = await mealManager.fetchMeals(
          null,
          userId: userId,
          showAllImages: true,
          date: dateKey,
        );

        for (final MealModel meal in meals) {
          for (final String url in meal.imageUrls) {
            if (!isMockPhotoUrl(url)) continue;

            onProgress?.call('Kalan test fotoğrafları taranıyor...');
            final bool deleted = await _deletePhoto(
              mealManager,
              MockTestPhotoRef(
                userId: userId,
                dateKey: dateKey,
                mealName: meal.mealType.name,
                url: url,
              ),
            );
            if (deleted) {
              result.deletedPhotos++;
            } else {
              result.failedPhotos++;
              allClean = false;
            }
          }
        }
      } catch (e) {
        logger.err('Photo sweep failed for user {} date {}: {}',
            [userId, dateKey, e]);
        allClean = false;
      }
    }

    try {
      final List<String> dietIds =
          await dietProvider.fetchMockTestDietIds(userId);
      for (final String docId in dietIds) {
        onProgress?.call('Kalan test diyetleri taranıyor...');
        final bool deleted = await dietProvider.deleteMockTestDiet(
          userId: userId,
          docId: docId,
        );
        if (deleted) result.deletedDiets++;
      }
    } catch (e) {
      logger.err('Diet sweep failed for user {}: {}', [userId, e]);
      allClean = false;
    }

    return allClean;
  }

  /// İndirme adresi bu aracın yüklediği bir dosyayı mı gösteriyor.
  ///
  /// Storage yolu adresin içinde kodlanmış olarak geçer; hem kodlanmış hem de
  /// çözülmüş biçim denenir.
  static bool isMockPhotoUrl(String url) {
    const String marker = '/$kMockPhotoFilePrefix';
    if (url.contains(marker)) return true;
    try {
      return Uri.decodeFull(url).contains(marker);
    } catch (e) {
      return false;
    }
  }

  /// Tek bir test fotoğrafını siler. Kayıttaki öğün adı ya da tarih okunamazsa
  /// silme denenmez (yanlış dokümana dokunmamak için).
  Future<bool> _deletePhoto(
      MealManager mealManager, MockTestPhotoRef photo) async {
    final Meals? meal = Meals.fromName(photo.mealName);
    if (meal == null) {
      logger.err('Unknown meal name in mock record: {}', [photo.mealName]);
      return false;
    }

    DateTime date;
    try {
      date = _dateKeyFormat.parseStrict(photo.dateKey);
    } catch (e) {
      logger.err('Unparsable date in mock record: {}', [photo.dateKey]);
      return false;
    }

    try {
      await mealManager.deleteMealImage(
        userId: photo.userId,
        meal: meal,
        imageUrlToDelete: photo.url,
        overrideDate: date,
        // Dosya Storage'dan zaten silinmişse kayıt yine de temizlenmeli.
        ignoreStorageFailure: true,
      );
      return true;
    } catch (e) {
      logger.err('Could not delete mock photo {} of user {}: {}',
          [photo.url, photo.userId, e]);
      return false;
    }
  }
}

/// Temizleme sonucunun sayıları.
class MockCleanupResult {
  int deletedPhotos = 0;
  int failedPhotos = 0;
  int deletedDiets = 0;
  int failedDiets = 0;
  int deletedRuns = 0;

  bool get hasFailures => failedPhotos > 0 || failedDiets > 0;

  String get summary {
    final StringBuffer buffer = StringBuffer()
      ..write('$deletedPhotos fotoğraf ve $deletedDiets test diyeti silindi.');
    if (hasFailures) {
      buffer.write('\n\n$failedPhotos fotoğraf, $failedDiets diyet '
          'silinemedi. Kayıtları duruyor; butona tekrar basarak yeniden '
          'deneyebilirsiniz.');
    }
    return buffer.toString();
  }
}
