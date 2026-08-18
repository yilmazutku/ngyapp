import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../models/logger.dart';
import '../utils/storage_upload.dart';

final Logger logger = Logger.forClass(TestProvider);

/// Manages Test attachments (PDFs or images)
/// Storage:  users/{userId}/tests/test_<ts>.<ext>
/// Firestore: users/{userId}/tests/doc('pdfFiles')/collection('pdfFiles')/{test_<ts>}
class TestProvider extends ChangeNotifier {
  /// Upload a test attachment (PDF or image) and write its metadata.
  ///
  /// Prefers streaming the file from disk via [filePath] (low, constant memory)
  /// and only uses the in-memory [fileBytes] as a fallback (e.g. on web). See
  /// [uploadFileToStorage] for why streaming matters on Windows desktop.
  Future<void> uploadTestAttachmentFile({
    required String userId,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async {
    try {
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;
      final docId = 'test_$ts';

      final ext = _inferExtension(fileName); // keeps dotless ext like "pdf"
      final contentType = _inferContentType(ext); // e.g., application/pdf, image/jpeg
      final storagePath = 'users/$userId/tests/$docId.$ext';

      // 1) upload to Storage (streamed from disk when a path is available).
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await uploadFileToStorage(
        ref: ref,
        metadata: SettableMetadata(contentType: contentType),
        filePath: filePath,
        bytes: fileBytes,
      );
      final downloadUrl = await ref.getDownloadURL();

      // 2) write Firestore metadata (kept "pdfFiles" path for backward parity with Tanita)
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tests')
          .doc(docId);

      final isImage = contentType.startsWith('image/');

      await docRef.set({
        'pdfUrl': downloadUrl,          // field name kept for compatibility
        'fileName': fileName,
        'uploadTime': FieldValue.serverTimestamp(),
        'storagePath': storagePath,
        'contentType': contentType,
        'isImage': isImage,
        'ext': ext,
      });

      logger.info('Test attachment uploaded. userId={}, docId={}, ext={}', [userId, docId, ext]);
      notifyListeners();
    } catch (e) {
      logger.err('Error uploading Test attachment for userId={}: {}', [userId, e.toString()]);
      rethrow;
    }
  }

  /// List attachments metadata
  Future<List<Map<String, dynamic>>> fetchTestAttachmentMetadata(String userId) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tests')
          .orderBy('uploadTime', descending: true)
          .get();

      return qs.docs.map((d) {
        final data = d.data();
        return {
          'docId': d.id,
          'pdfUrl': data['pdfUrl'],
          'fileName': data['fileName'],
          'uploadTime': data['uploadTime'],
          'storagePath': data['storagePath'] ?? '',
          'contentType': data['contentType'] ?? '',
          'isImage': data['isImage'] ?? false,
          'ext': data['ext'] ?? '',
        };
      }).toList();
    } catch (e) {
      logger.err('fetchTestAttachmentMetadata err for userId={}: {}', [userId, e.toString()]);
      return [];
    }
  }

  /// Delete attachment: removes Firestore doc and Storage blob
  Future<void> deleteTestAttachment({
    required String userId,
    required String docId,
    required String storagePath,
  }) async {
    try {
      if (storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref().child(storagePath).delete();
      }

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tests')
          .doc(docId);

      await docRef.delete();

      logger.info('Test attachment deleted. userId={}, docId={}', [userId, docId]);
      notifyListeners();
    } catch (e) {
      logger.err('deleteTestAttachment err. userId={}, docId={}, e={}', [userId, docId, e.toString()]);
      rethrow;
    }
  }

  // -------- helpers (no extra deps) --------
  String _inferExtension(String fileName) {
    final i = fileName.lastIndexOf('.');
    if (i == -1 || i == fileName.length - 1) return 'bin';
    return fileName.substring(i + 1).toLowerCase();
  }

  String _inferContentType(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }
}
