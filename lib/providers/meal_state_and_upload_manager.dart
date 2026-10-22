import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/meal_model.dart';
import '../models/filter_params.dart';
import '../models/pending_upload.dart';
import '../services/meal_reminder_service.dart';
import '../utils/date_formatter.dart';
import '../utils/image_thumbnail.dart';
import '../utils/storage_upload.dart';
import '../providers/chat_manager_new.dart';

/// Manages meal state and provides functionality for uploading and fetching meals
/// Handles the storage and retrieval of meal data from Firestore
class MealManager extends ChangeNotifier {
static const MEAL_RANGE_DAYS=7;

  /// Toplu (çok danışanlı) sorgularda aynı anda açılan Firestore
  /// isteği sayısı. Bkz. [fetchMealsOfUsersForDate].
  ///
  /// Her parti bir gidiş-dönüş demek; parti büyüdükçe sayfa daha az turda
  /// dolar. 20, tek seferde açılan bağlantıyı makul tutarken 100 danışanı
  /// 5 turda bitirir.
  static const int USER_BATCH_SIZE = 20;

  /// ADMIN CAGIRIR: SON 7 GÜNLÜK MEALLARI ÇEKER
  /// 
  /// Optimized to fetch all meals in a date range with a single batch operation
  /// instead of sequential queries for each date. This significantly improves
  /// performance when loading multiple days of data.
  Future<List<MealModel>> fetchMeals(
      String? selectedSubscriptionId/*optional*/, {
        required String userId,
        required bool showAllImages,
        String? date/*optional*/,
        MealFilterParams? filterParams,
      }) async {
    try {
      List<MealModel> all = [];
      
      // Determine the fetch strategy based on parameters
      if (filterParams?.specificDate != null) {
        // Single date - use direct fetch
        final dateKey = DateFormat('yyyy-MM-dd').format(filterParams!.specificDate!);
        all = await _fetchMealImages(userId, date: dateKey, filterParams: filterParams);
      } else if (date != null) {
        // Legacy: specific date parameter
        all = await _fetchMealImages(userId, date: date, filterParams: filterParams);
      } else {
        // Multiple dates - use batch fetch for better performance
        DateTime startDate;
        DateTime endDate;
        
        if (filterParams?.dateRange != null) {
          // Use provided date range
          startDate = filterParams!.dateRange!.start;
          endDate = filterParams.dateRange!.end;
        } else if (filterParams?.showOnlyThisWeek ?? false) {
          // Last 7 days
          final now = DateTime.now();
          endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          startDate = endDate.subtract(const Duration(days: MEAL_RANGE_DAYS - 1));
        } else {
          // Default: last 7 days
          final now = DateTime.now();
          endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          startDate = endDate.subtract(const Duration(days: MEAL_RANGE_DAYS - 1));
        }
        
        // Use batch fetch for date ranges
        all = await _fetchMealImagesInRange(userId, startDate, endDate, filterParams);
      }

      // Filter by subscription if needed
      if (!showAllImages && selectedSubscriptionId != null) {
        all = all.where((m) => m.subscriptionId == selectedSubscriptionId).toList();
      }

      // Apply meal type filter if provided. Ara öğün seçildiyse üç ara öğünün
      // hepsi eşleşir: filtrede numarasız tek "Ara" seçeneği var.
      if (filterParams?.mealType != null) {
        final Meals? filterMeal = Meals.fromName(filterParams!.mealType!);
        all = all
            .where((m) => filterMeal != null && filterMeal.isSnack
                ? m.mealType.isSnack
                : m.mealType.name == filterParams.mealType)
            .toList();
      }

      // Apply search filter if provided
      if (filterParams?.searchQuery != null && filterParams!.searchQuery!.isNotEmpty) {
        final searchLower = filterParams.searchQuery!.toLowerCase();
        all = all.where((m) {
          return m.description?.toLowerCase().contains(searchLower) ?? false;
        }).toList();
      }

      all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return all;
    } catch (e) {
      rethrow;
    }
  }


  /// Fetches meal images for a date range in a single batch operation
  /// More efficient than fetching each date individually
  Future<List<MealModel>> _fetchMealImagesInRange(
    String userId, 
    DateTime startDate, 
    DateTime endDate,
    MealFilterParams? filterParams,
  ) async {
    List<MealModel> meals = [];
    
    try {
      // Generate all date keys in the range
      List<String> dateKeys = [];
      var current = startDate;
      while (!current.isAfter(endDate)) {
        dateKeys.add(DateFormat('yyyy-MM-dd').format(current));
        current = current.add(const Duration(days: 1));
      }
      
      // Batch fetch: Get all date documents and their subcollections in parallel
      // This is more efficient than sequential queries

      final futures = dateKeys.map((dateKey) async {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('meals')
              .doc(dateKey)
              .collection('mealEntries')
              .get();
          List<MealModel> dateMeals = [];
          for (var doc in snapshot.docs) {
            try {
              dateMeals.add(MealModel.fromDocument(doc));
            } catch (e) {
            }
          }
          return dateMeals;
        } catch (e) {
          return <MealModel>[];
        }
      }).toList();
      
      // Wait for all queries to complete
      final results = await Future.wait(futures);
      
      // Flatten results
      for (final dateMeals in results) {
        meals.addAll(dateMeals);
      }
    } catch (e) {
    }
    
    return meals;
  }

  /// ADMIN ÇAĞIRIR: Verilen danışanların TEK bir güne ait öğün fotoğraflarını
  /// toplu hâlde çeker.
  ///
  /// Öğünler `users/{userId}/meals/{yyyy-MM-dd}/mealEntries` altında tutulur.
  /// Danışan fotoğrafı yalnızca sohbetten yükler; [uploadMealImg] bu dokümanı
  /// yazar, buradan okunur.
  ///
  /// Dönen map yalnızca o gün en az bir fotoğrafı olan danışanları içerir;
  /// listelerdeki öğünler saatine göre eskiden yeniye sıralıdır.
  ///
  /// [onBatch] verilirse her parti biter bitmez o partinin sonucuyla çağrılır:
  /// çağıran taraf tüm danışanları beklemeden ekranı doldurmaya başlayabilir.
  Future<Map<String, List<MealModel>>> fetchMealsOfUsersForDate({
    required List<String> userIds,
    required DateTime date,
    void Function(Map<String, List<MealModel>> batchResult)? onBatch,
  }) async {
    final String dateKey = DateFormat('yyyy-MM-dd').format(date);
    final Map<String, List<MealModel>> mealsByUser = {};

    // Danışan sayısı büyüdükçe tüm sorguları aynı anda açmamak için
    // USER_BATCH_SIZE'lık paralel gruplar hâlinde ilerlenir.
    for (int start = 0; start < userIds.length; start += USER_BATCH_SIZE) {
      final int end = start + USER_BATCH_SIZE < userIds.length
          ? start + USER_BATCH_SIZE
          : userIds.length;
      final List<String> batch = userIds.sublist(start, end);

      final List<List<MealModel>> batchResults = await Future.wait(
        batch.map((userId) => _fetchMealImages(userId, date: dateKey)),
      );

      final Map<String, List<MealModel>> batchMeals = {};
      for (int i = 0; i < batch.length; i++) {
        final List<MealModel> withPhotos = batchResults[i]
            .where((meal) => meal.imageUrls.isNotEmpty)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        if (withPhotos.isNotEmpty) {
          batchMeals[batch[i]] = withPhotos;
        }
      }

      mealsByUser.addAll(batchMeals);
      onBatch?.call(batchMeals);
    }

    return mealsByUser;
  }

  /// Fetches meal images for a specific date
  Future<List<MealModel>> _fetchMealImages(String userId, {String? date, MealFilterParams? filterParams}) async {
    final currentDate = date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    List<MealModel> meals = [];
    
    try {
      final mealEntriesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('meals')
          .doc(currentDate)
          .collection('mealEntries')
          .get();
          
      for (var doc in mealEntriesSnapshot.docs) {
        try {
          meals.add(MealModel.fromDocument(doc));
        } catch (e) {
        }
      }
    } catch (e) {
    }
    
    return meals;
  }

/// Öğüne yeni bir fotoğraf eklenebilir mi: o günün öğün kaydında
/// [MealModel.maxImages] sınırı dolmamışsa (ya da kayıt yoksa) true.
///
/// Yüklemeden önce sorulur ki kullanıcı fotoğraf seçip yüklemeyi bekledikten
/// sonra reddedilmesin. [date] verilmezse bugün.
Future<bool> canAddMealImage({
  required String userId,
  required Meals meal,
  DateTime? date,
}) async =>
    await mealImageSlotsLeft(userId: userId, meal: meal, date: date) > 0;

/// Öğüne daha kaç fotoğraf eklenebilir ([MealModel.maxImages] sınırına göre).
/// Birden çok fotoğraf seçtirilirken seçim sınırı olarak kullanılır.
Future<int> mealImageSlotsLeft({
  required String userId,
  required Meals meal,
  DateTime? date,
}) async {
  final String dateKey = DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());
  final DocumentSnapshot<Map<String, dynamic>> mealDoc = await FirebaseFirestore
      .instance
      .collection('users')
      .doc(userId)
      .collection('meals')
      .doc(dateKey)
      .collection('mealEntries')
      .doc(meal.name)
      .get();
  if (!mealDoc.exists) return MealModel.maxImages;
  final int used = MealModel.fromDocument(mealDoc).imageUrls.length;
  return used >= MealModel.maxImages ? 0 : MealModel.maxImages - used;
}

/// Sohbetten gönderilen öğün fotoğrafını ([PendingUpload]) öğün kaydına
/// ekler ve sohbete yazar; fotoğraf gönderildiği anın gününe ve saatine
/// kaydedilir ([PendingUpload.createdAt]), yükleme gecikse de. O gün bugünse
/// öğünün "yüklediniz mi?" hatırlatması iptal olur; fotoğraf sonradan
/// silinse de o gün geri kurulmaz (bkz. [mealStateFields]). Sohbet ekranı ve
/// uygulama açılışında geri yüklenen sıra (bkz.
/// [ChatManager.restorePendingUploads]) aynı yolu kullanır.
///
/// Öğün kaydı ve sohbet mesajı birlikte yazılır (bkz. [uploadMealImg]):
/// sohbette görünmeyen fotoğraf öğünde de görünmez. Yazılamazsa hata
/// fırlatılır, yükleme sırası "yüklenemedi" gösterip yeniden dener. Öğünün
/// fotoğraf sınırı dolmuşsa tekrar denenmeyen bir [UploadFailure] fırlatır.
Future<void> uploadChatMealPhoto(
  PendingUpload upload, {
  required String userId,
  required ChatManager chatManager,
}) async {
  final String? downloadUrl = await uploadMealImg(
    meal: upload.meal,
    image: upload.image,
    userId: userId,
    subscriptionId: userId,
    overrideDate: upload.createdAt,
    chatMessageId: upload.persistKey,
    cancelsReminder: true,
    chatManager: chatManager,
    observer: upload,
  );
  // Öğün kaydı sınıra ulaşmışsa (ör. başka cihazdan yüklendi) null döner.
  if (downloadUrl == null) {
    throw const UploadFailure(
      MealModel.maxImagesReachedMessage,
      canRetry: false,
    );
  }
  if (DateFormatter.isSameDay(upload.createdAt, DateTime.now())) {
    MealReminderService().cancelMealReminder(upload.meal);
  }
}

/// Uploads a meal photo to Firebase Storage and appends it to the meal document.
/// A meal type can have up to [MealModel.maxImages] images.
///
/// Fotoğraf kayda bir işlem (transaction) içinde, kaydın en güncel hâline
/// eklenir ([_addMealImage]): yükleme sürerken öğüne eklenen ya da öğünden
/// silinen fotoğraflar kaybolmaz, geri gelmez. Sınır bu arada dolduysa
/// yüklenen dosyalar silinir ve null döner. Kayıt okunamazsa ya da işlem
/// başarısız olursa hata fırlatılır (yüklenen dosyalar silinir); sohbetin
/// yükleme sırası yeniden dener.
///
/// [chatMessageId] verilirse sohbet mesajı (bu kimlikle) ve sohbet özeti de
/// aynı işlemde yazılır: fotoğraf ya hem öğünde hem sohbette görünür ya
/// hiçbirinde. Kimlik yüklemenin yeniden denemelerinde ve uygulama açılışında
/// geri yüklenen sırada aynı kalır ([PendingUpload.persistKey]): o mesaj
/// zaten yazıldıysa (önceki denemenin yanıtı kayboldu, uygulama kayıt
/// sırasında kapandı) fotoğraf ikinci kez gönderilmez, gönderilmiş sayılır.
///
/// İşlemin sonucu belli değilse (bağlantı hatası, zaman aşımı) yüklenen
/// dosyalar silinmez: kayıt yazılmış olabilir ve silinmiş dosyayı gösterirdi.
/// Yeniden deneme yazılmış mesajı görüp tekrar göndermez.
///
/// [observer] yüklemenin ilerlemesini izler ve iptal edebilir (bkz.
/// [uploadImageWithThumbnail]); dosyalar yüklenmeden iptal edilirse kayıt
/// yazılmaz ve [UploadCancelledException] fırlatılır. Dosyalar yüklenince
/// iptal edilemez ([UploadObserver.onUploaded]).
///
/// [cancelsReminder] true ise öğünün o günkü hatırlatması kalıcı olarak
/// kapanır (bkz. [mealStateFields]). Yalnızca danışanın sohbetten yüklemesi
/// ([uploadChatMealPhoto]) verir; admin test verisi danışanın hatırlatmasını
/// kapatmaz, test verisi silinince hatırlatma geri gelir.
Future<String?> uploadMealImg({
  required String userId,
  required Meals meal,
  required XFile image,
  required String subscriptionId,
  DateTime? overrideDate,
  String? chatMessageId,
  bool cancelsReminder = false,
  ChatManager? chatManager,
  UploadObserver? observer,
}) async {
  try {
    final referenceDate = overrideDate ?? DateTime.now();
    final currentDate = DateFormat('yyyy-MM-dd').format(referenceDate);
    final mealDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('meals')
        .doc(currentDate)
        .collection('mealEntries')
        .doc(meal.name);

    final DocumentReference<Map<String, dynamic>>? messageRef =
        chatMessageId == null ? null : _chatMessageRef(userId, chatMessageId);

    // Bu fotoğraf önceki bir denemede gönderildiyse yeniden yüklenmez.
    if (messageRef != null) {
      final DocumentSnapshot<Map<String, dynamic>> posted =
          await messageRef.get();
      if (posted.exists) {
        observer?.onSaving();
        return posted.data()?['imageUrl'] as String? ?? '';
      }
    }

    // Sınır doluysa hiç yüklenmez. Kayıt okunamazsa deneme başarısız olur.
    if (!await canAddMealImage(
        userId: userId, meal: meal, date: referenceDate)) {
      return null;
    }

    final UploadedImage uploaded = await uploadImageWithThumbnail(
      bytes: await image.readAsBytes(),
      fileName: image.name,
      mimeType: image.mimeType,
      // Ad benzersiz olur: aynı dosya aynı öğüne ikinci kez yüklense de
      // öncekinin üstüne yazılmaz.
      refFor: (fileName) => FirebaseStorage.instance.ref(
        'users/$userId/$_mealPhotosFolder/$currentDate/${meal.name}/'
        '${DateTime.now().millisecondsSinceEpoch}_$fileName',
      ),
      observer: observer,
    );

    // Yükleme bu arada iptal edildiyse kayıt yazılmaz.
    if (observer?.isCancelled ?? false) {
      await uploaded.delete();
      throw const UploadCancelledException();
    }

    final _MealImageWrite result;
    try {
      result = await _addMealImage(
        mealDocRef,
        userId: userId,
        meal: meal,
        subscriptionId: subscriptionId,
        image: uploaded,
        time: referenceDate,
        cancelsReminder: cancelsReminder,
        messageRef: messageRef,
        chatManager: chatManager,
      ).timeout(_mealImageWriteTimeout);
    } on TimeoutException {
      // Sonuç belli değil: dosyalar kalır (bkz. yukarıdaki not).
      throw const UploadFailure(PendingUpload.timeoutText);
    }

    switch (result.kind) {
      case _MealImageWriteKind.limitReached:
        await uploaded.delete();
        return null;
      case _MealImageWriteKind.alreadyPosted:
        // Önceki deneme yazmıştı: bu denemenin dosyaları kullanılmıyor.
        if (result.postedImageUrl != uploaded.url) await uploaded.delete();
      case _MealImageWriteKind.written:
        break;
    }

    // Kayıtlar (ve sohbet mesajı) yazıldı. İşlemle yazılan mesaj yerel
    // önbelleğe sunucudan gelir: bekleyen baloncuk mesaj sohbette görünene
    // kadar kalsın.
    if (messageRef != null) {
      try {
        await messageRef
            .snapshots()
            .timeout(_postedMessageWait)
            .firstWhere((snapshot) => snapshot.exists);
      } catch (e) {
        // Mesaj sonradan gelir; baloncuk yine kalkar.
      }
    }
    observer?.onSaving();
    notifyListeners();

    return result.kind == _MealImageWriteKind.written
        ? uploaded.url
        : result.postedImageUrl ?? '';
  } catch (e) {
    rethrow;
  }
}

/// Deletes a single image from a meal entry.
/// If no images remain, the meal is marked as unchecked. Öğünün o günkü
/// hatırlatma iptali ([mealStateFields]) kalır: hatırlatma geri kurulmaz.
///
/// Fotoğraf sohbete de düşmüşse o mesaj "fotoğraf silindi" notuna çevrilir
/// ([_markChatPhotoDeleted]). Silme nereden yapılırsa yapılsın (sohbet,
/// "Planım", test verisi temizliği) Öğün Fotoğrafları, Görseller sekmesi,
/// "Planım" ve sohbet aynı sonucu gösterir. Öğün kaydı bulunamasa da dosya ve
/// sohbet mesajı temizlenir.
///
/// Fotoğraf kayıttan bir işlem (transaction) içinde, kaydın en güncel
/// hâlinden adresine göre çıkarılır ([_removeMealImage]): bu sırada öğüne
/// eklenen fotoğraflar kaybolmaz. İşlem bağlantı ister; çevrimdışıyken silme
/// hata verir.
///
/// [ignoreStorageFailure] true iken Storage'daki dosya silinemese de (ör.
/// dosya zaten yok) Firestore kaydı temizlenmeye devam eder. Test verisini
/// temizleyen akış ve sohbetten silme bunu kullanır: kayıt sistemde asılı
/// kalmamalı.
Future<void> deleteMealImage({
  required String userId,
  required Meals meal,
  required String imageUrlToDelete,
  DateTime? overrideDate,
  bool ignoreStorageFailure = false,
}) async {
  try {
    final referenceDate = overrideDate ?? DateTime.now();
    final currentDate = DateFormat('yyyy-MM-dd').format(referenceDate);
    final mealDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('meals')
        .doc(currentDate)
        .collection('mealEntries')
        .doc(meal.name);

    // Storage silinemeyince kayıt kalsın diye önce dosya silinir; Storage
    // hatası yok sayılacaksa önce kayıt: geçici bir kayıt hatası silinmiş
    // dosyayı gösteren kayıt bırakmasın.
    if (!ignoreStorageFailure) await deleteFile(imageUrlToDelete);

    final _RemovedMealImage? removed =
        await _removeMealImage(mealDocRef, imageUrlToDelete, meal: meal);

    if (ignoreStorageFailure) {
      try {
        await deleteFile(imageUrlToDelete);
      } catch (e) {
      }
    }

    // Küçük görsel yardımcı bir dosya: silinemezse yok sayılır.
    final String? thumbUrlToDelete = removed?.thumbUrl;
    if (thumbUrlToDelete != null) {
      try {
        await deleteFile(thumbUrlToDelete);
      } catch (e) {
      }
    }

    await _markChatPhotoDeleted(userId, imageUrlToDelete);

    notifyListeners();
  } catch (e) {
    rethrow;
  }
}

/// Danışanın sohbette gönderdiği bir öğün fotoğrafını siler (bkz.
/// [deleteMealImage]): fotoğraf öğün kaydından, Storage'dan (küçük görseliyle)
/// ve sohbetten ("fotoğraf silindi" notu) kalkar.
///
/// Öğün ve gün, fotoğrafın yüklenirken kurulan Storage yolundan çözülür
/// ([mealPhotoLocation]); gece yarısına yakın yüklemelerde bile doğru öğün
/// kaydı bulunur. Yol çözülemezse [fallbackMeal] ve [fallbackDate] kullanılır.
Future<void> deleteChatMealPhoto({
  required String userId,
  required String imageUrl,
  Meals? fallbackMeal,
  DateTime? fallbackDate,
}) async {
  final ({Meals meal, DateTime date})? location =
      mealPhotoLocation(userId, imageUrl) ??
          (fallbackMeal != null && fallbackDate != null
              ? (meal: fallbackMeal, date: fallbackDate)
              : null);
  if (location == null) {
    throw StateError('Fotoğrafın ait olduğu öğün kaydı bulunamadı.');
  }

  await deleteMealImage(
    userId: userId,
    meal: location.meal,
    imageUrlToDelete: imageUrl,
    overrideDate: location.date,
    ignoreStorageFailure: true,
  );
}

/// Öğün fotoğrafının öğünü ve günü, Storage yolundan
/// (`users/{uid}/mealPhotos/{yyyy-MM-dd}/{öğün}/{dosya}`, bkz.
/// [uploadMealImg]). Adres başka bir yola aitse null. Sohbetteki bir öğün
/// fotoğrafından Öğün Fotoğrafları'nda o güne gitmek için de kullanılır.
({Meals meal, DateTime date})? mealPhotoLocation(
    String userId, String imageUrl) {
  try {
    final List<String> parts =
        FirebaseStorage.instance.refFromURL(imageUrl).fullPath.split('/');
    if (parts.length < 6 ||
        parts[0] != 'users' ||
        parts[1] != userId ||
        parts[2] != _mealPhotosFolder) {
      return null;
    }

    final Meals? meal = Meals.fromName(parts[4]);
    if (meal == null) return null;
    return (meal: meal, date: DateFormat('yyyy-MM-dd').parseStrict(parts[3]));
  } catch (e) {
    return null;
  }
}

/// [photoUploaded]: bkz. [mealStateFields].
Future<void> updateMealState(String userId, DateTime date, Meals meal, bool isChecked,
    {bool photoUploaded = false}) async {
    try {
    final currentDate = DateFormat('yyyy-MM-dd').format(date);
    final dayDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('meals')
        .doc(currentDate);

    await dayDocRef.set(
      mealStateFields(meal, isChecked, photoUploaded: photoUploaded),
      SetOptions(merge: true),
    );
  } catch (e) {
  }
}

/// Gün dokümanına (`users/{uid}/meals/{yyyy-MM-dd}`, birleştirerek) yazılan
/// öğün durumu: `meals.<öğün>` işareti; fotoğraf yüklendiyse ([photoUploaded])
/// ayrıca öğünün o günkü hatırlatmasını kapatan işaret
/// ([MealReminderService.REMINDER_CANCELLED_FIELD]). Bu işareti hiçbir yazım
/// geri almaz: fotoğraf silinse de hatırlatma o gün yeniden kurulmaz.
static Map<String, dynamic> mealStateFields(Meals meal, bool isChecked,
        {bool photoUploaded = false}) =>
    {
      'meals': {
        meal.name: isChecked, // mark this meal as "checked" for today
      },
      if (photoUploaded)
        MealReminderService.REMINDER_CANCELLED_FIELD: {meal.name: true},
    };

/// [current] öğün kaydına (yoksa yeni kayıt) bir fotoğraf ekler: adres,
/// küçük görsel (yoksa boş dize) ve saat, listelerin sonuna aynı sırayla
/// eklenir; eski kayıtta eksik küçük görsel ve saatler önce hizalanır.
/// Öğünün saati yeni fotoğrafın saati olur. Sınır ([MealModel.maxImages])
/// doluysa null.
static MealModel? mealWithImageAdded(
  MealModel? current, {
  required Meals meal,
  required String subscriptionId,
  required String imageUrl,
  required String? thumbUrl,
  required DateTime time,
}) {
  if (current != null && current.imageUrls.contains(imageUrl)) return current;
  if (current != null && !current.canAddMoreImages) return null;
  return MealModel(
    mealId: current?.mealId ?? meal.name,
    mealType: meal,
    imageUrls: [...?current?.imageUrls, imageUrl],
    thumbUrls: [...?current?.alignedThumbUrls(), thumbUrl ?? ''],
    imageTimes: [...?current?.alignedImageTimes(), time],
    subscriptionId: subscriptionId,
    timestamp: time,
    description: current?.description,
    calories: current?.calories,
    notes: current?.notes,
    isChecked: true,
  );
}

/// [current] kaydından [index]. fotoğrafı çıkarır; küçük görsel ve saat
/// listeleri aynı sırayla kısalır. Öğünün saati, kalan fotoğrafların en son
/// yükleneni olur. Fotoğraf kalmazsa null.
static MealModel? mealWithImageRemovedAt(MealModel current, int index) {
  final List<String> urls = List<String>.from(current.imageUrls)
    ..removeAt(index);
  if (urls.isEmpty) return null;
  final List<DateTime> times = current.alignedImageTimes()..removeAt(index);
  return MealModel(
    mealId: current.mealId,
    mealType: current.mealType,
    imageUrls: urls,
    thumbUrls: current.alignedThumbUrls()..removeAt(index),
    imageTimes: times,
    subscriptionId: current.subscriptionId,
    timestamp: times.reduce((a, b) => a.isAfter(b) ? a : b),
    description: current.description,
    calories: current.calories,
    notes: current.notes,
    isChecked: true,
  );
}


  /// Öğün fotoğraflarının Storage'daki klasörü (bkz. [uploadMealImg],
  /// [mealPhotoLocation]).
  static const String _mealPhotosFolder = 'mealPhotos';

  /// İşlemin (bkz. [_addMealImage]) en fazla bekleneceği süre: bağlantı
  /// var görünüp paketler gitmiyorsa işlem kendiliğinden bitmeyebilir.
  static const Duration _mealImageWriteTimeout = Duration(seconds: 60);

  /// İşlemle yazılan mesajın sohbetin yerel kopyasına gelmesinin en fazla
  /// bekleneceği süre.
  static const Duration _postedMessageWait = Duration(seconds: 10);

  /// Öğün fotoğrafının sohbet mesajı: kimliği yüklemenin sabit anahtarıdır
  /// (bkz. [uploadMealImg]).
  DocumentReference<Map<String, dynamic>> _chatMessageRef(
    String userId,
    String messageId,
  ) =>
      FirebaseFirestore.instance
          .collection('chats')
          .doc(userId) // In this app, chatId == userId
          .collection('messages')
          .doc(messageId);

  /// [image] fotoğrafını öğün kaydına bir işlem (transaction) içinde, kaydın
  /// en güncel hâline ekler ([mealWithImageAdded]); günün öğün işareti
  /// ([mealStateFields]) ve [messageRef] verilirse sohbet mesajı ile özeti
  /// ([_queueChatPost]) aynı işlemle yazılır: ya hepsi ya hiçbiri. Mesaj
  /// zaten varsa ya da fotoğraf kayıttaysa (önceki deneme yazdı) hiçbir şey
  /// yazılmaz. Sınır bu arada dolduysa hiçbir şey yazılmaz.
  Future<_MealImageWrite> _addMealImage(
    DocumentReference<Map<String, dynamic>> mealDocRef, {
    required String userId,
    required Meals meal,
    required String subscriptionId,
    required UploadedImage image,
    required DateTime time,
    required bool cancelsReminder,
    DocumentReference<Map<String, dynamic>>? messageRef,
    ChatManager? chatManager,
  }) =>
      FirebaseFirestore.instance
          .runTransaction<_MealImageWrite>((transaction) async {
        final DocumentSnapshot<Map<String, dynamic>> fresh =
            await transaction.get(mealDocRef);
        final DocumentSnapshot<Map<String, dynamic>>? posted =
            messageRef == null ? null : await transaction.get(messageRef);
        if (posted != null && posted.exists) {
          return (
            kind: _MealImageWriteKind.alreadyPosted,
            postedImageUrl: posted.data()?['imageUrl'] as String?,
          );
        }
        final MealModel? current =
            fresh.exists ? MealModel.fromDocument(fresh) : null;
        if (current?.imageUrls.contains(image.url) ?? false) {
          return (
            kind: _MealImageWriteKind.alreadyPosted,
            postedImageUrl: image.url,
          );
        }
        final MealModel? merged = mealWithImageAdded(
          current,
          meal: meal,
          subscriptionId: subscriptionId,
          imageUrl: image.url,
          thumbUrl: image.thumbUrl,
          time: time,
        );
        if (merged == null) {
          return (
            kind: _MealImageWriteKind.limitReached,
            postedImageUrl: null,
          );
        }
        transaction.set(mealDocRef, merged.toMap());
        transaction.set(
          mealDocRef.parent.parent!,
          mealStateFields(meal, true, photoUploaded: cancelsReminder),
          SetOptions(merge: true),
        );
        if (messageRef != null) {
          _queueChatPost(
              transaction, messageRef, userId, meal, image, chatManager);
        }
        return (kind: _MealImageWriteKind.written, postedImageUrl: image.url);
      });

  /// [imageUrl] fotoğrafını öğün kaydından bir işlem (transaction) içinde,
  /// kaydın en güncel hâlinden adresine göre çıkarır
  /// ([mealWithImageRemovedAt]); fotoğraf kalmazsa kayıt silinir ve günün
  /// öğün işareti aynı işlemle kalkar. Fotoğraf kayıtta yoksa null.
  Future<_RemovedMealImage?> _removeMealImage(
    DocumentReference<Map<String, dynamic>> mealDocRef,
    String imageUrl, {
    required Meals meal,
  }) =>
      FirebaseFirestore.instance
          .runTransaction<_RemovedMealImage?>((transaction) async {
        final DocumentSnapshot<Map<String, dynamic>> fresh =
            await transaction.get(mealDocRef);
        if (!fresh.exists) return null;
        final MealModel current = MealModel.fromDocument(fresh);
        final int index = current.imageUrls.indexOf(imageUrl);
        if (index < 0) return null;

        final MealModel? remaining = mealWithImageRemovedAt(current, index);
        if (remaining == null) {
          transaction.delete(mealDocRef);
          transaction.set(
            mealDocRef.parent.parent!,
            mealStateFields(meal, false),
            SetOptions(merge: true),
          );
        } else {
          transaction.set(mealDocRef, remaining.toMap());
        }
        return (
          thumbUrl: current.thumbUrlAt(index),
          emptied: remaining == null,
        );
      });

  /// Öğün fotoğrafının sohbet mesajını ve sohbet özetini [transaction]'a
  /// ekler (bkz. [_addMealImage]): mesaj öğün kaydıyla birlikte yazılır.
  void _queueChatPost(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> messageRef,
    String userId,
    Meals meal,
    UploadedImage image,
    ChatManager? chatManager,
  ) {
    final chatId = userId; // In this app, chatId == userId
    final chatDoc = FirebaseFirestore.instance.collection('chats').doc(chatId);

    // Chat summary and the admin unread counters in a single write:
    // set(merge: true) merges nested maps field by field, so the counters do
    // not need the dot-notation that would force a separate update().
    transaction.set(chatDoc, {
      'participants': [chatId, ...ChatManager.adminIds],
      'lastMessage': meal.chatSummary,
      'lastImageUrl': image.url,
      'lastImageThumbUrl': image.thumbUrl ?? '',
      'lastMessageAt': Timestamp.now(),
      'updatedAt': FieldValue.serverTimestamp(),
      'adminUnreadCount': {
        for (final adminUid in ChatManager.adminIds)
          adminUid: FieldValue.increment(1),
      },
      'hasUnreadFor': FieldValue.arrayUnion(ChatManager.adminIds.toList()),
    }, SetOptions(merge: true));

    transaction.set(messageRef, {
      'chatId': chatId,
      'senderId': userId,
      'text': meal.chatCaption,
      ...ChatManager.imageMessageFields(image),
      if (chatManager != null)
        'storagePath': '${Meals.chatMarkerPrefix}$userId/${meal.name}',
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.now(),
    });
  }

  /// Sohbette [imageUrl] fotoğrafını taşıyan mesajı "fotoğraf silindi" notuna
  /// çevirir ("Öğün: Öğle (fotoğraf silindi)"); sohbet listesinin son mesaj
  /// önizlemesi bu fotoğrafsa o da güncellenir. Mesaj silinmez: üzerindeki
  /// ifadeler ve konuşmanın akışı korunur.
  ///
  /// Hatası yutulur: öğün kaydı zaten temizlenmiştir; mesaj buradan
  /// yazılamazsa (ör. yetki) aynı işi `markChatMessagesOfDeletedMealPhotos`
  /// Cloud Function'ı sunucuda yapar.
  Future<void> _markChatPhotoDeleted(String userId, String imageUrl) async {
    try {
      final chatDoc =
          FirebaseFirestore.instance.collection('chats').doc(userId);
      final matches = await chatDoc
          .collection('messages')
          .where('imageUrl', isEqualTo: imageUrl)
          .get();
      if (matches.docs.isEmpty) return;

      String deletedText = Meals.deletedPhotoText;
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final doc in matches.docs) {
        final Object? text = doc.data()['text'];
        deletedText =
            Meals.deletedPhotoChatText(text is String ? text : null);
        batch.update(doc.reference, {
          for (final String field in ChatManager.imageFieldNames)
            field: FieldValue.delete(),
          'storagePath': FieldValue.delete(),
          'text': deletedText,
          'photoDeleted': true,
        });
      }
      await batch.commit();

      final chatSnapshot = await chatDoc.get();
      if (chatSnapshot.data()?['lastImageUrl'] == imageUrl) {
        await chatDoc.update({
          'lastImageUrl': '',
          'lastImageThumbUrl': '',
          'lastMessage': deletedText,
        });
      }
    } catch (e) {
      // Sunucudaki Cloud Function aynı işi yapar.
    }
  }
  

  
  /// Fetches meal data for a specific date
  Future<Map<Meals, bool>> fetchMealStates(String userId, {DateTime? date}) async {
    final effectiveDate = date ?? DateTime.now();
    final currentDate = DateFormat('yyyy-MM-dd').format(effectiveDate);
    Map<Meals, bool> checkedStates = {
      for (var meal in Meals.dietValues) meal: false,
    };
    
    try {
      final mealStateDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('meals')
          .doc(currentDate)
          .get();
          
      if (mealStateDoc.exists) {
        final data = mealStateDoc.data();
        if (data != null && data['meals'] != null) {
          final mealsData = data['meals'] as Map<String, dynamic>;
          
          for (var entry in mealsData.entries) {
            final mealType = Meals.fromName(entry.key);
            if (mealType != null) {
              checkedStates[mealType] = entry.value as bool;
            }
          }
        }
      }
    } catch (e) {
    }
    
    return checkedStates;
  }

  /// Küçük görseli olmayan eski bir fotoğraf için küçük görseli üretip
  /// kaydeder.
  ///
  /// Liste ekranı böyle bir fotoğrafı göstermek için orijinali indirmek
  /// zorunda kalır; indirdiği baytları buraya verir, küçük görsel bir kez
  /// üretilip yüklenir ve öğün kaydına yazılır. Sonraki her açılışta (ve diğer
  /// tüm cihazlarda) yalnızca küçük görsel iner.
  ///
  /// Kayıt bir işlem (transaction) içinde güncellenir: fotoğraf o arada
  /// silinmiş ya da listedeki yeri değişmişse yanlış yere yazılmaz.
  Future<void> backfillThumbnail({
    required String userId,
    required Meals meal,
    required DateTime date,
    required String imageUrl,
    required Uint8List originalBytes,
  }) async {
    final String dateKey = DateFormat('yyyy-MM-dd').format(date);
    final DocumentReference<Map<String, dynamic>> mealDocRef =
        FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('meals')
            .doc(dateKey)
            .collection('mealEntries')
            .doc(meal.name);

    // Aynı fotoğrafı iki cihaz aynı anda açtıysa ikinci üretim boşa gitmesin.
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await mealDocRef.get();
    if (!snapshot.exists) return;
    final MealModel current = MealModel.fromDocument(snapshot);
    final int index = current.imageUrls.indexOf(imageUrl);
    if (index < 0 || current.thumbUrlAt(index) != null) return;

    final ThumbnailData? thumb = await generateThumbnail(originalBytes);
    if (thumb == null) return;

    final Reference originalRef = FirebaseStorage.instance.refFromURL(imageUrl);
    final Reference thumbRef = thumbnailRefFor(originalRef, thumb.extension);
    await thumbRef.putData(
      thumb.bytes,
      SettableMetadata(contentType: thumb.contentType),
    );
    final String thumbUrl = await thumbRef.getDownloadURL();

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> fresh =
          await transaction.get(mealDocRef);
      if (!fresh.exists) return;
      final MealModel model = MealModel.fromDocument(fresh);
      final int freshIndex = model.imageUrls.indexOf(imageUrl);
      if (freshIndex < 0) return;
      final List<String> thumbs = model.alignedThumbUrls();
      if (thumbs[freshIndex].isNotEmpty) return;
      thumbs[freshIndex] = thumbUrl;
      transaction.update(mealDocRef, {'thumbUrls': thumbs});
    });
  }

  /// Deletes a file from Firebase Storage
  ///
  /// @param imageUrl The URL of the image to delete
  Future<void> deleteFile(String imageUrl) async {
    try {
      final Reference ref = FirebaseStorage.instance.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      rethrow;
    }
  }
}

/// [MealManager._addMealImage] işleminin sonucu.
enum _MealImageWriteKind {
  /// Fotoğraf (ve sohbet mesajı) yazıldı.
  written,

  /// Önceki bir deneme yazmıştı; bu deneme bir şey yazmadı.
  alreadyPosted,

  /// Öğünün fotoğraf sınırı doldu; bir şey yazılmadı.
  limitReached,
}

/// [_MealImageWriteKind] ve yazılmış mesajın fotoğraf adresi (fotoğraf
/// sonradan silindiyse null).
typedef _MealImageWrite = ({_MealImageWriteKind kind, String? postedImageUrl});

/// Öğün kaydından çıkarılan fotoğrafın küçük görseli ve öğünde fotoğraf
/// kalıp kalmadığı (bkz. [MealManager._removeMealImage]).
typedef _RemovedMealImage = ({String? thumbUrl, bool emptied});
