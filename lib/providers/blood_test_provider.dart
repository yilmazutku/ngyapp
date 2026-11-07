import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

import '../models/admin_notification.dart';
import '../models/blood_test_scan.dart';
import '../models/blood_test_status.dart';
import '../models/user_model.dart';
import '../utils/date_formatter.dart';
import '../utils/search_text.dart';
import 'admin_notifications_provider.dart';
import 'test_provider.dart';

class BloodTestProvider extends ChangeNotifier with WidgetsBindingObserver {
  BloodTestProvider({
    required AdminNotificationsProvider notifications,
    FirebaseFirestore? db,
  })  : _notifications = notifications,
        _dbOverride = db;

  final AdminNotificationsProvider _notifications;
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  static const Duration uploadGracePeriod = BloodTestStatus.firstTestGrace;

  static const int dailyScanHour = BloodTestStatus.dailyScanHour;

  static const int _checkConcurrency = 16;

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

  static final DateTime _listedSinceAlways = DateTime.utc(1970);

  static DateTime? missingBloodTestListedFrom(
    UserModel user, {
    required DateTime? createdAt,
    required bool removalRequested,
  }) {
    if (user.role != _customerRole || user.hasBloodTest) return null;
    if (removalRequested || user.isExcludedFromActiveCustomers) return null;
    return BloodTestStatus.firstTestDeadline(createdAt) ?? _listedSinceAlways;
  }

  static bool isMissingBloodTest(
    UserModel user, {
    required DateTime? createdAt,
    required bool removalRequested,
    required DateTime now,
  }) {
    final DateTime? listedFrom = missingBloodTestListedFrom(
      user,
      createdAt: createdAt,
      removalRequested: removalRequested,
    );
    return listedFrom != null && !listedFrom.isAfter(now);
  }

  static NotificationCustomer _notificationCustomerOf(UserModel user) =>
      NotificationCustomer(
        userId: user.userId,
        name: user.fullName.isEmpty ? user.email : user.fullName,
      );

  static DateTime? _createdAtOf(Map<String, dynamic> data) {
    final Object? raw = data[_createDateField] ?? data[_legacyCreatedAtField];
    return raw is Timestamp ? raw.toDate() : null;
  }

  static List<_CustomerRecord> _recordsOf(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final List<_CustomerRecord> records = [];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final UserModel user;
      try {
        user = UserModel.fromDocument(doc);
      } catch (e) {
        continue;
      }
      final Map<String, dynamic> data = doc.data();
      records.add(_CustomerRecord(
        user: user,
        createdAt: _createdAtOf(data),
        removalRequested: data[_removalRequestedField] == true,
        presenceRecorded: data.containsKey(UserModel.bloodTestPresentField),
      ));
    }
    return records;
  }

  String? _uid;

  Object? _owner;
  Timer? _timer;
  bool _scanning = false;

  String? _scannedDay;

  void startDailyScan(String uid, {required Object owner}) {
    _owner = owner;
    if (_uid == uid) return;
    _stopDailyScan();
    _owner = owner;
    _uid = uid;
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
    _lastReport = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scanIfDue();
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
    if (_scannedDay == today || now.hour < dailyScanHour) {
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
    final List<NotificationCustomer> missing = [
      for (final _CustomerRecord record in _recordsOf(snapshot))
        if (isMissingBloodTest(
          record.user,
          createdAt: record.createdAt,
          removalRequested: record.removalRequested,
          now: now,
        ))
          _notificationCustomerOf(record.user),
    ];
    missing.sort((a, b) => compareSearchText(a.name, b.name));
    return missing;
  }

  Future<BloodTestScanPreview> previewScan({required DateTime at}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _users
        .where(_roleField, isEqualTo: _customerRole)
        .get(const GetOptions(source: Source.server));
    final List<NotificationCustomer> missing = [];
    final List<BloodTestScanWaiting> waiting = [];
    int unrecordedCount = 0;
    for (final _CustomerRecord record in _recordsOf(snapshot)) {
      final UserModel user = record.user;
      if (!record.presenceRecorded) unrecordedCount++;
      final DateTime? listedFrom = missingBloodTestListedFrom(
        user,
        createdAt: record.createdAt,
        removalRequested: record.removalRequested,
      );
      if (listedFrom == null) continue;
      if (listedFrom.isAfter(at)) {
        waiting.add(BloodTestScanWaiting(
          customer: _notificationCustomerOf(user),
          listedFrom: listedFrom,
        ));
      } else {
        missing.add(_notificationCustomerOf(user));
      }
    }
    missing.sort((a, b) => compareSearchText(a.name, b.name));
    waiting.sort((a, b) {
      final int byDate = a.listedFrom.compareTo(b.listedFrom);
      return byDate != 0
          ? byDate
          : compareSearchText(a.customer.name, b.customer.name);
    });
    return BloodTestScanPreview(
      at: at,
      missing: missing,
      waiting: waiting,
      unrecordedCount: unrecordedCount,
    );
  }

  Future<BloodTestScanState> fetchScanState() async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _stateDoc.get(const GetOptions(source: Source.server));
    final Map<String, dynamic> data = snapshot.data() ?? const {};
    final Object? lastScanDay = data[_lastScanDayField];
    final Object? lastScanAt = data[_lastScanAtField];
    final Object? lastScanBy = data[_lastScanByField];
    final Object? initializedAt = data[_presenceInitializedAtField];
    return BloodTestScanState(
      lastScanDay: lastScanDay is String ? lastScanDay : null,
      lastScanAt: lastScanAt is Timestamp ? lastScanAt.toDate() : null,
      lastScanBy: lastScanBy is String ? lastScanBy : null,
      presenceInitializedAt:
          initializedAt is Timestamp ? initializedAt.toDate() : null,
    );
  }

  BloodTestReport? _lastReport;

  BloodTestReport? get lastReport => _lastReport;

  Future<BloodTestReport> checkAllCustomers({
    required DateTime now,
    void Function(int done, int total)? onProgress,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _users
        .where(_roleField, isEqualTo: _customerRole)
        .get(const GetOptions(source: Source.server));
    final List<_CustomerRecord> customers = [
      for (final _CustomerRecord record in _recordsOf(snapshot))
        if (!record.removalRequested &&
            !record.user.isExcludedFromActiveCustomers)
          record,
    ];

    final List<BloodTestStatus> statuses = [];
    onProgress?.call(0, customers.length);
    for (int start = 0;
        start < customers.length;
        start += _checkConcurrency) {
      statuses.addAll(await Future.wait([
        for (final _CustomerRecord customer
            in customers.skip(start).take(_checkConcurrency))
          _statusOf(customer.user, customer.createdAt, now),
      ]));
      onProgress?.call(statuses.length, customers.length);
    }
    statuses.sort(BloodTestStatus.compare);
    final BloodTestReport report =
        BloodTestReport(checkedAt: now, statuses: statuses);
    _lastReport = report;
    notifyListeners();
    return report;
  }

  Future<BloodTestStatus> _statusOf(
    UserModel user,
    DateTime? createdAt,
    DateTime now,
  ) async {
    final QuerySnapshot<Map<String, dynamic>> latest = await _users
        .doc(user.userId)
        .collection(TestProvider.testsCollection)
        .orderBy(TestProvider.bloodTestDateField, descending: true)
        .limit(1)
        .get();
    final Object? raw = latest.docs.isEmpty
        ? null
        : latest.docs.first.data()[TestProvider.bloodTestDateField];
    return BloodTestStatus.evaluate(
      customer: _notificationCustomerOf(user),
      createdAt: createdAt,
      hasBloodTest: user.hasBloodTest,
      lastTestDate: raw is Timestamp ? raw.toDate() : null,
      now: now,
    );
  }
}

class _CustomerRecord {
  const _CustomerRecord({
    required this.user,
    required this.createdAt,
    required this.removalRequested,
    required this.presenceRecorded,
  });

  final UserModel user;
  final DateTime? createdAt;
  final bool removalRequested;
  final bool presenceRecorded;
}
