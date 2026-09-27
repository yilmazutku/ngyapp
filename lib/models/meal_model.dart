import 'package:cloud_firestore/cloud_firestore.dart';

class MealModel {
  static const int maxImages = 10;

  /// Öğündeki fotoğraf sınırı dolmuşken yeni fotoğraf denendiğinde gösterilen
  /// uyarı; sohbet ve "Planım" aynı metni kullanır.
  static const String maxImagesReachedTitle = 'Fotoğraf Sınırı';
  static const String maxImagesReachedMessage =
      'Bir öğün için en fazla $maxImages fotoğraf yüklenmesine izin '
      'verilmektedir.';

  final String mealId;
  final Meals mealType;
  final List<String> imageUrls;

  /// [imageUrls] ile paralel yükleme saatleri. [timestamp] öğüne en son
  /// fotoğrafın eklendiği saattir; aynı öğündeki her fotoğrafın kendi saati
  /// buradan okunur ([imageTimeAt]). Bu alandan önceki kayıtlarda liste boştur.
  final List<DateTime> imageTimes;

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
    List<DateTime>? imageTimes,
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
        imageTimes = imageTimes ?? const [],
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

  /// [index]. fotoğrafın yükleme saati. Saati kaydedilmemiş eski
  /// fotoğraflarda öğünün saatine ([timestamp]) düşer.
  DateTime imageTimeAt(int index) =>
      index >= 0 && index < imageTimes.length ? imageTimes[index] : timestamp;

  /// [imageTimes]'ı [imageUrls] ile aynı uzunluğa getirir; eksik saatler
  /// [timestamp] ile doldurulur (bkz. [alignedThumbUrls]).
  List<DateTime> alignedImageTimes() =>
      List<DateTime>.generate(imageUrls.length, imageTimeAt);

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

    final DateTime timestamp = (data['timestamp'] as Timestamp).toDate();

    return MealModel(
      mealId: doc.id,
      mealType: Meals.values.firstWhere((e) => e.name == data['mealType']),
      imageUrls: urls,
      thumbUrls: data['thumbUrls'] is List
          ? List<String>.from(
              (data['thumbUrls'] as List).map((e) => e is String ? e : ''))
          : const [],
      imageTimes: data['imageTimes'] is List
          ? (data['imageTimes'] as List)
              .map((e) => e is Timestamp ? e.toDate() : timestamp)
              .toList()
          : const [],
      subscriptionId: data['subscriptionId'],
      description: data['description'],
      timestamp: timestamp,
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
      'imageTimes': alignedImageTimes().map(Timestamp.fromDate).toList(),
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

/// word dokumaninda ara ogun ararken aranan ifade "Ara"
const String ARA_WORD_LABEL='Ara';
enum Meals {

  br('Sabah', '09:00'),
  firstmid('Ara Öğün 1', '10:30'),
  lunch('Öğle', '12:30'),
  secondmid('Ara Öğün 2', '16:00'),
  dinner('Akşam', '19:00'),
  thirdmid('Ara Öğün 3', '21:00'),
  none('Diğer', '');

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

  /// Fotoğraf ekranlarında, sohbette ve bildirimlerde gösterilen öğün adı.
  ///
  /// Ara öğünler numaralandırılmadan tek ad altında toplanır: kullanıcıya
  /// hiçbir yerde "Ara Öğün 1/2/3" gösterilmez. Numaralı [label] yalnızca
  /// diyet yapısında (diyet dosyası ayrıştırma, diyet düzenleme) kullanılır;
  /// hatırlatmalar [displayLabel] ile "Ara" der.
  String get photoLabel => isSnack ? snackPhotoLabel : label;

  /// Ara öğünlerin fotoğraf ekranlarındaki ortak adı.
  static const String snackPhotoLabel = 'Ara Öğün';

  /// Sohbete düşen öğün fotoğrafının mesaj açıklaması: "Öğün: Ara Öğün".
  String get chatCaption => '$chatCaptionPrefix$photoLabel';

  /// Sohbet listesindeki son mesaj özeti: "Öğün Fotoğrafı (Ara Öğün)".
  String get chatSummary => '$_chatSummaryPrefix$photoLabel)';

  /// Öğün fotoğrafı mesajının açıklamasının öneki (bkz. [chatCaption]).
  static const String chatCaptionPrefix = 'Öğün: ';
  static const String _chatSummaryPrefix = 'Öğün Fotoğrafı (';

  /// Öğün fotoğrafı mesajının `storagePath` alanındaki işaretin öneki:
  /// "meals/{uid}/{öğün}". Storage yolu değildir; mesajın hangi öğüne ait
  /// olduğunu söyler.
  static const String chatMarkerPrefix = 'meals/';

  /// Fotoğrafı silinen öğün mesajının açıklamasına eklenen not.
  static const String deletedPhotoSuffix = '(fotoğraf silindi)';

  /// Açıklaması olmayan bir fotoğraf mesajının fotoğrafı silindiğinde yazılan
  /// metin.
  static const String deletedPhotoText = 'Fotoğraf silindi';

  /// [none] önceki sürümlerde bu adla yazılıyordu.
  static const String _legacyNoneLabel = 'Hiçbiri';

  /// Uygulamanın sohbete yazdığı öğün metinlerini ([chatCaption],
  /// [chatSummary]) bugünkü adlarla verir: eski mesajlardaki "Ara Öğün 2"
  /// "Ara Öğün", "Hiçbiri" "Diğer" olur. Kullanıcının yazdığı metinlere
  /// dokunulmaz.
  static String chatTextForDisplay(String text) {
    if (!text.startsWith(chatCaptionPrefix) &&
        !text.startsWith(_chatSummaryPrefix)) {
      return text;
    }

    String result = text.replaceFirst(_legacyNoneLabel, none.photoLabel);
    for (final Meals meal in values) {
      if (meal.isSnack) {
        result = result.replaceFirst(meal.label, meal.photoLabel);
      }
    }
    return result;
  }

  /// Fotoğrafı silinen mesajın yeni metni: "Öğün: Öğle (fotoğraf silindi)";
  /// açıklaması yoksa [deletedPhotoText].
  static String deletedPhotoChatText(String? text) {
    final String caption = chatTextForDisplay(text ?? '').trim();
    return caption.isEmpty
        ? deletedPhotoText
        : '$caption $deletedPhotoSuffix';
  }

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
      return null; // Return null if no match is found
    }
  }
}
