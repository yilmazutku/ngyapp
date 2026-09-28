import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/meal_model.dart';
import '../models/filter_params.dart';
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
  /// Danışan fotoğrafı ister "Planım" sayfasından ister sohbetten yüklesin
  /// [uploadMealImg] hep bu dokümanı yazdığı için iki yol da bu tek kaynaktan
  /// okunur.
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

/// Uploads a meal photo to Firebase Storage and appends it to the meal document.
/// A meal type can have up to [MealModel.maxImages] images.
///
/// [alsoPostToChat] true iken fotoğraf öğüne kaydedilip sohbete
/// gönderilemezse [MealChatPostException] fırlatılır: fotoğraf öğünde durur,
/// çağıran kullanıcıya sohbette görünmeyeceğini söyleyebilir.
///
/// [observer] yüklemenin ilerlemesini izler ve iptal edebilir (bkz.
/// [uploadImageWithThumbnail]); iptal edilirse kayıt yazılmaz ve
/// [UploadCancelledException] fırlatılır.
Future<String?> uploadMealImg({
  required String userId,
  required Meals meal,
  required XFile image,
  required String subscriptionId,
  DateTime? overrideDate,
  bool alsoPostToChat = false,
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

    MealModel? previousMealModel;

    try {
      final mealDoc = await mealDocRef.get();
      if (mealDoc.exists) {
        previousMealModel = MealModel.fromDocument(mealDoc);

        if (!previousMealModel.canAddMoreImages) {
          return null;
        }
      }
    } catch (e) {
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

    // Append the new URL to existing list (küçük görsel listesi de aynı
    // sırayla büyür; eski kayıtta eksikse boş dizeyle hizalanır).
    final existingUrls = previousMealModel?.imageUrls ?? [];
    final updatedUrls = [...existingUrls, uploaded.url];
    final existingThumbs = previousMealModel?.alignedThumbUrls() ?? <String>[];
    final updatedThumbs = [...existingThumbs, uploaded.thumbUrl ?? ''];
    final existingTimes =
        previousMealModel?.alignedImageTimes() ?? <DateTime>[];
    final updatedTimes = [...existingTimes, referenceDate];

    final mergedMealModel = MealModel(
      mealId: previousMealModel?.mealId ?? mealDocRef.id,
      mealType: meal,
      imageUrls: updatedUrls,
      thumbUrls: updatedThumbs,
      imageTimes: updatedTimes,
      subscriptionId: subscriptionId,
      timestamp: referenceDate,
      description: previousMealModel?.description,
      calories: previousMealModel?.calories,
      notes: previousMealModel?.notes,
      isChecked: true,
    );

    // Yükleme bu arada iptal edildiyse kayıt yazılmaz.
    if (observer?.isCancelled ?? false) {
      await uploaded.delete();
      throw const UploadCancelledException();
    }

    // Three different documents (meal entry, the day's checklist, the chat):
    // independent writes, so they are issued together instead of one after the
    // other. Sohbet yazımının hatası ayrıca tutulur: öğün kaydı yine de
    // tamamlanmış olur, yükleme "başarısız" sayılıp fotoğraf tekrar
    // yüklenmesin.
    Object? chatPostError;
    final Future<void> writes = Future.wait([
      mealDocRef.set(mergedMealModel.toMap()),
      updateMealState(userId, referenceDate, meal, true),
      if (alsoPostToChat)
        _postToChat(userId, meal, uploaded, chatManager)
            .catchError((Object e) {
          chatPostError = e;
        }),
    ]);
    // Yazımlar yerel önbelleğe düştü: sohbetteki mesaj şimdiden görünür.
    observer?.onSaving();
    await writes;

    notifyListeners();

    if (chatPostError != null) {
      throw MealChatPostException(uploaded.url, chatPostError!);
    }

    return uploaded.url;
  } catch (e) {
    rethrow;
  }
}

/// Deletes a single image from a meal entry.
/// If no images remain, the meal is marked as unchecked.
///
/// Fotoğraf sohbete de düşmüşse o mesaj "fotoğraf silindi" notuna çevrilir
/// ([_markChatPhotoDeleted]). Silme nereden yapılırsa yapılsın (sohbet,
/// "Planım", test verisi temizliği) Öğün Fotoğrafları, Görseller sekmesi,
/// "Planım" ve sohbet aynı sonucu gösterir. Öğün kaydı bulunamasa da dosya ve
/// sohbet mesajı temizlenir.
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

    final mealDoc = await mealDocRef.get();
    final MealModel? mealModel =
        mealDoc.exists ? MealModel.fromDocument(mealDoc) : null;
    final int index = mealModel?.imageUrls.indexOf(imageUrlToDelete) ?? -1;
    final String? thumbUrlToDelete =
        index >= 0 ? mealModel!.thumbUrlAt(index) : null;

    // Delete the file from Storage
    try {
      await deleteFile(imageUrlToDelete);
    } catch (e) {
      if (!ignoreStorageFailure) rethrow;
    }

    // Küçük görsel yardımcı bir dosya: silinemese de kayıt temizlenir.
    if (thumbUrlToDelete != null) {
      try {
        await deleteFile(thumbUrlToDelete);
      } catch (e) {
      }
    }

    if (mealModel != null && index >= 0) {
      final updatedUrls = List<String>.from(mealModel.imageUrls)
        ..removeAt(index);
      final updatedThumbs = mealModel.alignedThumbUrls()..removeAt(index);
      final updatedTimes = mealModel.alignedImageTimes()..removeAt(index);

      if (updatedUrls.isEmpty) {
        // No images left — remove the document and uncheck
        await mealDocRef.delete();
        await updateMealState(userId, referenceDate, meal, false);
      } else {
        await mealDocRef.set(
          MealModel(
            mealId: mealModel.mealId,
            mealType: meal,
            imageUrls: updatedUrls,
            thumbUrls: updatedThumbs,
            imageTimes: updatedTimes,
            subscriptionId: mealModel.subscriptionId,
            // Öğünün saati, kalan fotoğrafların en son yükleneni olur.
            timestamp: updatedTimes.reduce((a, b) => a.isAfter(b) ? a : b),
            description: mealModel.description,
            calories: mealModel.calories,
            notes: mealModel.notes,
            isChecked: true,
          ).toMap(),
        );
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

Future<void> updateMealState(String userId, DateTime date, Meals meal, bool isChecked) async {
    try {
    final currentDate = DateFormat('yyyy-MM-dd').format(date);
    final dayDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('meals')
        .doc(currentDate);

    await dayDocRef.set({
      'meals': {
        meal.name: isChecked, // mark this meal as "checked" for today
      },
    }, SetOptions(merge: true));
  } catch (e) {
  }
}


  /// Öğün fotoğraflarının Storage'daki klasörü (bkz. [uploadMealImg],
  /// [mealPhotoLocation]).
  static const String _mealPhotosFolder = 'mealPhotos';

  /// Posts the meal image to the user's chat. Hata yutulmaz; çağıran
  /// ([uploadMealImg]) sohbete düşmeyen fotoğrafı kullanıcıya bildirir.
  ///
  /// Özet ve mesaj tek toplu yazımla gider (bkz. [ChatManager.sendTextTo]):
  /// mesaj yerelde hemen görünür, çevrimdışıyken de; ikisi birbirinden kopmaz.
  Future<void> _postToChat(
    String userId,
    Meals meal,
    UploadedImage image,
    ChatManager? chatManager,
  ) async {
    final chatId = userId; // In this app, chatId == userId
    final chatDoc = FirebaseFirestore.instance.collection('chats').doc(chatId);

    // Chat summary and the admin unread counters in a single write:
    // set(merge: true) merges nested maps field by field, so the counters do
    // not need the dot-notation that would force a separate update().
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    batch.set(chatDoc, {
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

    batch.set(chatDoc.collection('messages').doc(), {
      'chatId': chatId,
      'senderId': userId,
      'text': meal.chatCaption,
      ...ChatManager.imageMessageFields(image),
      if (chatManager != null)
        'storagePath': '${Meals.chatMarkerPrefix}$userId/${meal.name}',
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.now(),
    });
    await batch.commit();
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
/// Öğün fotoğrafı öğün kaydına eklendi ama sohbete gönderilemedi
/// (bkz. [MealManager.uploadMealImg]).
class MealChatPostException implements Exception {
  /// Öğüne kaydedilen fotoğrafın adresi.
  final String downloadUrl;
  final Object cause;

  const MealChatPostException(this.downloadUrl, this.cause);

  @override
  String toString() => 'MealChatPostException($downloadUrl): $cause';
}
