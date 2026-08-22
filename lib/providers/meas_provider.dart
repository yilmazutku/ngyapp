import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
// if needed for date formatting
import '../models/logger.dart';
import '../models/meas_model.dart';
import '../models/filter_params.dart';
import '../utils/storage_upload.dart';

final Logger logger = Logger.forClass(MeasProvider);

/// Manages user measurement data including storage, retrieval, and updates of measurements
/// Provides functionality for handling measurement changes and PDF uploads
class MeasProvider extends ChangeNotifier {
  // Flag to track if measurements have been changed
  bool _measurementChanged = false;
  
  /// Returns whether measurements have been changed
  bool get measurementChanged => _measurementChanged;
  
  /// Resets the measurement changed flag
  void resetMeasurementChanged() {
    _measurementChanged = false;
  }

  /// Adds a new measurement for a user
  /// 
  /// @param userId The ID of the user to add the measurement for
  /// @param measurement The measurement model to add
  /// 
  /// @return The document ID of the added measurement
  Future<void> addMeasurement(String userId, MeasurementModel measurement) async {
    try {
      logger.info('Adding new measurement for userId={}', [userId]);
      
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('measurements')
          .doc(measurement.measurementId)
          .set(measurement.toMap());

      logger.info('Successfully added measurement with id={}', [measurement.measurementId]);
      
      // Set the measurement changed flag
      _measurementChanged = true;
      
      // Notify listeners to trigger UI updates
      notifyListeners();
    } catch (e) {
      logger.err('Failed to add measurement for userId={}: {}', [userId, e.toString()]);
      logger.err('Error stack trace: {}', [StackTrace.current]);
      rethrow;
    }
  }
  /// Updates an existing measurement for a user
  /// 
  /// @param userId The ID of the user whose measurement to update
  /// @param measurement The updated measurement model
  Future<void> updateMeasurement(String userId, MeasurementModel measurement) async {
    try {
      logger.info('Updating measurement for userId={}, measurementId={}', [userId, measurement.measurementId]);
      
      if (measurement.measurementId.isEmpty) {
        throw ArgumentError('Measurement document ID cannot be null or empty');
      }
      
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('measurements')
          .doc(measurement.measurementId);
      
      // Convert to map and update in Firestore
      final dataMap = measurement.toMap();
      await docRef.update(dataMap);
      
      logger.info('Successfully updated measurement with id={}', [measurement.measurementId]);
      
      // Set the measurement changed flag
      _measurementChanged = true;
      
      // Notify listeners to trigger UI updates
      notifyListeners();
    } catch (e) {
      logger.err('Failed to update measurement for userId={}, measurementId={}: {}', 
          [userId, measurement.measurementId, e.toString()]);
      logger.err('Error stack trace: {}', [StackTrace.current]);
      rethrow;
    }
  }

  /// Deletes a specific measurement for a user
  /// 
  /// @param userId The ID of the user whose measurement to delete
  /// @param measurementId The ID of the measurement to delete
  /// 
  /// @return True if deletion was successful, false otherwise
  Future<bool> deleteMeasurement(String userId, String measurementId) async {
    try {
      logger.info('Deleting measurement. userId={}, measurementId={}', [userId, measurementId]);

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('measurements')
          .doc(measurementId);
      await docRef.delete();
          
      logger.info('Successfully deleted measurement. userId={}, measurementId={}', [userId, measurementId]);
      
      // Set the measurement changed flag
      _measurementChanged = true;
      
      // Notify listeners to trigger UI updates
      notifyListeners();
      
      return true;
    } catch (e) {
      logger.err('Failed to delete measurement. userId={}, measurementId={}, error={}', 
          [userId, measurementId, e.toString()]);
      logger.err('Error stack trace: {}', [StackTrace.current]);
      return false;
    }
  }

  /// Fetches all measurements for a specific user
  /// 
  /// @param userId The ID of the user whose measurements to fetch
  /// @param filterParams Optional filter parameters for Firebase-side filtering
  /// 
  /// @return A list of MeasurementModel objects representing the user's measurements
  Future<List<MeasurementModel>> fetchMeasurements(String userId, {MeasurementFilterParams? filterParams}) async {
    try {
      logger.info('Fetching measurements for userId={}', [userId]);
      Query query = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('measurements');
      
      // Apply date range filter if provided
      if (filterParams?.dateRange != null) {
        query = query
            .where('date', isGreaterThanOrEqualTo: filterParams!.dateRange!.start)
            .where('date', isLessThanOrEqualTo: DateTime(
              filterParams.dateRange!.end.year,
              filterParams.dateRange!.end.month,
              filterParams.dateRange!.end.day,
              23,
              59,
              59,
            ));
      }
      
      query = query.orderBy('date', descending: true);
      
      final snapshot = await query.get();
      var measurements = snapshot.docs.map((doc) => MeasurementModel.fromDocument(doc)).toList();
      
      // Apply client-side search filter if needed (search by date text)
      if (filterParams?.searchQuery != null && filterParams!.searchQuery!.isNotEmpty) {
        final searchLower = filterParams.searchQuery!.toLowerCase();
        measurements = measurements.where((m) {
          final dateText = m.measDate.toString().toLowerCase();
          return dateText.contains(searchLower);
        }).toList();
      }
      
      logger.info('Fetched {} measurements with filters: {}', [measurements.length, filterParams?.toDebugMap()]);
      return measurements;
    } catch (e) {
      logger.err('fetchMeasurements err: {}', [e.toString()]);
      return [];
    }
  }

  /// Saves a batch of measurements for a user
  /// BUNU EXCEL IMPORTTA KULLANALIM!!!!!!!!!!!!
  /// 
  /// This is a legacy method kept for backward compatibility.
  /// It's recommended to use addMeasurement, updateMeasurement, or deleteMeasurement instead.
  /// 
  /// @param userId The ID of the user whose measurements are being saved
  /// @param measurements The list of measurement models to be saved
  // Future<void> saveChanges(String userId, List<MeasurementModel> measurements) async {
  //   logger.info('Using legacy batch save method for userId={}, measurements count={}',
  //       [userId, measurements.length]);
  //
  //   try {
  //     final collectionRef = FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(userId)
  //         .collection('measurements');
  //
  //     // Create a batch write operation
  //     final batch = FirebaseFirestore.instance.batch();
  //     int operationsCount = 0;
  //
  //     for (final measurement in measurements) {
  //       final docRef = measurement.measurementId != null && measurement.measurementId!.isNotEmpty
  //           ? collectionRef.doc(measurement.measurementId)
  //           : collectionRef.doc();
  //
  //
  //       // Add to batch
  //       batch.set(docRef, measurement.toMap());
  //       operationsCount++;
  //     }
  //
  //     // Commit the batch
  //     if (operationsCount > 0) {
  //       await batch.commit();
  //       logger.info('Batch saved {} measurements for userId={}', [operationsCount, userId]);
  //     } else {
  //       logger.info('No measurements to save for userId={}', [userId]);
  //     }
  //
  //     // Set the measurement changed flag
  //     _measurementChanged = true;
  //
  //     // Notify listeners to trigger UI updates
  //     notifyListeners();
  //   } catch (e) {
  //     logger.err('Failed to save measurements batch for userId={}: {}', [userId, e.toString()]);
  //     logger.err('Error stack trace: {}', [StackTrace.current]);
  //     rethrow;
  //   }
  // }

  /// Uploads a Tanita PDF file to Firebase Storage and stores its metadata in Firestore
  ///
  /// Streams the file from disk via [filePath] (low, constant memory). See
  /// [uploadFileToStorage] for why streaming matters on Windows desktop.
  ///
  /// @param userId The ID of the user to whom the PDF belongs
  /// @param fileName The name of the PDF file
  /// @param filePath Path to the local PDF on disk
  Future<void> uploadTanitaPdfFile({
    required String userId,
    required String fileName,
    required String filePath,
  }) async {

    try {
      final now = DateTime.now();
      final storagePath = 'users/$userId/measurements/tanita_${now.millisecondsSinceEpoch}.pdf';

      // 1) Upload to Storage (streamed from disk).
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);
      await uploadFileToStorage(
        ref: storageRef,
        metadata: SettableMetadata(contentType: 'application/pdf'),
        filePath: filePath,
      );

      final downloadUrl = await storageRef.getDownloadURL();

      // 2) Save metadata doc in Firestore
      final docId = 'tanita_${now.millisecondsSinceEpoch}';
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('measurements')
          .doc('tanita')      // or just .doc('tanita_{someKey}') if you prefer
          .collection('pdfFiles')
          .doc(docId);

      await docRef.set({
        'pdfUrl': downloadUrl,
        'fileName': fileName,
        'uploadTime': FieldValue.serverTimestamp(),
        'storagePath': storagePath,
      });

      logger.info('Tanita PDF uploaded: $docId');
      notifyListeners();
    } catch (e) {
      logger.err('Error uploading Tanita PDF: {}', [e.toString()]);
      rethrow;
    }
  }

  /// Deletes a Tanita PDF file: removes both the Firestore metadata document
  /// and the underlying Storage blob.
  ///
  /// [storagePath] is used when available (persisted on newer uploads). For
  /// legacy documents that predate the stored path, it is reconstructed from
  /// the [docId], which always matches the storage file name
  /// (`users/{userId}/measurements/{docId}.pdf`).
  ///
  /// @param userId The ID of the user to whom the PDF belongs
  /// @param docId The Firestore document ID of the Tanita PDF metadata
  /// @param storagePath The Storage path of the PDF blob (may be empty/legacy)
  Future<void> deleteTanitaPdfFile({
    required String userId,
    required String docId,
    String? storagePath,
  }) async {
    try {
      final resolvedPath = (storagePath != null && storagePath.isNotEmpty)
          ? storagePath
          : 'users/$userId/measurements/$docId.pdf';

      // Best-effort Storage removal: if the blob is already gone (e.g. legacy
      // path mismatch or a prior partial delete), still remove the Firestore
      // metadata so no orphaned entry remains in the list.
      try {
        await FirebaseStorage.instance.ref().child(resolvedPath).delete();
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          logger.warn('Tanita PDF blob not found, deleting metadata only: {}',
              [resolvedPath]);
        } else {
          rethrow;
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('measurements')
          .doc('tanita')
          .collection('pdfFiles')
          .doc(docId)
          .delete();

      logger.info('Tanita PDF deleted: userId={}, docId={}', [userId, docId]);
      notifyListeners();
    } catch (e) {
      logger.err('Error deleting Tanita PDF: userId={}, docId={}, e={}',
          [userId, docId, e.toString()]);
      rethrow;
    }
  }
}
