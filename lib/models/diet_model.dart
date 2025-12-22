import 'package:cloud_firestore/cloud_firestore.dart';

class DietDocument {
  final String docId;
  final String userId;
  final String displayName;
  final DateTime? uploadTime;
  final Map<String, dynamic> subtitles;
  final DateTime createDate;
  final String? createUser;
  DateTime? updateDate;
  String? updateUser;
  final String? subscriptionId;

  DietDocument({
    required this.docId,
    required this.userId,
    required this.displayName,
    required this.uploadTime,
    required this.subtitles,
    DateTime? createDate,
    this.createUser,
    this.updateDate,
    this.updateUser,
    this.subscriptionId,
  }) : createDate = createDate ?? DateTime.now();

  factory DietDocument.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    return DietDocument(
      docId: doc.id,
      uploadTime: (data?['uploadTime'] as Timestamp?)?.toDate(),
      subtitles: data?['subtitles'] as Map<String, dynamic>,
      userId:data?['userId'],
      displayName: data?['displayName'],
      createDate: data?['createDate'] != null ? (data?['createDate'] as Timestamp).toDate() : DateTime.now(),
      createUser: data?['createUser'],
      updateDate: data?['updateDate'] != null ? (data?['updateDate'] as Timestamp).toDate() : null,
      updateUser: data?['updateUser'],
      subscriptionId: data?['subscriptionId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uploadTime': uploadTime != null ? Timestamp.fromDate(uploadTime!) : null,
      'subtitles': subtitles,
      'createDate': Timestamp.fromDate(createDate),
      'userId':userId,
      'displayName':displayName,
      if (createUser != null) 'createUser': createUser,
      if (updateDate != null) 'updateDate': Timestamp.fromDate(updateDate!),
      if (updateUser != null) 'updateUser': updateUser,
      if (subscriptionId != null) 'subscriptionId': subscriptionId,
    };
  }

  // String get displayName {
  //   // docId often like "20230101_1145"; or use uploadTime if you prefer
  //   // Adjust format if needed:
  //   if (uploadTime != null) {
  //     final dateStr =
  //         '${uploadTime!.year}-${uploadTime!.month.toString().padLeft(2, '0')}-${uploadTime!.day.toString().padLeft(2, '0')}';
  //     return 'liste_$dateStr';
  //   }
  //   return 'liste_${docId}';
  // }
}
