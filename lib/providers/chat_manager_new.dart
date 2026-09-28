// lib/providers/chat_manager_new.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/meal_model.dart';
import '../models/pending_upload.dart';
import '../utils/storage_upload.dart';

/// Data Transfer Object representing a chat message from Firestore.
/// 
/// Structure:
/// - id: Firestore document ID
/// - chatId: The chat identifier (equals user UID in our one-chat-per-user model)
/// - senderId: UID of the user who sent the message
/// - text: Optional text content (null for image-only messages)
/// - imageUrl: Optional Firebase Storage download URL for images
/// - storagePath: Optional Storage path for cleanup operations
/// - createdAt: Server-side timestamp (authoritative)
/// - clientCreatedAt: Client-side timestamp (fallback while server timestamp is pending)
/// - reactions: Map of reactorUid -> emoji (e.g. {adminUid: '👍'}). Empty when no
///   one has reacted. Only one reaction per person is kept (WhatsApp-style).
/// - thumbUrl / imageWidth / imageHeight: fotoğrafın küçük görseli ve piksel
///   ölçüsü (bu alanlardan önceki mesajlarda yok).
/// - replyTo: yanıtlanan mesajın özeti (bkz. [MessageReply]).
class MessageData {
  final String id;
  final String chatId; //chatId if provided (admin viewing another user), otherwise current user's UID
  final String senderId;
  final String? text;
  final String? imageUrl;
  final String? storagePath;
  final Timestamp? createdAt;
  final Timestamp? clientCreatedAt;

  /// Fotoğrafın küçük görseli: sohbet baloncuğu ve listeler bunu indirir,
  /// orijinal yalnızca büyütünce iner. Eski mesajlarda null.
  final String? thumbUrl;

  /// Fotoğrafın piksel ölçüsü: baloncuk, görsel inmeden doğru oranda yer
  /// ayırır (liste kaymaz). Eski mesajlarda null.
  final int? imageWidth;
  final int? imageHeight;

  /// Bu mesaj bir mesaja yanıtsa, yanıtlanan mesajın özeti.
  final MessageReply? replyTo;

  /// Reactions left on this message, keyed by the reactor's UID.
  /// The value is the reaction emoji (e.g. '👍' or '❤️').
  final Map<String, String> reactions;

  /// Mesajdaki öğün fotoğrafı silindi mi. Silinen fotoğrafın mesajı kaybolmaz,
  /// "Öğün: Öğle (fotoğraf silindi)" notuna döner (bkz.
  /// `MealManager.deleteMealImage`).
  final bool photoDeleted;

  MessageData({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.text,
    this.imageUrl,
    this.storagePath,
    this.createdAt,
    this.clientCreatedAt,
    this.reactions = const {},
    this.photoDeleted = false,
    this.thumbUrl,
    this.imageWidth,
    this.imageHeight,
    this.replyTo,
  });

  /// Fotoğrafın en/boy oranı; ölçüsü kayıtlı değilse null.
  double? get imageAspectRatio {
    final int? width = imageWidth;
    final int? height = imageHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }

  /// Mesajın zamanı: sunucu zamanı, henüz yoksa cihazın yazdığı zaman.
  DateTime? get sentAt => (createdAt ?? clientCreatedAt)?.toDate();

  /// Danışanın sohbetten yüklediği öğün fotoğrafı mı (bkz.
  /// `MealManager.uploadMealImg`, `alsoPostToChat`).
  bool get isMealPhoto =>
      (imageUrl ?? '').isNotEmpty &&
      ((storagePath ?? '').startsWith(Meals.chatMarkerPrefix) ||
          (text ?? '').startsWith(Meals.chatCaptionPrefix));

  /// Öğün fotoğrafı mesajının öğünü: önce `storagePath` işaretinden
  /// ("meals/{uid}/{öğün}"), yoksa açıklamadan ("Öğün: Öğle"). Açıklamadan
  /// okunan ara öğün, numarası yazılmadığı için ilk ara öğüne düşer.
  /// Bulunamazsa null.
  Meals? get photoMeal {
    final String path = storagePath ?? '';
    if (path.startsWith(Meals.chatMarkerPrefix)) {
      final Meals? byName = Meals.fromName(path.split('/').last);
      if (byName != null) return byName;
    }

    final String caption = Meals.chatTextForDisplay(text ?? '');
    if (!caption.startsWith(Meals.chatCaptionPrefix)) return null;
    final String label =
        caption.substring(Meals.chatCaptionPrefix.length).trim();
    for (final Meals meal in Meals.values) {
      if (meal.displayLabel == label) return meal;
    }
    return null;
  }

  /// Factory constructor to create a MessageData instance from a Firestore snapshot.
  factory MessageData.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? {};
    return MessageData(
      id: snap.id,
      chatId: (data['chatId'] ?? '') as String,
      senderId: (data['senderId'] ?? '') as String,
      text: data['text'] as String?,
      imageUrl: data['imageUrl'] as String?,
      storagePath: data['storagePath'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      clientCreatedAt: data['clientCreatedAt'] as Timestamp?,
      reactions: parseReactions(data['reactions']),
      photoDeleted: data['photoDeleted'] == true,
      thumbUrl: data['thumbUrl'] as String?,
      imageWidth: (data['imageWidth'] as num?)?.toInt(),
      imageHeight: (data['imageHeight'] as num?)?.toInt(),
      replyTo: MessageReply.fromMap(data['replyTo']),
    );
  }

  /// Safely convert the raw Firestore `reactions` field into a
  /// `Map<String, String>`. Firestore may hand us a `Map<Object?, Object?>`,
  /// so we defensively filter to string keys and non-empty string values.
  static Map<String, String> parseReactions(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value is String && value.isNotEmpty) {
        out[key] = value;
      }
    });
    return out;
  }
}

/// Yanıtlanan mesajın, yanıtın içinde saklanan özeti. Yanıt baloncuğunda
/// alıntı olarak görünür; alıntıya dokununca sohbet o mesaja gider
/// ([messageId]). Özet yanıt anında kopyalanır: asıl mesaj sonradan
/// değişse de alıntı okunur kalır.
class MessageReply {
  final String messageId;
  final String senderId;

  /// Mesajın metni (kısaltılmış); fotoğraf mesajında açıklaması ya da boş.
  final String text;

  /// Fotoğraf mesajıysa küçük görseli (yoksa asıl görseli).
  final String? imageUrl;

  const MessageReply({
    required this.messageId,
    required this.senderId,
    required this.text,
    this.imageUrl,
  });

  /// Alıntıda saklanan en uzun metin.
  static const int _maxTextLength = 200;

  factory MessageReply.of(MessageData message) {
    final String text = Meals.chatTextForDisplay(message.text ?? '').trim();
    return MessageReply(
      messageId: message.id,
      senderId: message.senderId,
      text: text.length > _maxTextLength
          ? '${text.substring(0, _maxTextLength)}…'
          : text,
      imageUrl: message.thumbUrl ?? message.imageUrl,
    );
  }

  static MessageReply? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['messageId'];
    final Object? senderId = raw['senderId'];
    if (id is! String || senderId is! String) return null;
    final Object? text = raw['text'];
    final Object? imageUrl = raw['imageUrl'];
    return MessageReply(
      messageId: id,
      senderId: senderId,
      text: text is String ? text : '',
      imageUrl: imageUrl is String && imageUrl.isNotEmpty ? imageUrl : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'messageId': messageId,
        'senderId': senderId,
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };
}

/// Sohbet bir mesajda açılamadığında sebebi (bkz. [ChatManager.openFocusWindow]).
enum FocusWindowFailure {
  /// Mesaj sohbette yok (ör. sohbet silinmiş).
  notFound,

  /// Mesaj sohbetin çok gerisinde: ondan sonra
  /// [ChatManager.focusWindowMaxNewer]'dan fazla mesaj var.
  tooOld,
}

/// Sohbeti bir mesajda açmak için yüklenen mesajlar: hedef ve ondan yeniler
/// canlı ([messages], en yeni başta), hedeften eski birkaç mesaj tek seferlik
/// ([olderMessages], en yeni başta). Açılamadıysa [failure] dolu, diğerleri
/// boştur.
class FocusWindow {
  final Stream<List<MessageData>>? messages;
  final List<MessageData> olderMessages;
  final FocusWindowFailure? failure;

  const FocusWindow._({
    required Stream<List<MessageData>> this.messages,
    required this.olderMessages,
  }) : failure = null;

  const FocusWindow.failed(FocusWindowFailure this.failure)
      : messages = null,
        olderMessages = const [];
}

/// ChatManager handles all chat-related operations including:
/// - Sending text messages
/// - Sending images with compression, thumbnails and progress tracking
/// - Keeping the queue of photos waiting to be uploaded ([PendingUpload])
/// - Managing chat document structure
/// 
/// Architecture:
/// - One chat per user: chatId == userUid
/// - Collection structure: chats/{userUid}/messages/*
/// - The admin UID is automatically added as a participant in every chat
/// - Supports admin viewing any user's chat
/// 
/// Admin UID:
/// - Nilay: 0MvvbZsjbmNPW4QYShRNSOOtkE43
class ChatManager extends ChangeNotifier {
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final FirebaseStorage storage;

  /// Admin user IDs - these users have elevated permissions and are participants in all chats
  static const Set<String> adminIds = {
    '0MvvbZsjbmNPW4QYShRNSOOtkE43', // Nilay
    'SdPI69ChOvepuq9HrlW6no9rMRn1', // Admin
  };

  /// Check if a given UID belongs to an admin user
  static bool isAdminUid(String uid) => adminIds.contains(uid);

  /// Get admin IDs set (for external access)
  static Set<String> get adminUids => adminIds;

  ChatManager({
    required this.db,
    required this.auth,
    required this.storage,
  });


  // ===== Bekleyen fotoğraf yüklemeleri =====

  /// Sohbet -> yüklenmeyi bekleyen fotoğraflar (sıra sırasıyla). Liste her
  /// değişiklikte yenisiyle değiştirilir: ekran `Selector` ile yalnızca
  /// değişince yeniden çizilir.
  final Map<String, List<PendingUpload>> _pendingUploads = {};

  /// Sırası şu an işlenen sohbetler; bir sohbette aynı anda tek yükleme
  /// yapılır (aynı öğün kaydına iki fotoğraf aynı anda yazılmasın).
  final Set<String> _drainingChats = {};

  /// [chatId] sohbetinde yüklenmeyi bekleyen fotoğraflar.
  List<PendingUpload> pendingUploadsOf(String chatId) =>
      _pendingUploads[chatId] ?? const [];

  /// Fotoğrafları sıraya ekler ve sırayı işletir. Sohbet ekranı kapansa da
  /// yükleme sürer.
  void enqueueUploads(List<PendingUpload> uploads) {
    if (uploads.isEmpty) return;
    final Set<String> chatIds = {};
    for (final PendingUpload upload in uploads) {
      _pendingUploads[upload.chatId] = [
        ...pendingUploadsOf(upload.chatId),
        upload,
      ];
      chatIds.add(upload.chatId);
    }
    notifyListeners();
    chatIds.forEach(_drainUploads);
  }

  /// Yüklenemeyen fotoğrafı aynı yerinde yeniden sıraya koyar.
  void retryUpload(PendingUpload upload) {
    final List<PendingUpload> current = pendingUploadsOf(upload.chatId);
    final int index = current.indexOf(upload);
    if (index < 0) return;
    _pendingUploads[upload.chatId] = [...current]..[index] = upload.retryCopy();
    notifyListeners();
    _drainUploads(upload.chatId);
  }

  /// Fotoğrafı sıradan çıkarır; yükleniyorsa iptal edilir, mesaj yazılmaz.
  void discardUpload(PendingUpload upload) {
    upload.cancel();
    _removePendingUpload(upload);
  }

  void _removePendingUpload(PendingUpload upload) {
    final List<PendingUpload> current = pendingUploadsOf(upload.chatId);
    if (!current.contains(upload)) return;
    _pendingUploads[upload.chatId] =
        current.where((item) => item != upload).toList();
    notifyListeners();
  }

  /// Sohbetin sırasını baştan sona tek tek işler.
  Future<void> _drainUploads(String chatId) async {
    if (!_drainingChats.add(chatId)) return;
    try {
      while (true) {
        final PendingUpload? next = _nextWaitingUpload(chatId);
        if (next == null) return;
        await _runUpload(next);
      }
    } finally {
      _drainingChats.remove(chatId);
    }
  }

  PendingUpload? _nextWaitingUpload(String chatId) {
    for (final PendingUpload upload in pendingUploadsOf(chatId)) {
      if (upload.status.value == PendingUploadStatus.waiting) return upload;
    }
    return null;
  }

  /// Tek bir yüklemeyi yapar. İptal ya da zaman aşımında yarıda kalan
  /// yükleme beklenmez ([PendingUpload.aborted]); iptal edilmiş yükleme kayıt
  /// yazmaz (bkz. [uploadImageWithThumbnail]).
  Future<void> _runUpload(PendingUpload upload) async {
    upload.markUploading();
    try {
      await Future.any<void>([upload.runner(upload), upload.aborted]);
      if (upload.timedOut) {
        upload.markFailed(PendingUpload.timeoutText);
      } else {
        _removePendingUpload(upload);
      }
    } on UploadFailure catch (e) {
      upload.markFailed(e.message, canRetry: e.canRetry);
    } catch (e) {
      if (upload.cancelledByUser) {
        _removePendingUpload(upload);
      } else {
        upload.markFailed(upload.timedOut
            ? PendingUpload.timeoutText
            : PendingUpload.defaultErrorText);
      }
    }
  }

  /// Current authenticated user's UID
  String get userId => auth.currentUser!.uid;

  /// Returns the chat ID for a given user UID.
  /// In our one-chat-per-user model, chatId equals the user's UID.
  String chatIdForUser(String uid) {
    return uid;
  }

  // ===== Firestore References =====
  
  /// Sohbete doğrudan gönderilen görsellerin Storage klasörü. [deleteChat]
  /// yalnızca bu klasördeki dosyaları siler.
  String _chatStorageFolder(String chatId) => 'chats/$chatId';

  /// Returns a reference to the chat document for a given chatId
  DocumentReference<Map<String, dynamic>> _chatDoc(String chatId) =>
      db.collection('chats').doc(chatId);

  /// Sohbet açılışında ve eski mesajlar yüklenirken bir seferde okunan mesaj
  /// sayısı.
  static const int messagesPageSize = 30;

  /// Messages of a chat, newest first.
  Query<Map<String, dynamic>> _newestFirst(String chatId) => _chatDoc(chatId)
      .collection('messages')
      .orderBy('createdAt', descending: true);

  static List<MessageData> _toMessages(
          QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map((d) => MessageData.fromSnapshot(d)).toList();

  /// Returns a stream of messages for a specific chat.
  /// Messages are ordered newest-first and limited to [messagesPageSize].
  ///
  /// Usage: Used by UI to reactively display messages.
  Stream<List<MessageData>> messagesStreamFor(String chatId) {
    return _newestFirst(chatId)
        .limit(messagesPageSize)
        .snapshots()
        .map(_toMessages);
  }

  /// [since] anındaki mesajdan bugüne kadar bütün mesajlar, canlı (en yeni
  /// başta). Alt ucu sabit olduğu için yeni mesaj geldikçe liste büyür, hiçbir
  /// mesaj listeden düşmez: altına [fetchMessagesBefore] ile eklenen eski
  /// sayfalarla arada boşluk kalmaz.
  Stream<List<MessageData>> messagesSinceStream(
    String chatId,
    Timestamp since,
  ) {
    return _newestFirst(chatId).endAt([since]).snapshots().map(_toMessages);
  }

  /// [before] anından eski en fazla [limit] mesaj, tek seferlik (en yeni
  /// başta). Sohbette yukarı kaydırıldıkça eski mesajları sayfa sayfa yüklemek
  /// için kullanılır.
  ///
  /// Sunucudan okunur: çevrimdışıyken önbellekten gelen eksik bir sonuç
  /// "sohbetin başına gelindi" sanılmasın, hata olarak dönsün.
  Future<List<MessageData>> fetchMessagesBefore(
    String chatId,
    Timestamp before, {
    int limit = messagesPageSize,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _newestFirst(chatId)
        .startAfter([before])
        .limit(limit)
        .get(const GetOptions(source: Source.server));
    return _toMessages(snap);
  }

  /// Tek bir mesajı okur; yoksa null. Canlı dinlenmeyen eski sayfalardaki bir
  /// mesaj üzerinde işlem yapılınca (ifade, fotoğraf silme) güncel hâlini
  /// göstermek için kullanılır.
  Future<MessageData?> fetchMessage(String chatId, String messageId) async {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _chatDoc(chatId).collection('messages').doc(messageId).get();
    return doc.exists ? MessageData.fromSnapshot(doc) : null;
  }

  /// Sohbette bir fotoğrafın mesajını adresinden ([imageUrl]) bulur.
  ///
  /// Öğün fotoğrafı sohbete yüklenirken mesaja fotoğrafın indirme adresi
  /// yazılır (bkz. `MealManager.uploadMealImg`), bu yüzden eşleme adres
  /// üzerinden yapılır. Sohbete hiç düşmemiş bir fotoğraf için null döner.
  ///
  /// Dönen mesaj kimliğinin yanında üzerindeki tepkileri de taşır: fotoğrafa
  /// sohbet dışından ifade bırakılırken bırakanın o mesajdaki mevcut ifadesi
  /// buradan okunur ([toggleReaction] için gereken `currentEmoji`).
  ///
  /// Sorgu tek alan üzerinde (`imageUrl` eşitliği): Firestore'da kendiliğinden
  /// indekslidir, bileşik indeks gerekmez.
  Future<MessageData?> findImageMessage(String chatId, String imageUrl) async {
    if (imageUrl.isEmpty) return null;

    final QuerySnapshot<Map<String, dynamic>> matches = await _chatDoc(chatId)
        .collection('messages')
        .where('imageUrl', isEqualTo: imageUrl)
        .limit(1)
        .get();
    if (matches.docs.isEmpty) return null;

    return MessageData.fromSnapshot(matches.docs.first);
  }

  /// Firestore `whereIn` sorgusunun tek seferde kabul ettiği değer sayısı.
  static const int _whereInLimit = 30;

  /// ADMIN ÇAĞIRIR: [chatId] sohbetinde verilen fotoğrafların ([imageUrls])
  /// mesajlarına bırakılmış tepkiler (adres -> (uid -> emoji)); yalnızca
  /// tepkisi olan fotoğraflar döner.
  ///
  /// Öğün fotoğrafı sohbete yüklenirken mesaja fotoğrafın indirme adresi
  /// yazılır ([findImageMessage] ile aynı eşleme), bu yüzden mesajlar gün
  /// aralığıyla değil doğrudan adresle bulunur: fotoğraf hangi saat diliminde
  /// ya da gece yarısına ne kadar yakın yüklenmiş olursa olsun mesajı
  /// kaçırılmaz ve yalnızca fotoğraf mesajları okunur. Sorgu tek alan üzerinde
  /// (`imageUrl`), bileşik indeks gerekmez.
  Future<Map<String, Map<String, String>>> fetchImageReactions(
    String chatId,
    List<String> imageUrls,
  ) async {
    final List<String> urls =
        imageUrls.where((url) => url.isNotEmpty).toSet().toList();
    if (urls.isEmpty) return {};

    final List<Future<QuerySnapshot<Map<String, dynamic>>>> queries = [
      for (int from = 0; from < urls.length; from += _whereInLimit)
        _chatDoc(chatId)
            .collection('messages')
            .where(
              'imageUrl',
              whereIn: urls.sublist(from, min(from + _whereInLimit, urls.length)),
            )
            .get(),
    ];

    final Map<String, Map<String, String>> reactions = {};
    for (final QuerySnapshot<Map<String, dynamic>> snapshot
        in await Future.wait(queries)) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final Map<String, dynamic> data = doc.data();
        final String imageUrl = (data['imageUrl'] as String?) ?? '';
        final Map<String, String> parsed =
            MessageData.parseReactions(data['reactions']);
        if (imageUrl.isEmpty || parsed.isEmpty) continue;
        reactions[imageUrl] = parsed;
      }
    }
    return reactions;
  }

  /// Sohbet bir mesajda açıldığında (bkz. [openFocusWindow]) hedeften yeni en
  /// fazla kaç mesaj yüklenir. Hedef bundan daha gerideyse sohbet en yeni
  /// mesajdan açılır: yüzlerce mesajı birden okumak hem yavaş hem pahalı.
  static const int focusWindowMaxNewer = 300;

  /// Hedef mesajın üstünde, bağlam için gösterilen eski mesaj sayısı.
  static const int focusWindowOlderCount = 20;

  /// Sohbeti [messageId] mesajında açmak için gereken mesajları yükler.
  ///
  /// Normal sohbet son [messagesPageSize] mesajla açılır; hedef daha eskiyse
  /// onu göremezdi. Burada sorgu hedefi kapsayacak şekilde kurulur: hedef ve
  /// ondan yeni bütün mesajlar canlı dinlenir ([messagesSinceStream]), hedeften
  /// eski [focusWindowOlderCount] mesaj da bağlam için bir kez okunur. Yeni
  /// mesaj geldikçe pencere büyür, hedef pencereden hiç düşmez; daha eskisi
  /// yukarı kaydırıldıkça yüklenir.
  ///
  /// Mesaj yoksa ya da hedeften sonra [focusWindowMaxNewer]'dan fazla mesaj
  /// varsa pencere açılmaz; sebep [FocusWindow.failure] ile döner.
  Future<FocusWindow> openFocusWindow(String chatId, String messageId) async {
    final CollectionReference<Map<String, dynamic>> messages =
        _chatDoc(chatId).collection('messages');

    final DocumentSnapshot<Map<String, dynamic>> target =
        await messages.doc(messageId).get();
    final Map<String, dynamic>? data = target.data();
    final Object? createdAt = data?['createdAt'] ?? data?['clientCreatedAt'];
    if (createdAt is! Timestamp) {
      return const FocusWindow.failed(FocusWindowFailure.notFound);
    }

    final AggregateQuerySnapshot newer = await messages
        .where('createdAt', isGreaterThanOrEqualTo: createdAt)
        .count()
        .get();
    if ((newer.count ?? 0) > focusWindowMaxNewer) {
      return const FocusWindow.failed(FocusWindowFailure.tooOld);
    }

    return FocusWindow._(
      messages: messagesSinceStream(chatId, createdAt),
      olderMessages: await fetchMessagesBefore(
        chatId,
        createdAt,
        limit: focusWindowOlderCount,
      ),
    );
  }

  /// Returns a live stream of every photo the *user* (chatId == userId) has
  /// uploaded to their chat, newest first.
  ///
  /// Includes both direct chat images and meal photos, since both are stored as
  /// messages with `senderId == userId` and a non-empty `imageUrl`. The admin's
  /// own uploaded images are intentionally excluded.
  ///
  /// Implementation note: this filters by `senderId` only — a single-field
  /// equality that Firestore indexes automatically — and sorts client-side, so
  /// it needs NO composite index.
  Stream<List<MessageData>> userUploadedImagesStream(String userId) {
    return _chatDoc(userId)
        .collection('messages')
        .where('senderId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final images = snap.docs
          .map((d) => MessageData.fromSnapshot(d))
          .where((m) => (m.imageUrl ?? '').isNotEmpty)
          .toList();

      // Newest first; messages still awaiting a server timestamp sink to the end.
      images.sort((a, b) {
        final at = a.createdAt ?? a.clientCreatedAt;
        final bt = b.createdAt ?? b.clientCreatedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

      return images;
    });
  }

  /// Sohbet dokümanına `set(merge: true)` ile yazılan özet ve sayaçlar;
  /// mesajla aynı toplu yazımda gider.
  ///
  /// This data:
  /// - Creates the chat document if it doesn't exist
  /// - Adds both admin UIDs and the user as participants
  /// - Updates last message info for the admin chat list
  /// - Increments unread count for admins when user sends a message
  /// - Increments unread count for user when admin sends a message
  /// - Updates hasUnreadFor array for efficient unread count queries
  Map<String, dynamic> _chatSummaryData(
      String chatId, {
        String? lastMessage,
        String? lastImageUrl,
        String? lastImageThumbUrl,
        Timestamp? lastAt,
        bool incrementUnreadForAdmins = false,
        bool incrementUnreadForUser = false,
      }) {
    final participants = <String>{chatId, ...adminIds}.toList();
    
    // Everything lands in one write. set(merge: true) merges nested maps field
    // by field, so 'adminUnreadCount' can be written as a nested map instead of
    // the dot-notation keys that would force a second update() round trip.
    // Both unread flags feed a single arrayUnion, so raising them together can
    // no longer drop one side from hasUnreadFor.
    final unreadFor = <String>[
      if (incrementUnreadForAdmins) ...adminIds,
      if (incrementUnreadForUser) chatId,
    ];

    return <String, dynamic>{
      'participants': participants,
      if (lastMessage != null) 'lastMessage': lastMessage,
      if (lastImageUrl != null) 'lastImageUrl': lastImageUrl,
      if (lastImageThumbUrl != null) 'lastImageThumbUrl': lastImageThumbUrl,
      if (lastAt != null) 'lastMessageAt': lastAt,
      'updatedAt': FieldValue.serverTimestamp(),
      if (incrementUnreadForAdmins)
        'adminUnreadCount': {
          for (final adminUid in adminIds) adminUid: FieldValue.increment(1),
        },
      if (incrementUnreadForUser) 'userUnreadCount': FieldValue.increment(1),
      if (unreadFor.isNotEmpty) 'hasUnreadFor': FieldValue.arrayUnion(unreadFor),
    };
  }

  /// Mark a chat as read for the current admin user.
  /// Resets the unread count to 0, updates lastReadAt timestamp,
  /// and removes admin from hasUnreadFor array for efficient count queries.
  /// 
  /// Uses update() because dot-notation keys (adminUnreadCount.<uid>) only
  /// resolve as nested field paths with update(), not with set()+merge.
  /// 
  /// Call this when admin opens a chat.
  Future<void> markChatAsRead(String chatId) async {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null || !isAdminUid(currentUid)) {
      return;
    }
    
    try {
      await _chatDoc(chatId).update({
        'adminUnreadCount.$currentUid': 0,
        'adminLastReadAt.$currentUid': FieldValue.serverTimestamp(),
        'hasUnreadFor': FieldValue.arrayRemove([currentUid]),
      });
    } catch (e) {
      // Document may not exist yet (e.g. admin opens a new chat before any messages)
    }
  }

  /// Mark a chat as read for the current regular user.
  /// Resets the userUnreadCount to 0 and removes user from hasUnreadFor array.
  /// 
  /// Call this when a regular user opens their chat.
  Future<void> markChatAsReadForUser(String chatId) async {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null) {
      return;
    }
    
    // Skip if current user is an admin (they use markChatAsRead instead)
    if (isAdminUid(currentUid)) {
      return;
    }
    
    // Only mark as read if this is the user's own chat
    if (currentUid != chatId) {
      return;
    }
    
    await _chatDoc(chatId).set({
      'userUnreadCount': 0,
      'userLastReadAt': FieldValue.serverTimestamp(),
      // Remove this user from hasUnreadFor for efficient count queries
      'hasUnreadFor': FieldValue.arrayRemove([currentUid]),
    }, SetOptions(merge: true));
  }

  /// Stream of unread message count for the current regular user.
  /// Returns the number of unread messages in their chat.
  /// 
  /// For regular users, they have only one chat (their own), so this
  /// returns the count of unread messages in that chat.
  Stream<int> userUnreadCountStream() {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null) {
      return Stream.value(0);
    }
    
    // If user is admin, return 0 (admins use totalUnreadChatsStream instead)
    if (isAdminUid(currentUid)) {
      return Stream.value(0);
    }
    
    // User's chat ID is their own UID
    return _chatDoc(currentUid)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) {
            return 0;
          }
          final data = snapshot.data() ?? {};
          final count = (data['userUnreadCount'] ?? 0) as int;
          return count;
        })
        .handleError((error, stackTrace) {
          return 0;
        });
  }

  /// Stream of total unread chat count for the current admin.
  /// Returns the number of chats that have unread messages.
  /// 
  /// OPTIMIZED: Uses 'hasUnreadFor' array field with arrayContains query.
  /// This only fetches chats with unread messages (not ALL chats),
  /// and Firestore's arrayContains is highly efficient with proper indexing.
  Stream<int> totalUnreadChatsStream() {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null || !isAdminUid(currentUid)) {
      return Stream.value(0);
    }
    
    // Efficient query: only get chats where this admin has unread messages
    // Instead of fetching ALL chats and filtering client-side
    return db
        .collection('chats')
        .where('hasUnreadFor', arrayContains: currentUid)
        .snapshots()
        .map((snapshot) {
          final count = snapshot.docs.length;
          return count;
        })
        .handleError((error, stackTrace) {
          return 0;
        });
  }

  /// Oturumdaki kişinin [chatId] sohbetindeki okunmamış mesaj sayısı:
  /// yönetici için kendi `adminUnreadCount` değeri, danışan için
  /// `userUnreadCount`. Sohbet bir mesajda (odaklı) açıldığında "En yeniye
  /// git" düğmesindeki sayı buradan okunur.
  Future<int> currentUserUnreadCount(String chatId) async {
    final String? uid = auth.currentUser?.uid;
    if (uid == null) return 0;

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _chatDoc(chatId).get();
    final Map<String, dynamic>? data = snapshot.data();
    if (data == null) return 0;

    if (isAdminUid(uid)) return getUnreadCountFromChatData(data, uid);
    final Object? count = data['userUnreadCount'];
    return count is num ? count.toInt() : 0;
  }

  /// Get unread count for a specific chat and admin from chat data.
  /// Helper method used by UI widgets.
  /// 
  /// Handles Firestore type variations safely:
  /// - Map can be Map<String, dynamic> or Map<Object?, Object?>
  /// - Values can be int or num (Firestore uses num for numbers)
  static int getUnreadCountFromChatData(Map<String, dynamic> chatData, String adminUid) {
    final unreadMapRaw = chatData['adminUnreadCount'];
    if (unreadMapRaw == null || unreadMapRaw is! Map) {
      return 0;
    }
    
    final value = unreadMapRaw[adminUid];
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  /// Send a text message to a specific chat.
  ///
  /// Sohbet özeti (son mesaj, okunmamış sayaçları) ve mesaj tek bir toplu
  /// yazımla gider: mesaj yerel önbelleğe hemen yazılır ve listede anında
  /// görünür ("Gönderiliyor…"), çevrimdışıyken de; bağlantı gelince sunucuya
  /// iletilir. Dönen future sunucu yazımı onaylayınca tamamlanır, reddederse
  /// hata verir. Özet ile mesaj birbirinden kopmaz.
  ///
  /// Metin kutusu sohbet sayfasına aittir (bkz. `ChatPage`): bir sohbette
  /// yazılıp gönderilmeyen metin başka bir sohbetin kutusuna taşınmaz.
  ///
  /// @param chatId The target chat ID (user UID in our model)
  /// @param rawText The text typed by the user (trimmed here)
  /// @param replyTo Yanıtlanan mesajın özeti; yanıt değilse null.
  Future<void> sendTextTo(
    String chatId,
    String rawText, {
    MessageReply? replyTo,
  }) async {
    final text = rawText.trim();
    if (text.isEmpty) return;

    // User sends → notify admins; admin sends → notify user.
    final isAdminMessage = isAdminUid(userId);

    final WriteBatch batch = db.batch();
    batch.set(
      _chatDoc(chatId),
      _chatSummaryData(
        chatId,
        lastMessage: text,
        // Text-only message clears the image preview.
        lastImageUrl: '',
        lastImageThumbUrl: '',
        lastAt: Timestamp.now(),
        incrementUnreadForAdmins: !isAdminMessage,
        incrementUnreadForUser: isAdminMessage,
      ),
      SetOptions(merge: true),
    );
    batch.set(_chatDoc(chatId).collection('messages').doc(), {
      'chatId': chatId,
      'senderId': userId,
      'text': text,
      if (replyTo != null) 'replyTo': replyTo.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.now(),
    });
    await batch.commit();
  }

  /// Fotoğraf mesajının görsel alanları (adres, küçük görsel, ölçü). Öğün
  /// fotoğrafı ve sohbete gönderilen fotoğraf aynı alanları yazar.
  static Map<String, dynamic> imageMessageFields(UploadedImage image) => {
        'imageUrl': image.url,
        if (image.thumbUrl != null) 'thumbUrl': image.thumbUrl,
        if (image.size != null) 'imageWidth': image.size!.width,
        if (image.size != null) 'imageHeight': image.size!.height,
      };

  /// [imageMessageFields] alanlarının adları; fotoğrafı silinen mesajdan
  /// hepsi kaldırılır.
  static const List<String> imageFieldNames = [
    'imageUrl',
    'thumbUrl',
    'imageWidth',
    'imageHeight',
  ];

  /// Sohbete bir fotoğraf gönderir (öğün kaydına girmez).
  ///
  /// Fotoğraf küçültülür, küçük görseli ve ölçüsüyle birlikte yüklenir
  /// ([uploadImageWithThumbnail]); özet ve mesaj tek toplu yazımla gider (bkz.
  /// [sendTextTo]). [observer] ilerlemeyi izler ve iptal edebilir; iptal
  /// edilirse mesaj yazılmaz ve [UploadCancelledException] fırlatılır.
  ///
  /// @param chatId The target chat ID (user UID in our model)
  /// @param image The image file selected by the user
  Future<void> sendImageTo(
    String chatId,
    XFile image, {
    UploadObserver? observer,
  }) async {
    final UploadedImage uploaded = await uploadImageWithThumbnail(
      bytes: await image.readAsBytes(),
      fileName: image.name,
      mimeType: image.mimeType,
      refFor: (fileName) => storage.ref(
        '${_chatStorageFolder(chatId)}/'
        '${DateTime.now().millisecondsSinceEpoch}_${_rand(5)}'
        '${_extensionOf(fileName)}',
      ),
      observer: observer,
    );

    // User sends → notify admins; admin sends → notify user.
    final bool isAdminMessage = isAdminUid(userId);
    final WriteBatch batch = db.batch();
    batch.set(
      _chatDoc(chatId),
      _chatSummaryData(
        chatId,
        lastMessage: _photoSummaryText,
        lastImageUrl: uploaded.url,
        lastImageThumbUrl: uploaded.thumbUrl ?? '',
        lastAt: Timestamp.now(),
        incrementUnreadForAdmins: !isAdminMessage,
        incrementUnreadForUser: isAdminMessage,
      ),
      SetOptions(merge: true),
    );
    batch.set(_chatDoc(chatId).collection('messages').doc(), {
      'chatId': chatId,
      'senderId': userId,
      ...imageMessageFields(uploaded),
      'storagePath': uploaded.ref.fullPath,
      'createdAt': FieldValue.serverTimestamp(),
      'clientCreatedAt': Timestamp.now(),
    });
    final Future<void> commit = batch.commit();
    observer?.onSaving();
    await commit;
  }

  /// Sohbet listesinde fotoğraf mesajının özeti.
  static const String _photoSummaryText = 'Fotoğraf';

  /// Dosya adının uzantısı (noktayla); yoksa `.jpg`.
  static String _extensionOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(dot).toLowerCase() : '.jpg';
  }

  // ===== Reactions =====

  /// Add (or replace) the current user's reaction on a message.
  ///
  /// Reactions are stored as a map on the message document keyed by the
  /// reactor's UID: `reactions.<uid> = emoji`. Only one reaction per user is
  /// kept, so calling this again with a different emoji overwrites the previous
  /// one (WhatsApp-style).
  ///
  /// Uses update() with a dot-notation field path so only the single nested
  /// key is written (the rest of the message document is untouched). update()
  /// — unlike set()+merge — reliably resolves `reactions.<uid>` as a nested
  /// field path, and creates the `reactions` map if it does not exist yet.
  ///
  /// @param chatId    The chat that owns the message (user UID in our model).
  /// @param messageId The message document id to react to.
  /// @param emoji     The reaction emoji (e.g. '👍' or '❤️').
  Future<void> setReaction(String chatId, String messageId, String emoji) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      return;
    }

    try {
      await _chatDoc(chatId).collection('messages').doc(messageId).update({
        'reactions.$uid': emoji,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Remove the current user's reaction from a message (if any).
  ///
  /// Deletes the `reactions.<uid>` nested key via update()+FieldValue.delete().
  /// Safe to call even when the user has no reaction on the message.
  ///
  /// @param chatId    The chat that owns the message (user UID in our model).
  /// @param messageId The message document id to clear the reaction from.
  Future<void> removeReaction(String chatId, String messageId) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      return;
    }

    try {
      await _chatDoc(chatId).collection('messages').doc(messageId).update({
        'reactions.$uid': FieldValue.delete(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Toggle the current user's reaction on a message.
  ///
  /// If the user's existing reaction already equals [emoji], it is removed
  /// (tapping the same reaction again clears it). Otherwise the reaction is set
  /// to [emoji]. [currentEmoji] is the reactor's existing reaction as known by
  /// the caller (from the streamed message), avoiding an extra read.
  Future<void> toggleReaction(
    String chatId,
    String messageId,
    String emoji, {
    String? currentEmoji,
  }) async {
    if (currentEmoji == emoji) {
      await removeReaction(chatId, messageId);
    } else {
      await setReaction(chatId, messageId, emoji);
    }
  }

  /// Permanently delete an entire chat and all of its data.
  ///
  /// This is an ADMIN-ONLY destructive operation that:
  /// 1. Deletes the images the chat itself uploaded (chats/{chatId}/...) from
  ///    Firebase Storage. Storage deletion is best-effort per file: a single
  ///    failure (e.g. the file was already removed) is ignored and does not
  ///    abort the rest of the operation.
  /// 2. Deletes all message documents in the messages subcollection
  ///    (in batches, since a document delete does not cascade to subcollections).
  /// 3. Deletes the chat document itself.
  ///
  /// Öğün fotoğrafları silinmez: dosyaları danışanın öğün kayıtlarına aittir
  /// (`users/{uid}/mealPhotos/...`) ve "Planım", Öğün Fotoğrafları gibi
  /// ekranlar onları göstermeye devam eder. Silinseydi bu kayıtlar kırık
  /// adreslerle kalırdı.
  ///
  /// Throws [StateError] if the caller is not an admin.
  ///
  /// @param chatId The chat to delete (user UID in our one-chat-per-user model)
  Future<void> deleteChat(String chatId) async {
    final currentUid = auth.currentUser?.uid;
    if (currentUid == null || !isAdminUid(currentUid)) {
      throw StateError('Bu işlem için yetkiniz yok.');
    }

    final messagesRef = _chatDoc(chatId).collection('messages');

    // Step 1: Fetch all message documents
    final snapshot = await messagesRef.get();

    // Step 2: Delete the chat's own images from Storage (best-effort,
    // de-duplicated). refFromURL only parses the download URL (no network
    // call), so the storage path decides what belongs to the chat.
    final chatFolder = '${_chatStorageFolder(chatId)}/';
    final imageUrls = <String>{};
    for (final doc in snapshot.docs) {
      // Görselin kendisi ve küçük görseli.
      for (final String field in const ['imageUrl', 'thumbUrl']) {
        final url = (doc.data()[field] as String?)?.trim() ?? '';
        if (url.isEmpty) continue;
        try {
          if (storage.refFromURL(url).fullPath.startsWith(chatFolder)) {
            imageUrls.add(url);
          }
        } catch (e) {
          // Not a Firebase Storage URL: nothing of ours to delete.
        }
      }
    }

    // Deleted in parallel batches: one round trip per image, serialised, made
    // clearing a busy chat take minutes.
    const storageDeleteConcurrency = 16;
    final urlList = imageUrls.toList();
    for (int i = 0; i < urlList.length; i += storageDeleteConcurrency) {
      final chunk = urlList.skip(i).take(storageDeleteConcurrency);
      await Future.wait(chunk.map((url) async {
        try {
          await storage.refFromURL(url).delete();
        } catch (e) {
        }
      }));
    }

    // Step 3: Delete message documents in batches (Firestore limit: 500 ops/batch)
    const batchLimit = 450;
    var batch = db.batch();
    var opCount = 0;
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= batchLimit) {
        await batch.commit();
        batch = db.batch();
        opCount = 0;
      }
    }
    if (opCount > 0) {
      await batch.commit();
    }

    // Step 4: Delete the chat document itself
    await _chatDoc(chatId).delete();

    notifyListeners();
  }

  /// Generate a random alphanumeric string of length n.
  /// Used for creating unique file names.
  String _rand(int n) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
