import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/diet_model.dart';
import '../models/logger.dart';
import '../models/filter_params.dart';

/// Manages diet data for users
/// Provides functionality for fetching, creating, updating, and deleting diet documents
class DietProvider extends ChangeNotifier {
  final Logger logger = Logger.forClass(DietProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetches the latest diet list subtitles for a user
  /// Returns null if no diet list is found
  /// 
  /// @param userId The ID of the user whose diet subtitles to fetch
  /// @return A map containing the subtitles from the most recent diet list, or null if none exists
  Future<Map<String, dynamic>?> fetchLatestDietSubtitles(String userId) async {
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
      final data = latestDoc.data();
      
      if (data['subtitles'] != null) {
        logger.info('Found diet list with subtitles for user {}', [userId]);
        return data['subtitles'] as Map<String, dynamic>;
      }

      logger.warn('Latest diet list has no subtitles for user {}', [userId]);
      return null;
    } catch (e) {
      logger.err('Error fetching latest diet subtitles: {}', [e]);
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
          
          // Search in meal content
          try {
            for (final entry in diet.subtitles.entries) {
              final mealKey = entry.key.toLowerCase();
              if (mealKey.contains(q)) return true;
              
              final mealItems = entry.value['content'];
              if (mealItems is List) {
                for (final item in mealItems) {
                  final text = item is Map ? (item['content']?.toString().toLowerCase() ?? '') : '';
                  if (text.contains(q)) return true;
                }
              }
            }
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
          
          // Search in meal content
          bool foundInContent = false;
          int matchCount = 0;
          
          try {
            for (var mealEntry in diet.subtitles.entries) {
              final mealName = mealEntry.key.toLowerCase();
              if (mealName.contains(lowerQuery)) {
                foundInContent = true;
                matchCount++;
              }

              // Search in meal items
              final mealItems = diet.subtitles[mealName]?['content'];//diet.getMealItems(mealEntry.key);//diet.getMealItems(mealEntry.key);
              if (mealItems != null) {
                for (var item in mealItems) {
                  final content = item is Map
                      ? item['content']?.toString().toLowerCase() ?? ''
                      : '';
                  if (content.contains(lowerQuery)) {
                    foundInContent = true;
                    matchCount++;
                  }
                }
              }
            }
            
            // Store match count for this diet
            if (matchCount > 0) {
              matchCounts[diet.docId] = matchCount;
            }
          } catch (e, s) {
            logger.err('Error searching diet content: $e', [s]);
            // On error, include the diet in results to avoid hiding data due to errors
            foundInContent = true;
          }
          
          return foundInContent;
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

  /// Deletes a diet document
  /// 
  /// @param userId The ID of the user who owns the diet document
  /// @param docId The ID of the diet document to delete
  Future<void> deleteDiet({
    required String userId,
    required String docId,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('dietLists')
          .doc(docId)
          .delete();
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
  /// @param displayName Optional updated name for the diet
  /// @param subscriptionId Optional subscription ID to associate with the diet
  /// @param updateUser Optional ID of the user making the update
  /// 
  /// @return true if update was successful, false otherwise
  Future<bool> updateDiet({
    required String userId,
    required String docId,
    required Map<String, dynamic> subtitles,
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
  /// @param subtitles The meal data to store
  /// @param subscriptionId The ID of the subscription associated with this diet
  /// 
  /// @return The ID of the newly created diet document
  Future<String?> uploadDiet({
    required String userId,
    required Map<String, dynamic> subtitles,
    required String subscriptionId,
    String? displayName //optional TODO ileride dialogtan belki girilir
  }) async {
    try {
      final now=DateTime.now();
      final Map<String, dynamic> dietData = {
        'uploadTime': FieldValue.serverTimestamp(),
        'subscriptionId': subscriptionId,
        'subtitles': subtitles,
        'userId': userId,
        'displayName': displayName?? 'liste_${now.day.toString().padLeft(2, '0')}_${now.month.toString().padLeft(2, '0')}_${now.year.toString().substring(2)}_${now.hour.toString().padLeft(2, '0')}_${now.minute.toString().padLeft(2, '0')}',
        'createDate': Timestamp.now(),
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
