import 'package:cloud_firestore/cloud_firestore.dart';

import 'logger.dart';

class MealModel {
  final String mealId;
  final Meals mealType;
  final String imageUrl;
  final String? subscriptionId;
  final String? description;
  final DateTime timestamp;
  final int? calories;
  final String? notes;
  bool isChecked; // Now mutable to allow state changes
  final DateTime createDate;
  final String? createUser;
  DateTime? updateDate;
  String? updateUser;

  MealModel({
    required this.mealId,
    required this.mealType,
    required this.imageUrl,
    this.subscriptionId,
    this.description,
    required this.timestamp,
    this.calories,
    this.notes,
    required this.isChecked,
    DateTime? createDate,
    this.createUser,
    this.updateDate,
    this.updateUser,
  }) : createDate = createDate ?? DateTime.now();

  factory MealModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MealModel(
      mealId: doc.id,
      mealType: Meals.values.firstWhere((e) => e.name == data['mealType']),
      imageUrl: data['imageUrl'],
      subscriptionId: data['subscriptionId'],
      description: data['description'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      calories: data['calories'],
      notes: data['notes'],
      isChecked: data['isChecked'] ?? false,
      createDate: data['createDate'] != null ? (data['createDate'] as Timestamp).toDate() : DateTime.now(),
      createUser: data['createUser'],
      updateDate: data['updateDate'] != null ? (data['updateDate'] as Timestamp).toDate() : null,
      updateUser: data['updateUser'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mealType': mealType.name,
      'imageUrl': imageUrl,
      'subscriptionId': subscriptionId,
      'description': description,
      'timestamp': Timestamp.fromDate(timestamp),
      'calories': calories,
      'notes': notes,
      'isChecked': isChecked,
      'createDate': Timestamp.fromDate(createDate),
      if (createUser != null) 'createUser': createUser,
      if (updateDate != null) 'updateDate': Timestamp.fromDate(updateDate!),
      if (updateUser != null) 'updateUser': updateUser,
    };
  }
}

final Logger logger = Logger.forClass(Meals);

/// word dokumaninda ara ogun ararken aranan ifade "Ara"
const String ARA_WORD_LABEL='Ara';
enum Meals {

  br('Sabah', '09:00'),
  firstmid('Ara Öğün 1', '10:30'),
  lunch('Öğle', '12:30'),
  secondmid('Ara Öğün 2', '16:00'),
  dinner('Akşam', '19:00'),
  thirdmid('Ara Öğün 3', '21:00'),
  none('Hiçbiri', '');

  const Meals(this.label, this.defaultTime);

  final String label;
  final String defaultTime;

  /// Actual meal types used for diets, tracking, and reminders (excludes [none]).
  static List<Meals> get dietValues =>
      values.where((m) => m != Meals.none).toList();

  /// Returns a simplified display label where all "Ara Öğün" types are shown as just "Ara"
  String get displayLabel {
    if (this == Meals.firstmid || this == Meals.secondmid || this == Meals.thirdmid) {
      return 'Ara';
    }
    return label;
  }

  static Meals? fromName(String name) {
    try {
      return Meals.values.firstWhere((meal) => meal.name== name);
    } catch (e) {
      logger.warn('No matching meal found for name: {}', [name]);
      return null; // Return null if no match is found
    }
  }
}
