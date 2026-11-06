import 'dart:convert';
import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_notification.dart';
import 'fcm_service.dart';
import 'notification_service.dart';

class AdminNotificationDelivery {
  AdminNotificationDelivery({
    AdminNotificationScheduler? local,
    AdminNotificationBanner? banner,
    bool? osShowsInForeground,
  })  : _local = local ?? const _DeviceNotificationScheduler(),
        _banner = banner ?? _showFcmBanner,
        _osShowsInForeground = osShowsInForeground ?? Platform.isAndroid;

  final AdminNotificationScheduler _local;
  final AdminNotificationBanner _banner;

  final bool _osShowsInForeground;

  static const Duration recentWindow = Duration(hours: 24);

  static const Duration _keepRecordsFor = Duration(days: 30);

  static const String _scheduledKeyPrefix = 'adminNotifications.scheduled.';
  static const String _announcedKeyPrefix = 'adminNotifications.announced.';

  static const String _manyTitleSuffix = ' yeni sistem bildirimi';

  String? _uid;

  Map<String, int> _scheduled = {};

  Map<String, int> _announced = {};

  Future<void>? _loading;

  Future<void> attach(String uid) {
    if (_uid == uid && _loading != null) return _loading!;
    _uid = uid;
    _scheduled = {};
    _announced = {};
    return _loading = _load(uid);
  }

  void detach() {
    _uid = null;
    _loading = null;
    _scheduled = {};
    _announced = {};
  }

  Future<void> _load(String uid) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (_uid != uid) return;
      _scheduled = _decode(prefs.getString('$_scheduledKeyPrefix$uid'));
      _announced = _decode(prefs.getString('$_announcedKeyPrefix$uid'));
    } catch (e) {
    }
  }

  static Map<String, int> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final MapEntry<dynamic, dynamic> entry in decoded.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      };
    } catch (e) {
      return {};
    }
  }

  Future<void> _save() async {
    final String? uid = _uid;
    if (uid == null) return;
    final int oldest =
        DateTime.now().subtract(_keepRecordsFor).millisecondsSinceEpoch;
    _scheduled.removeWhere((_, fireAt) => fireAt < oldest);
    _announced.removeWhere((_, fireAt) => fireAt < oldest);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_scheduledKeyPrefix$uid', jsonEncode(_scheduled));
      await prefs.setString('$_announcedKeyPrefix$uid', jsonEncode(_announced));
    } catch (e) {
    }
  }

  Future<void> syncUpcoming(List<AdminNotification> upcoming) async {
    if (!_local.isSupported) return;
    final String? uid = _uid;
    if (uid == null) return;
    await _loading;
    if (_uid != uid) return;

    final Set<String> wanted = {for (final n in upcoming) n.id};
    final Set<String> pending = await _local.pendingDocIds();
    for (final String docId in pending.difference(wanted)) {
      await _local.cancel(docId);
      _scheduled.remove(docId);
    }

    bool changed = false;
    for (final AdminNotification notification in upcoming) {
      final int fireAt = notification.fireAt.millisecondsSinceEpoch;
      if (_scheduled[notification.id] == fireAt &&
          pending.contains(notification.id)) {
        continue;
      }
      final bool scheduled = await _local.schedule(
        docId: notification.id,
        title: notification.title,
        body: notification.body,
        fireAt: notification.fireAt,
      );
      if (_uid != uid) return;
      if (scheduled) {
        _scheduled[notification.id] = fireAt;
        changed = true;
      }
    }
    if (changed) await _save();
  }

  Future<void> announce({
    required List<AdminNotification> due,
    required DateTime now,
    required bool inForeground,
    required Set<String> becameDueInForeground,
  }) async {
    final String? uid = _uid;
    if (uid == null) return;
    await _loading;
    if (_uid != uid) return;

    final List<AdminNotification> toShow = [];
    bool changed = false;
    for (final AdminNotification notification in due) {
      if (_announced.containsKey(notification.id)) continue;
      final int fireAt = notification.fireAt.millisecondsSinceEpoch;

      final bool stale = !notification.isUnreadFor(uid) ||
          now.difference(notification.fireAt) > recentWindow;
      if (stale) {
        _announced[notification.id] = fireAt;
        changed = true;
        continue;
      }

      if (_scheduled.containsKey(notification.id)) {
        if (becameDueInForeground.contains(notification.id) &&
            !_osShowsInForeground) {
          toShow.add(notification);
        }
        _announced[notification.id] = fireAt;
        changed = true;
        continue;
      }

      if (inForeground) {
        toShow.add(notification);
        _announced[notification.id] = fireAt;
        changed = true;
      }
    }
    if (changed) await _save();
    if (toShow.isNotEmpty && _uid == uid) _showBanner(toShow);
  }

  void _showBanner(List<AdminNotification> notifications) {
    if (notifications.length == 1) {
      final AdminNotification only = notifications.single;
      _banner(
        title: only.title,
        body: only.body,
        data: FcmService.adminNotificationTapData(only.id),
      );
      return;
    }
    _banner(
      title: '${notifications.length}$_manyTitleSuffix',
      body: notifications.map((n) => n.title).join(' · '),
      data: FcmService.adminNotificationTapData(''),
    );
  }
}

typedef AdminNotificationBanner = void Function({
  required String title,
  required String body,
  required Map<String, dynamic> data,
});

void _showFcmBanner({
  required String title,
  required String body,
  required Map<String, dynamic> data,
}) =>
    FcmService().showInAppBanner(title: title, body: body, data: data);

abstract class AdminNotificationScheduler {
  bool get isSupported;

  Future<bool> schedule({
    required String docId,
    required String title,
    required String body,
    required DateTime fireAt,
  });

  Future<void> cancel(String docId);

  Future<Set<String>> pendingDocIds();
}

class _DeviceNotificationScheduler implements AdminNotificationScheduler {
  const _DeviceNotificationScheduler();

  @override
  bool get isSupported => NotificationService().isSupported;

  @override
  Future<bool> schedule({
    required String docId,
    required String title,
    required String body,
    required DateTime fireAt,
  }) =>
      NotificationService().scheduleAdminNotification(
        docId: docId,
        title: title,
        body: body,
        fireAt: fireAt,
      );

  @override
  Future<void> cancel(String docId) =>
      NotificationService().cancelAdminNotification(docId);

  @override
  Future<Set<String>> pendingDocIds() =>
      NotificationService().pendingAdminNotificationDocIds();
}
