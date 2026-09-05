import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../models/diet_model.dart';
import '../models/logger.dart';
import '../models/filter_params.dart';
import '../utils/storage_upload.dart';

/// Manages diet data for users
/// Provides functionality for fetching, creating, updating, and deleting diet documents
class DietProvider extends ChangeNotifier {
  final Logger logger = Logger.forClass(DietProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Returns true when any meal key or content line in [subtitles] contains
  /// the already-lower-cased [query]. Safe to call with a null map.
  bool _subtitlesContainQuery(Map<String, dynamic>? subtitles, String query) =>
      _countSubtitleMatches(subtitles, query) > 0;

  /// Counts how many meal keys / content lines in [subtitles] contain the
  /// already-lower-cased [query]. Used to rank search results. Safe to call
  /// with a null map (weekday-only diets have no weekend subtitles).
  int _countSubtitleMatches(Map<String, dynamic>? subtitles, String query) {
    if (subtitles == null) return 0;
    int matchCount = 0;
    for (final entry in subtitles.entries) {
      if (entry.key.toLowerCase().contains(query)) matchCount++;
      final value = entry.value;
      final mealItems = value is Map ? value['content'] : null;
      if (mealItems is List) {
        for (final item in mealItems) {
          final content = item is Map
              ? (item['content']?.toString().toLowerCase() ?? '')
              : '';
          if (content.contains(query)) matchCount++;
        }
      }
    }
    return matchCount;
  }

  /// Fetches the most recent diet document for a user.
  ///
  /// Returns the full [DietDocument] (weekday `subtitles` + optional
  /// `weekendSubtitles`) so callers can decide how to present weekday vs
  /// weekend menus. Returns null if the user has no diet lists.
  ///
  /// @param userId The ID of the user whose latest diet to fetch
  Future<DietDocument?> fetchLatestDietDocument(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('dietLists')
          .orderBy('uploadTime', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        logger.info('No diet lists found for user {}', [userId]);
        return null;
      }

      final latestDoc = querySnapshot.docs.first;
      if (latestDoc.data()['subtitles'] == null) {
        logger.warn('Latest diet list has no subtitles for user {}', [userId]);
        return null;
      }

      logger.info('Found latest diet document for user {}', [userId]);
      return DietDocument.fromSnapshot(latestDoc);
    } catch (e) {
      logger.err('Error fetching latest diet document: {}', [e]);
      rethrow;
    }
  }

  /// Fetches diet documents for a specific user
  /// 
  /// @param userId The ID of the user whose diets to fetch
  /// @param showAllData If true, returns all diet documents regardless of any filters
  /// @param filterParams Optional filter parameters for Firebase-side filtering
  /// 
  /// @return A list of DietDocument objects representing the user's diets
  Future<List<DietDocument>> fetchDiets(
      {required String userId, required bool showAllData, DietFilterParams? filterParams}) async {
    try {
      Query query = _firestore
          .collection('users')
          .doc(userId)
          .collection('dietLists');

      // Apply date range filter if provided
      if (filterParams?.dateRange != null) {
        query = query
            .where('uploadTime', isGreaterThanOrEqualTo: filterParams!.dateRange!.start)
            .where('uploadTime', isLessThanOrEqualTo: DateTime(
              filterParams.dateRange!.end.year,
              filterParams.dateRange!.end.month,
              filterParams.dateRange!.end.day,
              23,
              59,
              59,
            ));
      }
      
      query = query.orderBy('uploadTime', descending: true);

      final snapshot = await query.get();

      // Debug: Print raw data
      // for (var doc in snapshot.docs) {
      //   logger.info('Raw document data for ${doc.id}: ${doc.data()}');
      // }

      List<DietDocument> diets = [];
      for (var doc in snapshot.docs) {
        try {
          final diet = DietDocument.fromSnapshot(doc);
          diets.add(diet);
        } catch (e, s) {
          logger.err('Error parsing diet document ${doc.id}: {}, {}', [e,s]);
          // Continue with next document instead of failing completely
          continue;
        }
      }

      // Apply client-side search filter if needed (complex content search)
      if (filterParams?.searchQuery != null && filterParams!.searchQuery!.isNotEmpty) {
        final q = filterParams.searchQuery!.toLowerCase();
        diets = diets.where((diet) {
          // Search in display name
          if (diet.displayName.toLowerCase().contains(q)) return true;

          // Search in both weekday and weekend meal content
          try {
            if (_subtitlesContainQuery(diet.subtitles, q)) return true;
            if (_subtitlesContainQuery(diet.weekendSubtitles, q)) return true;
          } catch (_) {}

          return false;
        }).toList();
      }

      logger.info('Fetched ${diets.length} diets for user $userId with filters: {}', [filterParams?.toDebugMap()]);
      return diets;
    } catch (e, s) {
      logger.err('Error fetching diets: $e', [s]);
      return [];
    }
  }

  /// Searches diet documents for a specific user based on query and date range
  /// 
  /// @param userId The ID of the user whose diets to search
  /// @param searchQuery Optional search query to filter diets
  /// @param dateRange Optional date range to filter diets
  /// @param subscriptionId Optional subscription ID to filter diets
  /// 
  /// @return A list of DietDocument objects that match the search criteria, sorted by relevance
  Future<List<DietDocument>> searchDiets({
    required String userId,
    String? searchQuery,
    DateTimeRange? dateRange,
    String? subscriptionId,
  }) async {
    try {
      // Fetch all diets for the user
      List<DietDocument> allDiets = await fetchDiets(
        userId: userId, 
        showAllData: true
      );
      
      // If no filters, return all diets
      if ((searchQuery == null || searchQuery.isEmpty) && 
          dateRange == null && 
          subscriptionId == null) {
        return allDiets;
      }
      
      // Filter by subscription ID if provided
      if (subscriptionId != null) {
        allDiets = allDiets.where((diet) {
          // This assumes DietDocument has a subscriptionId field
          // If not, you would need to add it or handle differently
          return diet.subscriptionId == subscriptionId;
        }).toList();
      }
      
      // Filter by date range if provided
      if (dateRange != null) {
        final endOfDay = DateTime(
          dateRange.end.year,
          dateRange.end.month,
          dateRange.end.day,
          23,
          59,
          59,
        );
        
        allDiets = allDiets.where((diet) {
          if (diet.uploadTime == null) return false;
          return diet.uploadTime!.isAfter(dateRange.start) && 
                 diet.uploadTime!.isBefore(endOfDay);
        }).toList();
      }
      
      // Search in diet content if query provided
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final lowerQuery = searchQuery.toLowerCase();
        
        // Calculate match counts for sorting by relevance
        Map<String, int> matchCounts = {};
        
        // Filter diets based on search query
        allDiets = allDiets.where((diet) {
          // Search in diet name
          if (diet.displayName.toLowerCase().contains(lowerQuery)) {
            matchCounts[diet.docId] = (matchCounts[diet.docId] ?? 0) + 1;
            return true;
          }

          // Search in both weekday and weekend meal content
          int matchCount = 0;

          try {
            matchCount += _countSubtitleMatches(diet.subtitles, lowerQuery);
            matchCount += _countSubtitleMatches(diet.weekendSubtitles, lowerQuery);

            // Store match count for this diet
            if (matchCount > 0) {
              matchCounts[diet.docId] = matchCount;
            }
          } catch (e, s) {
            logger.err('Error searching diet content: $e', [s]);
            // On error, include the diet in results to avoid hiding data due to errors
            return true;
          }

          return matchCount > 0;
        }).toList();
        
        // Sort by match count (descending) if search query provided
        if (searchQuery.isNotEmpty) {
          allDiets.sort((a, b) {
            final aCount = matchCounts[a.docId] ?? 0;
            final bCount = matchCounts[b.docId] ?? 0;
            
            // First by match count (descending)
            if (aCount != bCount) {
              return bCount.compareTo(aCount);
            }
            
            // Then by date (newest first) as secondary sort
            final aDate = a.uploadTime ?? DateTime(1900);
            final bDate = b.uploadTime ?? DateTime(1900);
            return bDate.compareTo(aDate);
          });
          
          logger.info('Sorted diets by relevance for query: $searchQuery');
        }
      }
      
      return allDiets;
    } catch (e, s) {
      logger.err('Error searching diets: $e', [s]);
      return [];
    }
  }

  /// Uploads a recipe PDF for a diet to Cloud Storage.
  ///
  /// Stored at `users/{userId}/dietRecipes/recipe_<ts>.pdf`. Returns a map with
  /// the download `url`, storage `path` (for later cleanup) and original
  /// `name`, or null when the upload fails.
  ///
  /// Called from the diet import flow when the imported diet contains the
  /// "*tarifi ektedir" reference and the admin attaches a recipe PDF.
  Future<Map<String, String>?> uploadRecipePdf({
    required String userId,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async {
    try {
      // Keep the admin's own file name (see [uploadSourceFile]); the recipe is
      // opened for reading, so it stays inline instead of forcing a download.
      final safeName = sanitizeStorageFileName(fileName, fallback: 'tarif.pdf');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'users/$userId/dietRecipes/$ts/$safeName';

      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await uploadFileToStorage(
        ref: ref,
        metadata: SettableMetadata(
          contentType: 'application/pdf',
          contentDisposition: inlineContentDisposition(safeName),
        ),
        filePath: filePath,
        bytes: fileBytes,
      );
      final downloadUrl = await ref.getDownloadURL();

      logger.info('Recipe PDF uploaded. userId=$userId path=$storagePath');
      return {
        'url': downloadUrl,
        'path': storagePath,
        'name': safeName,
      };
    } catch (e, s) {
      logger.err('Error uploading recipe PDF: $e', [s]);
      return null;
    }
  }

  Future<Map<String, String>?> uploadSourceFile({
    required String userId,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async {
    try {
      // The uploaded document keeps its original name so it downloads under
      // that name; the timestamp is a folder segment, which keeps object names
      // unique without touching the file name itself.
      final safeName = sanitizeStorageFileName(fileName, fallback: 'diyet.docx');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'users/$userId/dietSources/$ts/$safeName';

      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await uploadFileToStorage(
        ref: ref,
        metadata: SettableMetadata(
          contentType: kDocxContentType,
          contentDisposition: attachmentContentDisposition(safeName),
        ),
        filePath: filePath,
        bytes: fileBytes,
      );
      final downloadUrl = await ref.getDownloadURL();

      logger.info('Diet source file uploaded. userId=$userId path=$storagePath');
      return {
        'url': downloadUrl,
        'path': storagePath,
        'name': safeName,
      };
    } catch (e, s) {
      logger.err('Error uploading diet source file: $e', [s]);
      return null;
    }
  }

  /// Best-effort removal of a Cloud Storage object by its full path. Never
  /// throws: a failed cleanup must not break the calling flow.
  Future<void> deleteStorageFile(String? storagePath) async {
    final path = (storagePath ?? '').trim();
    if (path.isEmpty) return;
    try {
      await FirebaseStorage.instance.ref().child(path).delete();
      logger.info('Deleted storage file at $path');
    } catch (e) {
      logger.warn('Could not delete storage file at $path: $e');
    }
  }

  /// Deletes a diet document
  ///
  /// @param userId The ID of the user who owns the diet document
  /// @param docId The ID of the diet document to delete
  Future<void> deleteDiet({
    required String userId,
    required String docId,
  }) async {
    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('dietLists')
          .doc(docId);

      // Best-effort: remove the attached files (recipe PDF, imported Word
      // document) from Storage first so they don't get orphaned. A
      // missing/failed delete never blocks removing the diet document itself.
      try {
        final snap = await docRef.get();
        final data = snap.data();
        for (final field in const ['recipePdfPath', 'sourceFilePath']) {
          await deleteStorageFile(data?[field] as String?);
        }
      } catch (e) {
        logger.warn('Could not read attachments of diet $docId: $e');
      }

      await docRef.delete();
      logger.info('Deleted diet document: $docId');
      notifyListeners();
    } catch (e, s) {
      logger.err('Error deleting diet document: $e', [s]);
      rethrow;
    }
  }

  /// Creates a new diet document in Firestore
  /// 
  /// @param userId The ID of the user for whom to create the diet
  /// @param dietData The map containing diet data to store
  /// @param subscriptionId Optional subscription ID to associate with the diet
  /// 
  /// @return The ID of the newly created diet document
  Future<String> createDiet({
    required String userId,
    required Map<String, dynamic> dietData,
    String? subscriptionId,
  }) async {
    try {
      // Add current user as creator
      dietData['createDate'] = Timestamp.now();
      dietData['uploadTime'] = Timestamp.now();
      dietData['userId'] = userId;
      
      // Add subscription ID if provided
      if (subscriptionId != null) {
        dietData['subscriptionId'] = subscriptionId;
      }

      final docRef = await _firestore
          .collection('users')
          .doc(userId)
          .collection('dietLists')
          .add(dietData);

      logger.info('Created new diet document with ID: ${docRef.id}');
      notifyListeners();
      return docRef.id;
    } catch (e, s) {
      logger.err('Error creating diet document: $e', [s]);
      rethrow;
    }
  }

  /// Updates an existing diet document
  /// 
  /// @param userId The ID of the user who owns the diet
  /// @param docId The ID of the diet document to update
  /// @param subtitles The updated subtitles data
  /// @param weekendSubtitles Optional weekend (Hafta Sonu) menu. When provided
  ///   and non-empty it is saved; when provided and empty the weekend menu is
  ///   removed from the document; when null the existing weekend menu is left
  ///   untouched.
  /// @param displayName Optional updated name for the diet
  /// @param subscriptionId Optional subscription ID to associate with the diet
  /// @param updateUser Optional ID of the user making the update
  /// 
  /// @return true if update was successful, false otherwise
  Future<bool> updateDiet({
    required String userId,
    required String docId,
    required Map<String, dynamic> subtitles,
    Map<String, dynamic>? weekendSubtitles,
    String? displayName,
    String? subscriptionId,
    String? updateUser,
  }) async {
    try {
      // Prepare data for saving
      final Map<String, dynamic> updatedData = {
        'uploadTime': Timestamp.now(), // Update timestamp
        'subtitles': subtitles,
      };

      // Persist/replace/remove the weekend menu based on what was passed in.
      if (weekendSubtitles != null) {
        updatedData['weekendSubtitles'] = weekendSubtitles.isEmpty
            ? FieldValue.delete()
            : weekendSubtitles;
      }

      // Add display name if provided
      if (displayName != null) {
        updatedData['displayName'] = displayName;
      }
      
      // Add subscription ID if provided
      if (subscriptionId != null) {
        updatedData['subscriptionId'] = subscriptionId;
      }
      
      // Add update metadata if there's an update user
      if (updateUser != null) {
        updatedData['updateDate'] = Timestamp.now();
        updatedData['updateUser'] = updateUser;
      }

      // Update in Firestore
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('dietLists')
          .doc(docId)
          .update(updatedData);

      logger.info('Updated diet document: $docId');
      notifyListeners();
      return true;
    } catch (e, s) {
      logger.err('Error updating diet document: $e', [s]);
      return false;
    }
  }

  /// Uploads a new diet document with subscription information
  /// 
  /// @param userId The ID of the user for whom to upload the diet
  /// @param subtitles The weekday meal data to store
  /// @param weekendSubtitles Optional weekend (Hafta Sonu) menu; stored only
  ///   when non-null and non-empty
  /// @param subscriptionId Optional ID of the subscription associated with this
  ///   diet; omitted from the document when null or empty
  /// 
  /// @return The ID of the newly created diet document
  Future<String?> uploadDiet({
    required String userId,
    required Map<String, dynamic> subtitles,
    String? subscriptionId,
    Map<String, dynamic>? weekendSubtitles,
    String? displayName, //optional TODO ileride dialogtan belki girilir
    String? recipePdfUrl,
    String? recipePdfPath,
    String? recipePdfName,
    String? sourceFileUrl,
    String? sourceFilePath,
    String? sourceFileName,
  }) async {
    try {
      final now=DateTime.now();
      final Map<String, dynamic> dietData = {
        'uploadTime': FieldValue.serverTimestamp(),
        if (subscriptionId != null && subscriptionId.isNotEmpty)
          'subscriptionId': subscriptionId,
        'subtitles': subtitles,
        if (weekendSubtitles != null && weekendSubtitles.isNotEmpty)
          'weekendSubtitles': weekendSubtitles,
        'userId': userId,
        'displayName': displayName?? 'liste_${now.day.toString().padLeft(2, '0')}_${now.month.toString().padLeft(2, '0')}_${now.year.toString().substring(2)}_${now.hour.toString().padLeft(2, '0')}_${now.minute.toString().padLeft(2, '0')}',
        'createDate': Timestamp.now(),
        if (recipePdfUrl != null && recipePdfUrl.isNotEmpty)
          'recipePdfUrl': recipePdfUrl,
        if (recipePdfPath != null && recipePdfPath.isNotEmpty)
          'recipePdfPath': recipePdfPath,
        if (recipePdfName != null && recipePdfName.isNotEmpty)
          'recipePdfName': recipePdfName,
        if (sourceFileUrl != null && sourceFileUrl.isNotEmpty)
          'sourceFileUrl': sourceFileUrl,
        if (sourceFilePath != null && sourceFilePath.isNotEmpty)
          'sourceFilePath': sourceFilePath,
        if (sourceFileName != null && sourceFileName.isNotEmpty)
          'sourceFileName': sourceFileName,
      };

      final docRef = await _firestore
          .collection('users')
          .doc(userId)
          .collection('dietLists')
          .add(dietData);

      logger.info('Diet list uploaded with ID: ${docRef.id}');
      notifyListeners();
      return docRef.id;
    } catch (e, s) {
      logger.err('Error uploading diet list: $e', [s]);
      return null;
    }
  }
}
