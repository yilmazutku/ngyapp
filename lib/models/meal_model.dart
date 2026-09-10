import 'package:cloud_firestore/cloud_firestore.dart';

import 'logger.dart';

class MealModel {
  static const int maxImages = 3;

  final String mealId;
  final Meals mealType;
  final List<String> imageUrls;

  /// [imageUrls] ile paralel küçük görsel adresleri; küçük görseli olmayan
  /// fotoğrafın yerinde boş dize durur. Liste ekranları tam boy fotoğraf
  /// yerine bunu indirir. Eski kayıtlarda liste boş olabilir; hizasız bir
  /// liste [thumbUrlAt] tarafından güvenle yok sayılır.
  final List<String> thumbUrls;
  final String? subscriptionId;
  final String? description;
  final DateTime timestamp;
  final int? calories;
  final String? notes;
  bool isChecked;
  final DateTime createDate;
  final String? createUser;
  DateTime? updateDate;
  String? updateUser;

  MealModel({
    required this.mealId,
    required this.mealType,
    required this.imageUrls,
    List<String>? thumbUrls,
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
  })  : thumbUrls = thumbUrls ?? const [],
        createDate = createDate ?? DateTime.now();

  /// First image URL for convenience, or empty string if none.
  String get imageUrl => imageUrls.isNotEmpty ? imageUrls.first : '';

  /// [index]. fotoğrafın küçük görsel adresi; yoksa null.
  String? thumbUrlAt(int index) {
    if (index < 0 || index >= thumbUrls.length) return null;
    final String url = thumbUrls[index];
    return url.isEmpty ? null : url;
  }

  /// [thumbUrls]'i [imageUrls] ile aynı uzunluğa getirir (eksikler boş dize,
  /// fazlalar atılır). Listeyi değiştiren her yazıcı bunu kullanır ki iki liste
  /// hiç hizasız kalmasın.
  List<String> alignedThumbUrls() => List<String>.generate(
        imageUrls.length,
        (i) => i < thumbUrls.length ? thumbUrls[i] : '',
      );

  bool get canAddMoreImages => imageUrls.length < maxImages;

  factory MealModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Backward compat: read new list field first, fall back to legacy string
    List<String> urls;
    if (data['imageUrls'] is List) {
      urls = List<String>.from(data['imageUrls']);
    } else if (data['imageUrl'] is String &&
        (data['imageUrl'] as String).isNotEmpty) {
      urls = [data['imageUrl'] as String];
    } else {
      urls = [];
    }

    return MealModel(
      mealId: doc.id,
      mealType: Meals.values.firstWhere((e) => e.name == data['mealType']),
      imageUrls: urls,
      thumbUrls: data['thumbUrls'] is List
          ? List<String>.from(
              (data['thumbUrls'] as List).map((e) => e is String ? e : ''))
          : const [],
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
      'imageUrls': imageUrls,
      'thumbUrls': alignedThumbUrls(),
      // Keep legacy field for any readers that still use it
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

  /// Ara öğün mü (numaralı üç ara öğünden biri).
  bool get isSnack =>
      this == Meals.firstmid ||
      this == Meals.secondmid ||
      this == Meals.thirdmid;

  /// Fotoğraf ekranlarında gösterilen öğün adı.
  ///
  /// Ara öğünler numaralandırılmadan tek ad altında toplanır: fotoğrafa
  /// bakarken "Ara Öğün 1/2/3" ayrımının bilgi değeri yok, kart etiketini
  /// gereksiz uzatıyor. Diyet ekranları ve hatırlatmalar kendi adlarını
  /// ([label], [displayLabel]) kullanmayı sürdürür.
  String get photoLabel => isSnack ? snackPhotoLabel : label;

  /// Ara öğünlerin fotoğraf ekranlarındaki ortak adı.
  static const String snackPhotoLabel = 'Ara Öğün';

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
