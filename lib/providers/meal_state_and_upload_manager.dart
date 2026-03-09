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

/// Uploads a meal photo to Firebase Storage and updates the meal document
/// *without* wiping possible future-user-entered fields (description, calories, notes).
/// önceden tamamını silip yapıyodu şuan sadece modify ediyo merge ile
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

    // 1) Prepare references for "today" and this specific meal
    //
    // Firestore path (per user, per day, per meal):
    //   users/{userId}/meals/{yyyy-MM-dd}/mealEntries/{meal.name}
    //
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

    // 2) Try to read the existing document:
    //    - If it exists, we:
    //        * parse it into MealModel
    //        * delete ONLY the old image from Storage
    //    - We do NOT delete the Firestore document itself.
    try {
      final mealDoc = await mealDocRef.get();

      if (mealDoc.exists) {
        previousMealModel = MealModel.fromDocument(mealDoc);

        // If there was an old image, delete it from Storage to avoid leaks.
        if (previousMealModel.imageUrl.isNotEmpty) {
          await deleteFile(previousMealModel.imageUrl);
          logger.info('Previous meal image deleted for meal: {}', [meal.name]);
        }
      }
    } catch (e) {
      logger.err('Error handling previous meal image/doc: {}', [e]);
      // We still continue; worst case we just overwrite with new data.
    }

    // 3) Upload the new image file to Firebase Storage.
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

    // 4) Build the new MealModel, but KEEP user-entered fields from previous doc:
    //
    //    - Always update:
    //        * imageUrl          -> new image URL
    //        * timestamp         -> now
    //        * subscriptionId    -> from parameter
    //        * isChecked         -> true  (this meal is now "done" for today)
    //
    //    - Preserve from previousMealModel (if it existed):
    //        * description
    //        * calories
    //        * notes
    //
    //    This way, changing the photo does NOT wipe those fields.
    final mergedMealModel = MealModel(
      mealId: previousMealModel?.mealId ?? mealDocRef.id,
      mealType: meal,
      imageUrl: result.downloadUrl!,
      subscriptionId: subscriptionId,
      timestamp: referenceDate,
      description: previousMealModel?.description,
      calories: previousMealModel?.calories,
      notes: previousMealModel?.notes,
      isChecked: true,
    );

    // 5) Write merged data back to Firestore.
    //    .set() here will:
    //      - create the doc if it didn't exist
    //      - overwrite it with the merged fields if it did
    await mealDocRef.set(mergedMealModel.toMap());

    // 6) Update the "meals" map on the day document:
    //
    // users/{userId}/meals/{currentDate}
    //
    // Example document after multiple meals:
    // {
    //   "meals": {
    //     "BREAKFAST": true,
    //     "LUNCH": true,
    //     "DINNER": false
    //   }
    // }
    //
    // merge: true means we only touch this one meal key.
    await updateMealState(userId, referenceDate, meal,true /*isChecked*/);

    // 7) Optionally post the new image to chat
    if (alsoPostToChat) {
      await _postToChat(userId, meal, result.downloadUrl!, chatManager);
    }

    // 8) Notify listeners so UI can refresh
    notifyListeners();

    logger.info('Meal upload finished. downloadUrl={}', [result.downloadUrl]);
    return result.downloadUrl;
  } catch (e, st) {
    logger.err('Error uploading meal: {}, Stack:', [e,st]);
    rethrow;
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
      
      // Update chat document with image info
      await chatDoc.set({
        'participants': [chatId, ...ChatManager.adminIds],
        'lastMessage': 'Öğün Fotoğrafı (${meal.label})',
        'lastImageUrl': imageUrl,
        'lastMessageAt': Timestamp.now(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      // Increment admin unread counts via update() (dot-notation needs update())
      final unreadData = <String, dynamic>{};
      for (final adminUid in ChatManager.adminIds) {
        unreadData['adminUnreadCount.$adminUid'] = FieldValue.increment(1);
      }
      unreadData['hasUnreadFor'] = FieldValue.arrayUnion(ChatManager.adminIds.toList());
      await chatDoc.update(unreadData);
      
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