import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/filter_params.dart';
import '../providers/chat_manager_new.dart';

final Logger logger = Logger.forClass(MealManager);

/// Manages meal state and provides functionality for uploading and fetching meals
/// Handles the storage and retrieval of meal data from Firestore
class MealManager extends ChangeNotifier {
static const MEAL_RANGE_DAYS=7;

  /// Toplu (çok danışanlı) sorgularda aynı anda açılan Firestore
  /// isteği sayısı. Bkz. [fetchMealsOfUsersForDate].
  static const int USER_BATCH_SIZE = 10;

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

      // Apply meal type filter if provided
      if (filterParams?.mealType != null) {
        all = all.where((m) => m.mealType.name == filterParams!.mealType).toList();
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
      logger.err('Error fetching meals (unified nested path): {}', [e]);
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
      
      logger.debug('Fetching meals for {} dates in range', [dateKeys.length]);
      
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
              logger.err('Error parsing meal document {}: {}', [doc.id, e]);
            }
          }
          return dateMeals;
        } catch (e) {
          logger.err('Error fetching meals for date {}: {}', [dateKey, e]);
          return <MealModel>[];
        }
      }).toList();
      
      // Wait for all queries to complete
      final results = await Future.wait(futures);
      
      // Flatten results
      for (final dateMeals in results) {
        meals.addAll(dateMeals);
      }
      
      logger.info('Fetched {} meal images for date range {} to {}',
        [meals.length, DateFormat('yyyy-MM-dd').format(startDate), DateFormat('yyyy-MM-dd').format(endDate)]);
    } catch (e) {
      logger.err('Error fetching meal images in range: {}', [e]);
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
  Future<Map<String, List<MealModel>>> fetchMealsOfUsersForDate({
    required List<String> userIds,
    required DateTime date,
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

      for (int i = 0; i < batch.length; i++) {
        final List<MealModel> withPhotos = batchResults[i]
            .where((meal) => meal.imageUrls.isNotEmpty)
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        if (withPhotos.isNotEmpty) {
          mealsByUser[batch[i]] = withPhotos;
        }
      }
    }

    logger.info('Fetched meal photos for date {}. users={} ofRequested={}',
        [dateKey, mealsByUser.length, userIds.length]);
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
          logger.err('Error parsing meal document: {}', [e]);
        }
      }
      
      logger.info('Fetched {} meal images for date {}', [meals.length, currentDate]);
    } catch (e) {
      logger.err('Error fetching meal images: {}', [e]);
    }
    
    return meals;
  }

/// Uploads a meal photo to Firebase Storage and appends it to the meal document.
/// A meal type can have up to [MealModel.maxImages] images.
Future<String?> uploadMealImg({
  required String userId,
  required Meals meal,
  required XFile image,
  required String subscriptionId,
  DateTime? overrideDate,
  bool alsoPostToChat = false,
  ChatManager? chatManager,
}) async {
  try {
    logger.info('Uploading meal photo. meal={}', [meal.name]);

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
          logger.warn('Max images reached for meal: {}', [meal.name]);
          return null;
        }
      }
    } catch (e) {
      logger.err('Error reading previous meal doc: {}', [e]);
    }

    final result = await _uploadImg(
      image,
      meal: meal,
      userId: userId,
      overrideDate: referenceDate,
    );

    if (!result.isUploadOk || result.downloadUrl == null) {
      logger.err('Image upload failed: {}', [result.errorMessage ?? 'Unknown error']);
      return null;
    }

    // Append the new URL to existing list
    final existingUrls = previousMealModel?.imageUrls ?? [];
    final updatedUrls = [...existingUrls, result.downloadUrl!];

    final mergedMealModel = MealModel(
      mealId: previousMealModel?.mealId ?? mealDocRef.id,
      mealType: meal,
      imageUrls: updatedUrls,
      subscriptionId: subscriptionId,
      timestamp: referenceDate,
      description: previousMealModel?.description,
      calories: previousMealModel?.calories,
      notes: previousMealModel?.notes,
      isChecked: true,
    );

    // Three different documents (meal entry, the day's checklist, the chat):
    // independent writes, so they are issued together instead of one after the
    // other.
    await Future.wait([
      mealDocRef.set(mergedMealModel.toMap()),
      updateMealState(userId, referenceDate, meal, true),
      if (alsoPostToChat)
        _postToChat(userId, meal, result.downloadUrl!, chatManager),
    ]);

    notifyListeners();

    logger.info('Meal upload finished. downloadUrl={}', [result.downloadUrl]);
    return result.downloadUrl;
  } catch (e, st) {
    logger.err('Error uploading meal: {}, Stack:', [e, st]);
    rethrow;
  }
}

/// Deletes a single image from a meal entry.
/// If no images remain, the meal is marked as unchecked.
Future<void> deleteMealImage({
  required String userId,
  required Meals meal,
  required String imageUrlToDelete,
  DateTime? overrideDate,
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
    if (!mealDoc.exists) return;

    final mealModel = MealModel.fromDocument(mealDoc);
    final updatedUrls = List<String>.from(mealModel.imageUrls)
      ..remove(imageUrlToDelete);

    // Delete the file from Storage
    await deleteFile(imageUrlToDelete);

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
          subscriptionId: mealModel.subscriptionId,
          timestamp: mealModel.timestamp,
          description: mealModel.description,
          calories: mealModel.calories,
          notes: mealModel.notes,
          isChecked: true,
        ).toMap(),
      );
    }

    notifyListeners();
    logger.info('Deleted image from meal {}. Remaining: {}',
        [meal.name, updatedUrls.length]);
  } catch (e) {
    logger.err('Error deleting meal image: {}', [e]);
    rethrow;
  }
}

  /// Bir danışanın [date] gününe ait TÜM öğün fotoğraflarını siler ve o günün
  /// öğün işaretlerini sıfırlar. Silinen fotoğraf sayısını döner.
  ///
  /// Test verisi üreten ekranın (mock yükleme sayfası) aynı gün için tekrar
  /// tekrar çalışabilmesi için var: bir öğün en fazla [MealModel.maxImages]
  /// görsel taşıdığından, önce temizlenmezse ikinci deneme sessizce boşa
  /// giderdi.
  ///
  /// Storage'daki dosya silinemezse (ör. dosya zaten yok) o dosya atlanır;
  /// Firestore kaydının silinmesi yine de sürer.
  Future<int> deleteMealsForDate({
    required String userId,
    required DateTime date,
  }) async {
    final String dateKey = DateFormat('yyyy-MM-dd').format(date);
    int deletedPhotos = 0;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('meals')
          .doc(dateKey)
          .collection('mealEntries')
          .get();

      for (final doc in snapshot.docs) {
        MealModel? meal;
        try {
          meal = MealModel.fromDocument(doc);
        } catch (e) {
          logger.err('Error parsing meal document {} while deleting: {}',
              [doc.id, e]);
        }

        for (final String url in meal?.imageUrls ?? const <String>[]) {
          try {
            await deleteFile(url);
            deletedPhotos++;
          } catch (e) {
            logger.warn('Could not delete storage file {}: {}', [url, e]);
          }
        }

        await doc.reference.delete();
        if (meal != null) {
          await updateMealState(userId, date, meal.mealType, false);
        }
      }

      notifyListeners();
      logger.info('Deleted meals for user {} date {}. photos={} entries={}',
          [userId, dateKey, deletedPhotos, snapshot.docs.length]);
    } catch (e) {
      logger.err('Error deleting meals for user {} date {}: {}',
          [userId, dateKey, e]);
      rethrow;
    }

    return deletedPhotos;
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

    logger.info('Updated state for {} to {} for date {}', [meal.name, isChecked, currentDate]);
  } catch (e) {
    logger.err('Error updating meal state: {}', [e]);
  }
}


  /// Posts the meal image to the user's chat
  Future<void> _postToChat(String userId, Meals meal, String imageUrl, ChatManager? chatManager) async {
    try {
      // If we have a ChatManager instance, use it to post the image directly
      final chatId = userId; // In this app, chatId == userId
      final chatDoc = FirebaseFirestore.instance.collection('chats').doc(chatId);
      
      // Chat summary and the admin unread counters in a single write:
      // set(merge: true) merges nested maps field by field, so the counters do
      // not need the dot-notation that would force a separate update().
      await chatDoc.set({
        'participants': [chatId, ...ChatManager.adminIds],
        'lastMessage': 'Öğün Fotoğrafı (${meal.label})',
        'lastImageUrl': imageUrl,
        'lastMessageAt': Timestamp.now(),
        'updatedAt': FieldValue.serverTimestamp(),
        'adminUnreadCount': {
          for (final adminUid in ChatManager.adminIds)
            adminUid: FieldValue.increment(1),
        },
        'hasUnreadFor': FieldValue.arrayUnion(ChatManager.adminIds.toList()),
      }, SetOptions(merge: true));

      // Add message to chat
      final msgData = <String, dynamic>{
        'chatId': chatId,
        'senderId': userId,
        'text': 'Öğün: ${meal.label}',
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': Timestamp.now(),
      };
      if (chatManager != null) {
        msgData['storagePath'] = 'meals/$userId/${meal.name}';
      }
      final refMsg = await chatDoc.collection('messages').add(msgData);
      
      logger.info('Meal image posted to chat. messageId={}', [refMsg.id]);
    } catch (e) {
      logger.err('Error posting to chat: {}', [e]);
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
      logger.err('Error fetching meal states: {}', [e]);
    }
    
    return checkedStates;
  }

  /// Uploads a file to Firebase Storage
  ///
  /// Handles uploading image files to appropriate paths in Firebase Storage based on
  /// whether they are meal photos or chat photos.
  ///
  /// @param imageFile The image file to upload
  /// @param meal Optional meal type if this is a meal photo
  /// @param userId The ID of the user to whom the image belongs
  ///
  /// @return An UploadResult containing the download URL or error message
  Future<UploadResult> _uploadImg(
    XFile? imageFile, {
    Meals? meal,
    required String userId,
    DateTime? overrideDate,
  }) async {
    if (imageFile == null) {
      return UploadResult(errorMessage: 'No image selected for upload.');
    }

    try {
      String fileName = imageFile.name;
      final effectiveDate = overrideDate ?? DateTime.now();
      String date = DateFormat('yyyy-MM-dd').format(effectiveDate);
      String path;

      if (meal != null) {
        path = 'users/$userId/mealPhotos/$date/${meal.name}/$fileName';
      } else {
        path = 'users/$userId/chatPhotos/$date/$fileName';
      }

      Reference ref = FirebaseStorage.instance.ref(path);
     // logger.debug('Uploading file to path: $path');

      // Read the file as bytes
      Uint8List imageData = await imageFile.readAsBytes();

      // Determine the content type
      String? mimeType = imageFile.mimeType;

      SettableMetadata metadata = SettableMetadata(contentType: mimeType);

      // UploadTask uploadTask = ref.putData(imageData, metadata);
      await ref.putData(imageData, metadata);

      // await uploadTask;

      // After uploading, get the download URL
      String downloadUrl = await ref.getDownloadURL();
      logger.info('Uploaded file to path: $path, downloadUrl: $downloadUrl');
      return UploadResult(downloadUrl: downloadUrl);
    } on FirebaseException catch (e) {
      logger.err('FirebaseException Error during file upload: {}',
          [e.message ?? 'exception does not have message.']);
      rethrow;
    } catch (e2) {
      logger.err('Unexpected error during file upload: {}', [e2.toString()]);
      rethrow;
    }
  }

  /// Deletes a file from Firebase Storage
  ///
  /// @param imageUrl The URL of the image to delete
  Future<void> deleteFile(String imageUrl) async {
    try {
      final Reference ref = FirebaseStorage.instance.refFromURL(imageUrl);
      await ref.delete();
      logger.info('Deleted file at URL: $imageUrl');
    } catch (e) {
      logger.err('Error deleting file at URL {}: {}', [imageUrl, e.toString()]);
      rethrow;
    }
  }
}
/// Represents the result of an image upload operation
class UploadResult {
  final String? downloadUrl;
  final String? errorMessage;

  /// Indicates whether the upload was successful
  bool get isUploadOk => downloadUrl != null && errorMessage == null;

  UploadResult({this.downloadUrl, this.errorMessage});
}