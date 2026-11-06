import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../models/admin_notification.dart';
import '../models/user_model.dart';
import '../utils/date_formatter.dart';
import '../utils/search_text.dart';
import 'admin_notifications_provider.dart';

class BloodTestProvider extends ChangeNotifier with WidgetsBindingObserver {
  BloodTestProvider({
    required AdminNotificationsProvider notifications,
    FirebaseFirestore? db,
  })  : _notifications = notifications,
        _dbOverride = db;

  final AdminNotificationsProvider _notifications;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  static const Duration uploadGracePeriod = Duration(days: 7);

  static const int dailyScanHour = 9;

  static const Duration _startupDelay = Duration(seconds: 20);

  static const Duration _retryDelay = Duration(minutes: 30);

  static const String _usersCollection = 'users';
  static const String _roleField = 'role';
  static const String _customerRole = 'customer';
  static const String _createDateField = 'createDate';
  static const String _legacyCreatedAtField = 'createdAt';
  static const String _removalRequestedField = 'isUserRequestedRemoval';

  static const String _stateCollection = 'adminState';
  static const String _stateDocId = 'bloodTests';
  static const String _presenceInitializedAtField = 'presenceInitializedAt';
  static const String _lastScanDayField = 'lastScanDay';
  static const String _lastScanAtField = 'lastScanAt';
  static const String _lastScanByField = 'lastScanBy';

  static const int _batchLimit = 450;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(_usersCollection);

  DocumentReference<Map<String, dynamic>> get _stateDoc =>
      _db.collection(_stateCollection).doc(_stateDocId);

  final Map<String, bool> _savedPresence = {};

  bool? savedPresence(String userId) => _savedPresence[userId];

  Future<void> setBloodTestPresent({
    required String userId,
    required bool present,
  }) async {
    await _users.doc(userId).update({UserModel.bloodTestPresentField: present});
    _savedPresence[userId] = present;
    notifyListeners();
  }

  static bool isMissingBloodTest(
    UserModel user, {
    required DateTime? createdAt,
    required bool removalRequested,
    required DateTime now,
  }) {
    if (user.role != _customerRole || user.hasBloodTest) return false;
    if (removalRequested || user.isExcludedFromActiveCustomers) return false;
    if (createdAt == null) return true;
    return !createdAt.add(uploadGracePeriod).isAfter(now);
  }

  static DateTime? _createdAtOf(Map<String, dynamic> data) {
    final Object? raw = data[_createDateField] ?? data[_legacyCreatedAtField];
    return raw is Timestamp ? raw.toDate() : null;
  }

  String? _uid;

  Object? _owner;
  Timer? _timer;
  bool _scanning = false;
  bool _inForeground = true;

  String? _scannedDay;

  void startDailyScan(String uid, {required Object owner}) {
    _owner = owner;
    if (_uid == uid) return;
    _stopDailyScan();
    _owner = owner;
    _uid = uid;
    _inForeground = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer(_startupDelay, _scanIfDue);
  }

  void releaseDailyScan(Object owner) {
    if (identical(_owner, owner)) _stopDailyScan();
  }

  void _stopDailyScan() {
    if (_uid != null) WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _uid = null;
    _owner = null;
    _scannedDay = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (_inForeground) _scanIfDue();
  }

  @override
  void dispose() {
    _stopDailyScan();
    super.dispose();
  }

  Future<void> _scanIfDue() async {
    final String? uid = _uid;
    if (uid == null || _scanning) return;
    final DateTime now = DateTime.now();
    final String today = DateFormatter.formatIsoDate(now);
    if (_scannedDay == today || now.hour < dailyScanHour || !_inForeground) {
      _armTimer();
      return;
    }

    _scanning = true;
    bool failed = false;
    try {
      await runDailyScan(uid: uid, now: now);
      if (_uid == uid) _scannedDay = today;
    } catch (e) {
      failed = true;
    } finally {
      _scanning = false;
      _armTimer(retry: failed);
    }
  }

  Future<int?> runDailyScan({
    required String uid,
    required DateTime now,
    bool force = false,
  }) async {
    final String today = DateFormatter.formatIsoDate(now);
    final DocumentSnapshot<Map<String, dynamic>> stateSnapshot =
        await _stateDoc.get(const GetOptions(source: Source.server));
    final Map<String, dynamic> state = stateSnapshot.data() ?? const {};
    if (!force && state[_lastScanDayField] == today) return null;

    final Object? initializedAt = state[_presenceInitializedAtField];
    if (initializedAt is! Timestamp) {
      await _initializePresence();
      await _stateDoc.set({
        _presenceInitializedAtField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      final Object? lastScanAt = state[_lastScanAtField];
      final DateTime since =
          (lastScanAt is Timestamp ? lastScanAt : initializedAt)
              .toDate()
              .subtract(const Duration(days: 1));
      await _initializePresence(createdSince: since);
    }

    final List<NotificationCustomer> missing = await _fetchMissing(now);
    if (missing.isNotEmpty) {
      await _notifications.saveMissingBloodTestList(
        day: today,
        customers: missing,
        at: now,
      );
    }
    await _notifications.supersedeMissingBloodTestLists(
      exceptId: missing.isEmpty
          ? null
          : AdminNotification.missingBloodTestsId(today),
    );
    await _stateDoc.set({
      _lastScanDayField: today,
      _lastScanAtField: FieldValue.serverTimestamp(),
      _lastScanByField: uid,
    }, SetOptions(merge: true));
    if (_uid == uid) _scannedDay = today;
    return missing.length;
  }

  void _armTimer({bool retry = false}) {
    _timer?.cancel();
    _timer = null;
    if (_uid == null) return;
    final DateTime now = DateTime.now();
    final DateTime todayRun =
        DateTime(now.year, now.month, now.day, dailyScanHour);
    final DateTime next;
    if (retry) {
      next = now.add(_retryDelay);
    } else if (_scannedDay == DateFormatter.formatIsoDate(now) ||
        !now.isBefore(todayRun)) {
      next = DateTime(now.year, now.month, now.day + 1, dailyScanHour);
    } else {
      next = todayRun;
    }
    _timer = Timer(next.difference(now), _scanIfDue);
  }

  Future<void> _initializePresence({DateTime? createdSince}) async {
    final Query<Map<String, dynamic>> query = createdSince == null
        ? _users.where(_roleField, isEqualTo: _customerRole)
        : _users.where(_createDateField,
            isGreaterThanOrEqualTo: Timestamp.fromDate(createdSince));
    final QuerySnapshot<Map<String, dynamic>> snapshot = await query.get();
    final List<DocumentReference<Map<String, dynamic>>> refs = [
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        if (doc.data()[_roleField] == _customerRole &&
            !doc.data().containsKey(UserModel.bloodTestPresentField))
          doc.reference,
    ];
    for (int start = 0; start < refs.length; start += _batchLimit) {
      final WriteBatch batch = _db.batch();
      for (final DocumentReference<Map<String, dynamic>> ref
          in refs.skip(start).take(_batchLimit)) {
        batch.update(ref, {UserModel.bloodTestPresentField: false});
      }
      await batch.commit();
    }
  }

  Future<List<NotificationCustomer>> _fetchMissing(DateTime now) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _users
        .where(UserModel.bloodTestPresentField, isEqualTo: false)
        .get(const GetOptions(source: Source.server));
    final List<NotificationCustomer> missing = [];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final UserModel user;
      try {
        user = UserModel.fromDocument(doc);
      } catch (e) {
        continue;
      }
      final Map<String, dynamic> data = doc.data();
      if (!isMissingBloodTest(
        user,
        createdAt: _createdAtOf(data),
        removalRequested: data[_removalRequestedField] == true,
        now: now,
      )) {
        continue;
      }
      missing.add(NotificationCustomer(
        userId: user.userId,
        name: user.fullName.isEmpty ? user.email : user.fullName,
      ));
    }
    missing.sort((a, b) => compareSearchText(a.name, b.name));
    return missing;
  }
}
