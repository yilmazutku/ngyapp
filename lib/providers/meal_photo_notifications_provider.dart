import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../models/admin_notification.dart';
import 'chat_manager_new.dart';

class MealPhotoNotificationsProvider extends ChangeNotifier
    with WidgetsBindingObserver {
  MealPhotoNotificationsProvider({
    FirebaseFirestore? db,
    this.maxChatListeners = defaultMaxChatListeners,
  }) : _dbOverride = db;

  static const int defaultMaxChatListeners = 60;

  final FirebaseFirestore? _dbOverride;
  final int maxChatListeners;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  static const String _chatsCollection = 'chats';
  static const String _messagesCollection = 'messages';
  static const String _lastMessageAtField = 'lastMessageAt';
  static const String _adminLastReadAtField = 'adminLastReadAt';
  static const String _createdAtField = 'createdAt';

  String? _uid;

  Object? _owner;
  DateTime? _day;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatsSubscription;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _messageSubscriptions = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _groupSubscription;
  bool _groupReady = false;
  bool _groupFailed = false;
  final Map<String, DateTime?> _lastReadAt = {};
  final Map<String, Map<String, MessageData>> _photosByChat = {};
  Timer? _dayTimer;
  bool _loaded = false;
  bool _hasError = false;

  List<MealPhotoNotification> _items = const [];

  List<MealPhotoNotification> get items => _items;

  int get unreadCount => _items.where((item) => !item.isRead).length;

  bool get isLoaded => _loaded;
  bool get hasError => _hasError;

  @visibleForTesting
  int get messageListenerCount =>
      _messageSubscriptions.length + (_groupSubscription == null ? 0 : 1);

  void start(String uid, {required Object owner}) {
    _owner = owner;
    if (_uid == uid && _chatsSubscription != null) return;
    _stop(notify: false);
    _owner = owner;
    _uid = uid;
    WidgetsBinding.instance.addObserver(this);
    _listenToday();
  }

  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _stop(notify: true);
  }

  void _stop({required bool notify}) {
    final bool wasActive = _uid != null;
    _cancelSubscriptions();
    _dayTimer?.cancel();
    _dayTimer = null;
    if (wasActive) WidgetsBinding.instance.removeObserver(this);
    _uid = null;
    _owner = null;
    _day = null;
    _items = const [];
    _loaded = false;
    _hasError = false;
    if (wasActive && notify) notifyListeners();
  }

  void _cancelSubscriptions() {
    _chatsSubscription?.cancel();
    _chatsSubscription = null;
    _cancelChatListeners();
    _groupSubscription?.cancel();
    _groupSubscription = null;
    _groupReady = false;
    _photosByChat.clear();
    _lastReadAt.clear();
  }

  void _cancelChatListeners() {
    for (final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub
        in _messageSubscriptions.values) {
      sub.cancel();
    }
    _messageSubscriptions.clear();
  }

  void _listenToday() {
    _cancelSubscriptions();
    _groupFailed = false;
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(now.year, now.month, now.day);
    _day = day;
    _items = const [];
    _loaded = false;
    _chatsSubscription = _db
        .collection(_chatsCollection)
        .where(_lastMessageAtField,
            isGreaterThanOrEqualTo: Timestamp.fromDate(day))
        .snapshots()
        .listen(_onChats, onError: (Object error) {
      _hasError = true;
      _loaded = true;
      notifyListeners();
    });

    _dayTimer?.cancel();
    final DateTime nextDay = DateTime(day.year, day.month, day.day + 1);
    _dayTimer = Timer(
        nextDay.difference(now) + const Duration(seconds: 1), _listenToday);
  }

  void _onChats(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final Set<String> chatIds = {};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      chatIds.add(doc.id);
      _lastReadAt[doc.id] = _readAtOf(doc.data());
    }
    for (final String chatId in _lastReadAt.keys.toList()) {
      if (chatIds.contains(chatId)) continue;
      _lastReadAt.remove(chatId);
      _messageSubscriptions.remove(chatId)?.cancel();
      if (!_groupReady) _photosByChat.remove(chatId);
    }
    _syncMessageListeners();
    _loaded = true;
    _hasError = false;
    _rebuild();
  }

  void _syncMessageListeners() {
    if (_groupSubscription != null) return;
    if (!_groupFailed && _lastReadAt.length > maxChatListeners) {
      _groupSubscription = _db
          .collectionGroup(_messagesCollection)
          .where(_createdAtField,
              isGreaterThanOrEqualTo: Timestamp.fromDate(_day!))
          .snapshots()
          .listen(_onTodayMessages, onError: _onTodayMessagesError);
      return;
    }
    for (final String chatId in _lastReadAt.keys) {
      _messageSubscriptions.putIfAbsent(chatId, () => _listenMessages(chatId));
    }
  }

  void _onTodayMessages(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (_groupReady) {
      for (final DocumentChange<Map<String, dynamic>> change
          in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          final String? chatId = _chatIdOf(change.doc.reference);
          if (chatId != null) _photosByChat[chatId]?.remove(change.doc.id);
        } else {
          _applyTodayMessage(change.doc);
        }
      }
    } else {
      _groupReady = true;
      _cancelChatListeners();
      _photosByChat.clear();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        _applyTodayMessage(doc);
      }
    }
    _rebuild();
  }

  void _onTodayMessagesError(Object error) {
    debugPrint('MealPhotoNotificationsProvider: $error');
    _groupFailed = true;
    _groupSubscription?.cancel();
    _groupSubscription = null;
    _groupReady = false;
    _syncMessageListeners();
    _rebuild();
  }

  void _applyTodayMessage(DocumentSnapshot<Map<String, dynamic>> doc) {
    final String? chatId = _chatIdOf(doc.reference);
    if (chatId == null) return;
    final MessageData message = MessageData.fromSnapshot(doc);
    if (_isCustomerMealPhoto(message, chatId)) {
      _photosByChat.putIfAbsent(chatId, () => {})[message.id] = message;
    } else {
      _photosByChat[chatId]?.remove(message.id);
    }
  }

  String? _chatIdOf(DocumentReference<Map<String, dynamic>> message) {
    final DocumentReference<Map<String, dynamic>>? chat = message.parent.parent;
    if (chat == null || chat.parent.path != _chatsCollection) return null;
    return chat.id;
  }

  DateTime? _readAtOf(Map<String, dynamic> chatData) {
    final Object? readAtMap = chatData[_adminLastReadAtField];
    if (readAtMap is! Map) return null;
    final Object? readAt = readAtMap[_uid];
    return readAt is Timestamp ? readAt.toDate() : null;
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _listenMessages(
      String chatId) {
    return _db
        .collection(_chatsCollection)
        .doc(chatId)
        .collection(_messagesCollection)
        .where(_createdAtField,
            isGreaterThanOrEqualTo: Timestamp.fromDate(_day!))
        .snapshots()
        .listen((snapshot) {
      _photosByChat[chatId] = {
        for (final MessageData message
            in snapshot.docs.map(MessageData.fromSnapshot))
          if (_isCustomerMealPhoto(message, chatId)) message.id: message,
      };
      _rebuild();
    }, onError: (Object error) {});
  }

  bool _isCustomerMealPhoto(MessageData message, String chatId) =>
      message.isMealPhoto &&
      !message.photoDeleted &&
      message.senderId == chatId &&
      message.senderId != _uid;

  void _rebuild() {
    final List<MealPhotoNotification> items = [];
    _photosByChat.forEach((chatId, photos) {
      if (!_lastReadAt.containsKey(chatId)) return;
      final DateTime? readAt = _lastReadAt[chatId];
      for (final MessageData photo in photos.values) {
        final DateTime? sentAt = photo.sentAt;
        if (sentAt == null) continue;
        final String? thumbUrl = photo.thumbUrl;
        final bool hasThumb = thumbUrl != null && thumbUrl.isNotEmpty;
        items.add(MealPhotoNotification(
          chatId: chatId,
          messageId: photo.id,
          mealLabel: photo.photoMeal?.displayLabel,
          sentAt: sentAt,
          imageUrl: hasThumb ? thumbUrl : (photo.imageUrl ?? ''),
          imageIsOriginal: !hasThumb,
          isRead: readAt != null && !sentAt.isAfter(readAt),
        ));
      }
    });
    items.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    _items = items;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _uid == null) return;
    final DateTime now = DateTime.now();
    final DateTime? day = _day;
    if (day == null ||
        day.year != now.year ||
        day.month != now.month ||
        day.day != now.day) {
      _listenToday();
    }
  }

  @override
  void dispose() {
    _stop(notify: false);
    super.dispose();
  }
}
