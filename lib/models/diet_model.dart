import 'package:cloud_firestore/cloud_firestore.dart';

import 'diet_goals.dart';
import 'diet_recipe.dart';
import 'meal_model.dart';

class DietDocument {
  static const String recipesPerLineField = 'recipesPerLine';

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
  /// Older diets keep their only recipe PDF here and every "*tarifi ektedir"
  /// link opens it. Diets with [recipesPerLine] keep each link's PDF on its
  /// content line; for them this is just the first recipe, written for older
  /// app versions.
  final String? recipePdfUrl;

  /// Cloud Storage path of the attached recipe PDF (used for cleanup).
  final String? recipePdfPath;

  /// Original file name of the attached recipe PDF (for display).
  final String? recipePdfName;

  final bool recipesPerLine;

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
    this.recipesPerLine = false,
    this.sourceFileUrl,
    this.sourceFilePath,
    this.sourceFileName,
    this.waterGoal,
    this.sportGoal,
  }) : createDate = createDate ?? DateTime.now();

  /// Whether this diet defines a distinct weekend (Hafta Sonu) menu.
  bool get hasWeekend =>
      weekendSubtitles != null && weekendSubtitles!.isNotEmpty;

  DietRecipe? get legacyRecipe => recipesPerLine || (recipePdfUrl ?? '').isEmpty
      ? null
      : DietRecipe(url: recipePdfUrl!, path: recipePdfPath, name: recipePdfName);

  late final List<DietRecipe> recipes = _collectRecipes();

  /// Whether this diet has an attached recipe PDF.
  bool get hasRecipe => recipes.isNotEmpty;

  List<DietRecipe> _collectRecipes() {
    final Set<String> seen = <String>{};
    final DietRecipe? legacy = legacyRecipe;
    return <DietRecipe>[
      for (final DietRecipe recipe in <DietRecipe>[
        if (legacy != null) legacy,
        ..._lineRecipesOf(subtitles),
        ..._lineRecipesOf(weekendSubtitles),
      ])
        if (seen.add(recipe.url)) recipe,
    ];
  }

  static Set<String> attachmentPathsOf(Map<String, dynamic>? data) {
    final Set<String> paths = <String>{};
    void add(String? path) {
      final String trimmed = (path ?? '').trim();
      if (trimmed.isNotEmpty) paths.add(trimmed);
    }

    add(data?['recipePdfPath'] as String?);
    add(data?['sourceFilePath'] as String?);
    for (final String field in const <String>['subtitles', 'weekendSubtitles']) {
      for (final DietRecipe recipe in _lineRecipesOf(data?[field])) {
        add(recipe.path);
      }
    }
    return paths;
  }

  static Iterable<DietRecipe> _lineRecipesOf(Object? subtitles) sync* {
    if (subtitles is! Map) return;
    final List<Object?> mealKeys = <Object?>[
      for (final Meals meal in Meals.values)
        if (subtitles.containsKey(meal.name)) meal.name,
      for (final Object? key in subtitles.keys)
        if (Meals.fromName('$key') == null) key,
    ];
    for (final Object? key in mealKeys) {
      final Object? meal = subtitles[key];
      final Object? content = meal is Map ? meal['content'] : null;
      if (content is! List) continue;
      for (final Object? item in content) {
        if (item is! Map) continue;
        for (final DietRecipe? recipe
            in DietRecipe.listFrom(item[DietRecipe.lineField])) {
          if (recipe != null) yield recipe;
        }
      }
    }
  }

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
      recipesPerLine: data?[recipesPerLineField] == true,
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
      if (recipesPerLine) recipesPerLineField: true,
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
