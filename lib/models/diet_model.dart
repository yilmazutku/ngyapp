import 'package:cloud_firestore/cloud_firestore.dart';

import 'diet_goals.dart';

class DietDocument {
  final String docId;
  final String userId;
  final String displayName;
  final DateTime? uploadTime;

  /// Weekday (Hafta İçi) meal plan, keyed by [Meals] enum name.
  final Map<String, dynamic> subtitles;

  /// Optional weekend (Hafta Sonu) meal plan, keyed by [Meals] enum name.
  ///
  /// Present only when the diet was imported/created with a separate weekend
  /// menu (docx contained a standalone `HAFTASONU` line). Null or empty means
  /// this is a weekday-only diet, which keeps older documents fully compatible.
  final Map<String, dynamic>? weekendSubtitles;

  final DateTime createDate;
  final String? createUser;
  DateTime? updateDate;
  String? updateUser;
  final String? subscriptionId;

  /// Download URL of the recipe PDF attached to this diet, if any.
  ///
  /// Set when the imported diet contained the "*tarifi ektedir" reference and
  /// the admin attached a recipe PDF. The user opens it by tapping the recipe
  /// link shown on their plan.
  final String? recipePdfUrl;

  /// Cloud Storage path of the attached recipe PDF (used for cleanup).
  final String? recipePdfPath;

  /// Original file name of the attached recipe PDF (for display).
  final String? recipePdfName;

  final String? sourceFileUrl;

  final String? sourceFilePath;

  final String? sourceFileName;

  /// "Su Hedefi: ..." line captured verbatim from the imported document.
  final String? waterGoal;

  /// "Spor Hedefi: ..." line captured verbatim from the imported document.
  final String? sportGoal;

  DietDocument({
    required this.docId,
    required this.userId,
    required this.displayName,
    required this.uploadTime,
    required this.subtitles,
    this.weekendSubtitles,
    DateTime? createDate,
    this.createUser,
    this.updateDate,
    this.updateUser,
    this.subscriptionId,
    this.recipePdfUrl,
    this.recipePdfPath,
    this.recipePdfName,
    this.sourceFileUrl,
    this.sourceFilePath,
    this.sourceFileName,
    this.waterGoal,
    this.sportGoal,
  }) : createDate = createDate ?? DateTime.now();

  /// Whether this diet defines a distinct weekend (Hafta Sonu) menu.
  bool get hasWeekend =>
      weekendSubtitles != null && weekendSubtitles!.isNotEmpty;

  /// Whether this diet has an attached recipe PDF.
  bool get hasRecipe => (recipePdfUrl ?? '').isNotEmpty;

  bool get hasSourceFile => (sourceFileUrl ?? '').isNotEmpty;

  /// Goal lines shown above the first meal of this diet.
  DietGoals get goals => DietGoals(water: waterGoal, sport: sportGoal);

  factory DietDocument.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    return DietDocument(
      docId: doc.id,
      uploadTime: (data?['uploadTime'] as Timestamp?)?.toDate(),
      subtitles: data?['subtitles'] as Map<String, dynamic>,
      weekendSubtitles: data?['weekendSubtitles'] as Map<String, dynamic>?,
      userId:data?['userId'],
      displayName: data?['displayName'],
      createDate: data?['createDate'] != null ? (data?['createDate'] as Timestamp).toDate() : DateTime.now(),
      createUser: data?['createUser'],
      updateDate: data?['updateDate'] != null ? (data?['updateDate'] as Timestamp).toDate() : null,
      updateUser: data?['updateUser'],
      subscriptionId: data?['subscriptionId'],
      recipePdfUrl: data?['recipePdfUrl'] as String?,
      recipePdfPath: data?['recipePdfPath'] as String?,
      recipePdfName: data?['recipePdfName'] as String?,
      sourceFileUrl: data?['sourceFileUrl'] as String?,
      sourceFilePath: data?['sourceFilePath'] as String?,
      sourceFileName: data?['sourceFileName'] as String?,
      waterGoal: data?['waterGoal'] as String?,
      sportGoal: data?['sportGoal'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uploadTime': uploadTime != null ? Timestamp.fromDate(uploadTime!) : null,
      'subtitles': subtitles,
      if (hasWeekend) 'weekendSubtitles': weekendSubtitles,
      'createDate': Timestamp.fromDate(createDate),
      'userId':userId,
      'displayName':displayName,
      if (createUser != null) 'createUser': createUser,
      if (updateDate != null) 'updateDate': Timestamp.fromDate(updateDate!),
      if (updateUser != null) 'updateUser': updateUser,
      if (subscriptionId != null) 'subscriptionId': subscriptionId,
      if (recipePdfUrl != null) 'recipePdfUrl': recipePdfUrl,
      if (recipePdfPath != null) 'recipePdfPath': recipePdfPath,
      if (recipePdfName != null) 'recipePdfName': recipePdfName,
      if (sourceFileUrl != null) 'sourceFileUrl': sourceFileUrl,
      if (sourceFilePath != null) 'sourceFilePath': sourceFilePath,
      if (sourceFileName != null) 'sourceFileName': sourceFileName,
      if (waterGoal != null) 'waterGoal': waterGoal,
      if (sportGoal != null) 'sportGoal': sportGoal,
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
