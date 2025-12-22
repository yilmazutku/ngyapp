import 'package:cloud_firestore/cloud_firestore.dart';

class TestModel {
  final String testId;
  final String userId;
  final String testName;
  final String? testDescription;
  final DateTime testDate;
  final String? testFileUrl; // URL to the uploaded test file (image, PDF)
  final DateTime createDate;
  final String? createUser;
  DateTime? updateDate;
  String? updateUser;

  TestModel({
    required this.testId,
    required this.userId,
    required this.testName,
    this.testDescription,
    required this.testDate,
    this.testFileUrl,
    DateTime? createDate,
    this.createUser,
    this.updateDate,
    this.updateUser,
  }) : createDate = createDate ?? DateTime.now();

  factory TestModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TestModel(
      testId: doc.id,
      userId: data['userId'],
      testName: data['testName'],
      testDescription: data['testDescription'],
      testDate: (data['testDate'] as Timestamp).toDate(),
      testFileUrl: data['testFileUrl'],
      createDate: data['createDate'] != null ? (data['createDate'] as Timestamp).toDate() : DateTime.now(),
      createUser: data['createUser'],
      updateDate: data['updateDate'] != null ? (data['updateDate'] as Timestamp).toDate() : null,
      updateUser: data['updateUser'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'testName': testName,
      'testDescription': testDescription,
      'testDate': Timestamp.fromDate(testDate),
      'testFileUrl': testFileUrl,
      'createDate': Timestamp.fromDate(createDate),
      if (createUser != null) 'createUser': createUser,
      if (updateDate != null) 'updateDate': Timestamp.fromDate(updateDate!),
      if (updateUser != null) 'updateUser': updateUser,
    };
  }
}