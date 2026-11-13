import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'chat_manager_new.dart';

class UserPhotoGalleryProvider extends ChangeNotifier {
  UserPhotoGalleryProvider({required ChatManager chat, required this.userId})
      : _chat = chat;

  static const int olderPageSize = 120;

  final ChatManager _chat;
  final String userId;

  StreamSubscription<List<MessageData>>? _subscription;

  List<MessageData> _live = const [];
  List<MessageData> _livePhotos = const [];
  List<MessageData> _olderPhotos = const [];
  List<MessageData> _photos = const [];
  int _otherImagesInLive = 0;
  int _otherImagesInOlder = 0;
  Timestamp? _olderCursor;

  bool _loaded = false;
  bool _failed = false;
  bool _liveAnchored = false;
  bool _loadingOlder = false;
  bool _olderLoadFailed = false;
  bool _olderOffline = false;
  bool _reachedStart = false;
  bool _disposed = false;

  int? _imageCount;
  bool _countFailed = false;
  bool _counting = false;
  bool _countStale = false;

  List<MessageData> get photos => _photos;

  bool get isLoading => !_loaded && !_failed;

  bool get hasFailed => _failed;

  bool get isLoadingOlder => _loadingOlder;

  bool get olderLoadFailed => _olderLoadFailed;

  bool get olderOffline => _olderOffline;

  bool get atStart => _liveAnchored
      ? _reachedStart
      : _loaded && _live.length < ChatManager.messagesPageSize;

  int? get totalCount {
    if (atStart) return _photos.length;
    final int? images = _imageCount;
    if (images == null) return null;
    return math.max(
      _photos.length,
      images - _otherImagesInLive - _otherImagesInOlder,
    );
  }

  bool get totalCountUnavailable => _countFailed && totalCount == null;

  void start() {
    if (_subscription != null) return;
    _listen(_chat.messagesStreamFor(userId));
  }

  Future<void> loadOlder() async {
    if (_disposed ||
        !_loaded ||
        _loadingOlder ||
        _olderLoadFailed ||
        _live.isEmpty ||
        atStart) {
      return;
    }

    Timestamp? cursor = _olderCursor ?? _timeOf(_live.last);
    if (cursor == null) return;

    _loadingOlder = true;
    if (!_liveAnchored) {
      _liveAnchored = true;
      _listen(_chat.messagesSinceStream(userId, cursor));
    }
    _notify();

    try {
      while (cursor != null) {
        final ({List<MessageData> messages, bool fromCache}) page =
            await _chat.fetchOlderPage(userId, cursor, limit: olderPageSize);
        if (_disposed) return;

        final List<MessageData> found = page.messages.where(_isPhoto).toList();
        _olderPhotos = [..._olderPhotos, ...found];
        _otherImagesInOlder += page.messages.where(_isOtherImage).length;
        if (page.messages.isNotEmpty) {
          cursor = _timeOf(page.messages.last);
          _olderCursor = cursor ?? _olderCursor;
        }

        final bool shortPage = page.messages.length < olderPageSize;
        if (page.fromCache) {
          _olderOffline = shortPage;
          _olderLoadFailed = shortPage;
        } else {
          _reachedStart = shortPage;
        }
        if (found.isNotEmpty || shortPage) break;
      }
    } catch (e) {
      _olderLoadFailed = true;
    } finally {
      _loadingOlder = false;
      _mergePhotos();
      _notify();
    }
  }

  void retryOlder() {
    _olderLoadFailed = false;
    _olderOffline = false;
    unawaited(loadOlder());
  }

  Future<void> refreshMessage(String messageId) async {
    if (_olderPhotos.any((MessageData photo) => photo.id == messageId)) {
      MessageData? fresh;
      try {
        fresh = await _chat.fetchMessage(userId, messageId);
      } catch (e) {
        return;
      }
      if (_disposed) return;

      final int index = _olderPhotos
          .indexWhere((MessageData photo) => photo.id == messageId);
      if (index >= 0) {
        final List<MessageData> updated = [..._olderPhotos];
        if (fresh != null && _isPhoto(fresh)) {
          updated[index] = fresh;
        } else {
          updated.removeAt(index);
        }
        _olderPhotos = updated;
        _mergePhotos();
        _notify();
      }
    }
    unawaited(_refreshCount());
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  void _listen(Stream<List<MessageData>> stream) {
    _subscription?.cancel();
    _subscription = stream.listen(
      _onLive,
      onError: (Object e) {
        _failed = true;
        _notify();
      },
    );
  }

  void _onLive(List<MessageData> messages) {
    final List<String> before = _idsOf(_livePhotos);
    final bool first = !_loaded;

    _live = messages;
    _livePhotos = messages.where(_isPhoto).toList();
    _otherImagesInLive = messages.where(_isOtherImage).length;
    _loaded = true;
    _failed = false;
    _mergePhotos();

    if (first || !listEquals(before, _idsOf(_livePhotos))) {
      unawaited(_refreshCount());
    }
    _notify();
    if (_photos.isEmpty) unawaited(loadOlder());
  }

  Future<void> _refreshCount() async {
    if (_counting) {
      _countStale = true;
      return;
    }
    _counting = true;
    try {
      do {
        _countStale = false;
        final int count = await _chat.countImageMessages(userId);
        if (_disposed) return;
        _imageCount = count;
        _countFailed = false;
        _notify();
      } while (_countStale);
    } catch (e) {
      _countFailed = true;
      _notify();
    } finally {
      _counting = false;
    }
  }

  void _mergePhotos() {
    final Set<String> liveIds = _idsOf(_livePhotos).toSet();
    _photos = [
      ..._livePhotos,
      ..._olderPhotos.where((MessageData photo) => !liveIds.contains(photo.id)),
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _isPhoto(MessageData message) =>
      message.senderId == userId && _hasImage(message);

  bool _isOtherImage(MessageData message) =>
      message.senderId != userId && _hasImage(message);

  static bool _hasImage(MessageData message) =>
      (message.imageUrl ?? '').isNotEmpty;

  static List<String> _idsOf(List<MessageData> messages) =>
      [for (final MessageData message in messages) message.id];

  static Timestamp? _timeOf(MessageData message) =>
      message.createdAt ?? message.clientCreatedAt;
}
