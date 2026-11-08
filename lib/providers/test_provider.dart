import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../models/test_attachment.dart';
import '../utils/storage_upload.dart';

/// Manages Test attachments (PDFs or images)
/// Storage:  users/{userId}/tests/test_<ts>.<ext>
/// Firestore: users/{userId}/tests/{test_<ts>}
class TestProvider extends ChangeNotifier {
  TestProvider({FirebaseFirestore? db}) : _dbOverride = db;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  static const String testsCollection = 'tests';

  /// Upload a test attachment (PDF or image) and write its metadata.
  ///
  /// Streams the file from disk via [filePath] (low, constant memory). See
  /// [uploadFileToStorage] for why streaming matters on Windows desktop.
  Future<void> uploadTestAttachmentFile({
    required String userId,
    required String fileName,
    required String filePath,
    BloodTestInfo? bloodTest,
  }) async {
    final DateTime now = DateTime.now();
    final int ts = now.millisecondsSinceEpoch;
    final String docId = 'test_$ts';

    final String ext = _inferExtension(fileName); // keeps dotless ext like "pdf"
    final String contentType = _inferContentType(ext); // e.g., application/pdf, image/jpeg
    final String storagePath = 'users/$userId/tests/$docId.$ext';

    // 1) upload to Storage (streamed from disk when a path is available).
    final Reference ref = FirebaseStorage.instance.ref().child(storagePath);
    await uploadFileToStorage(
      ref: ref,
      metadata: SettableMetadata(contentType: contentType),
      filePath: filePath,
    );
    final String downloadUrl = await ref.getDownloadURL();

    // 2) write Firestore metadata (field names kept for compatibility)
    await _testsOf(userId).doc(docId).set({
      TestAttachment.urlField: downloadUrl,
      TestAttachment.fileNameField: fileName,
      TestAttachment.uploadTimeField: FieldValue.serverTimestamp(),
      TestAttachment.storagePathField: storagePath,
      TestAttachment.contentTypeField: contentType,
      TestAttachment.isImageField: contentType.startsWith('image/'),
      TestAttachment.extField: ext,
      ..._categoryFields(bloodTest),
    });

    notifyListeners();
  }

  Future<List<TestAttachment>> fetchTestAttachments(String userId) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _testsOf(userId)
        .orderBy(TestAttachment.uploadTimeField, descending: true)
        .get();
    return [
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        TestAttachment.fromMap(doc.id, doc.data()),
    ];
  }

  Future<void> updateDocumentCategory({
    required String userId,
    required List<String> docIds,
    BloodTestInfo? bloodTest,
  }) async {
    final WriteBatch batch = _db.batch();
    for (final String docId in docIds) {
      batch.update(_testsOf(userId).doc(docId), {
        ..._categoryFields(bloodTest),
        if (bloodTest == null) ...{
          TestAttachment.bloodTestDateField: FieldValue.delete(),
          TestAttachment.bloodTestReminderField: FieldValue.delete(),
        },
      });
    }
    await batch.commit();
    notifyListeners();
  }

  static Map<String, Object> _categoryFields(BloodTestInfo? bloodTest) {
    if (bloodTest == null) return {TestAttachment.isBloodTestField: false};
    return {
      TestAttachment.isBloodTestField: true,
      TestAttachment.bloodTestDateField: Timestamp.fromDate(bloodTest.testDate),
      TestAttachment.bloodTestReminderField: bloodTest.wantsReminder,
    };
  }

  CollectionReference<Map<String, dynamic>> _testsOf(String userId) =>
      _db.collection('users').doc(userId).collection(testsCollection);

  /// Delete attachment: removes Firestore doc and Storage blob
  Future<void> deleteTestAttachment({
    required String userId,
    required String docId,
    required String storagePath,
  }) async {
    if (storagePath.isNotEmpty) {
      await FirebaseStorage.instance.ref().child(storagePath).delete();
    }
    await _testsOf(userId).doc(docId).delete();
    notifyListeners();
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
