import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_notification.dart';

enum DocumentCategory {
  bloodTest('Kan Tahlili'),
  other('Diğer');

  const DocumentCategory(this.label);

  final String label;
}

class BloodTestInfo {
  BloodTestInfo({required DateTime testDate, required this.wantsReminder})
      : testDate = DateTime(testDate.year, testDate.month, testDate.day);

  final DateTime testDate;
  final bool wantsReminder;
}

class TestAttachment {
  static const String urlField = 'pdfUrl';
  static const String fileNameField = 'fileName';
  static const String uploadTimeField = 'uploadTime';
  static const String storagePathField = 'storagePath';
  static const String contentTypeField = 'contentType';
  static const String isImageField = 'isImage';
  static const String extField = 'ext';
  static const String isBloodTestField = 'isBloodTest';
  static const String bloodTestDateField = 'bloodTestDate';
  static const String bloodTestReminderField = 'bloodTestReminder';

  const TestAttachment({
    required this.docId,
    required this.url,
    required this.fileName,
    required this.uploadTime,
    required this.storagePath,
    required this.isImage,
    required this.bloodTestMark,
    required this.bloodTestDate,
    required this.bloodTestReminder,
  });

  factory TestAttachment.fromMap(String docId, Map<String, dynamic> data) {
    final Object? uploadTime = data[uploadTimeField];
    final String contentType = data[contentTypeField] as String? ?? '';
    final Object? mark = data[isBloodTestField];
    final bool? bloodTestMark = mark is bool ? mark : null;
    final Object? testDate = data[bloodTestDateField];
    final DateTime? day = bloodTestMark == true && testDate is Timestamp
        ? testDate.toDate()
        : null;
    return TestAttachment(
      docId: docId,
      url: data[urlField] as String? ?? '',
      fileName: data[fileNameField] as String? ?? '',
      uploadTime: uploadTime is Timestamp ? uploadTime.toDate() : null,
      storagePath: data[storagePathField] as String? ?? '',
      isImage: data[isImageField] as bool? ?? contentType.startsWith('image/'),
      bloodTestMark: bloodTestMark,
      bloodTestDate: day == null ? null : DateTime(day.year, day.month, day.day),
      bloodTestReminder:
          bloodTestMark == true && data[bloodTestReminderField] == true,
    );
  }

  final String docId;
  final String url;
  final String fileName;
  final DateTime? uploadTime;
  final String storagePath;
  final bool isImage;
  final bool? bloodTestMark;
  final DateTime? bloodTestDate;
  final bool bloodTestReminder;

  bool get isBloodTest => bloodTestMark == true;

  bool get isUnclassified => bloodTestMark == null;

  DocumentCategory get category =>
      isBloodTest ? DocumentCategory.bloodTest : DocumentCategory.other;

  BloodTestInfo? get bloodTestInfo {
    final DateTime? testDate = bloodTestDate;
    if (!isBloodTest || testDate == null) return null;
    return BloodTestInfo(testDate: testDate, wantsReminder: bloodTestReminder);
  }

  static int compareByUploadTime(TestAttachment a, TestAttachment b) {
    final DateTime? first = a.uploadTime;
    final DateTime? second = b.uploadTime;
    if (first == null || second == null) {
      return (first == null ? 0 : 1) - (second == null ? 0 : 1);
    }
    return second.compareTo(first);
  }

  static int compareByTestDate(TestAttachment a, TestAttachment b) {
    final DateTime? first = a.bloodTestDate;
    final DateTime? second = b.bloodTestDate;
    if (first != null && second != null && first != second) {
      return second.compareTo(first);
    }
    if ((first == null) != (second == null)) return first == null ? -1 : 1;
    return compareByUploadTime(a, b);
  }

  static List<TestAttachment> ofCategory(
    List<TestAttachment> files,
    DocumentCategory category,
  ) {
    return [
      for (final TestAttachment file in files)
        if (file.category == category) file,
    ]..sort(category == DocumentCategory.bloodTest
        ? compareByTestDate
        : compareByUploadTime);
  }

  static DateTime? latestTestDate(List<TestAttachment> files) {
    DateTime? latest;
    for (final TestAttachment file in files) {
      final DateTime? testDate = file.bloodTestDate;
      if (testDate != null && (latest == null || testDate.isAfter(latest))) {
        latest = testDate;
      }
    }
    return latest;
  }

  static List<DateTime> testDatesOf(List<TestAttachment> files) {
    return {
      for (final TestAttachment file in files)
        if (file.bloodTestDate != null) file.bloodTestDate!,
    }.toList()
      ..sort((a, b) => b.compareTo(a));
  }

  static Map<DateTime, bool> reminderWishesOf(List<TestAttachment> files) {
    final Map<DateTime, bool> wishes = {};
    for (final TestAttachment file in files) {
      final DateTime? testDate = file.bloodTestDate;
      if (testDate == null) continue;
      wishes[testDate] = (wishes[testDate] ?? false) || file.bloodTestReminder;
    }
    return wishes;
  }

  DateTime? get reminderDueDay {
    final DateTime? testDate = bloodTestDate;
    return testDate == null ? null : BloodTestReminderSchedule.dueDay(testDate);
  }
}
