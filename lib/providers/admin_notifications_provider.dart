import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../models/admin_notification.dart';
import '../services/admin_notification_delivery.dart';
import '../utils/date_formatter.dart';

class AdminNotificationsProvider extends ChangeNotifier
    with WidgetsBindingObserver {
  AdminNotificationsProvider({
    FirebaseFirestore? db,
    AdminNotificationDelivery? delivery,
    String? Function()? currentUid,
  })  : _dbOverride = db,
        _deliveryOverride = delivery,
        _currentUidOverride = currentUid;

  static const String collectionName = 'adminNotifications';

  static const int listLimit = 150;

  static const int upcomingLimit = 100;

  static const int olderPageSize = 100;

  final FirebaseFirestore? _dbOverride;
  final AdminNotificationDelivery? _deliveryOverride;
  final String? Function()? _currentUidOverride;

  String? get _currentUid => _currentUidOverride != null
      ? _currentUidOverride()
      : FirebaseAuth.instance.currentUser?.uid;
  late final AdminNotificationDelivery _delivery =
      _deliveryOverride ?? AdminNotificationDelivery();

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection(collectionName);

  String? _uid;

  Object? _owner;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _dueSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _upcomingSubscription;

  DateTime _windowStart = DateTime.now();
  List<AdminNotification> _dueWindow = const [];
  List<AdminNotification> _upcomingWindow = const [];
  bool _dueWindowLoaded = false;
  bool _upcomingWindowLoaded = false;
  bool _dueWindowFailed = false;
  bool _upcomingWindowFailed = false;
  bool _upcomingWindowFull = false;
  int _windowGeneration = 0;

  List<AdminNotification> _all = const [];

  List<AdminNotification> _due = const [];

  List<AdminNotification> _older = const [];

  DocumentSnapshot<Map<String, dynamic>>? _oldestLoaded;
  bool _hasMoreOlder = false;
  bool _loadingOlder = false;

  bool _loaded = false;
  bool _hasError = false;
  bool _inForeground = true;
  bool _inBackground = false;
  DateTime _lastDueCheck = DateTime.now();
  Timer? _dueTimer;
  Timer? _dayTimer;

  List<AdminNotification> get notifications =>
      _older.isEmpty ? _due : [..._due, ..._older];

  List<AdminNotification> get upcoming {
    final DateTime now = DateTime.now();
    return [
      for (final AdminNotification n in _all)
        if (!n.isDueAt(now)) n,
    ]..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  }

  bool get upcomingWindowIsFull => _upcomingWindowFull;

  bool get isLoaded => _loaded;
  bool get hasError => _hasError;

  bool get canLoadOlder => _hasMoreOlder;
  bool get isLoadingOlder => _loadingOlder;

  int get unreadCount {
    final String? uid = _uid;
    if (uid == null) return 0;
    return _due.where((n) => n.isUnreadFor(uid)).length;
  }

  bool isRead(AdminNotification notification) {
    final String? uid = _uid;
    return uid != null && !notification.isUnreadFor(uid);
  }

  void start(String uid, {required Object owner}) {
    _owner = owner;
    if (_uid == uid && _dueSubscription != null) return;
    _stop(notify: false, signedOut: _uid != null && _uid != uid);
    _owner = owner;
    _uid = uid;
    _inForeground = true;
    _inBackground = false;
    _lastDueCheck = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    _delivery.attach(uid);
    _subscribe();
  }

  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _stop(notify: true, signedOut: _currentUid != _uid);
  }

  void _subscribe() {
    _dueSubscription?.cancel();
    _upcomingSubscription?.cancel();
    final DateTime windowStart = DateTime.now();
    final Timestamp bound = Timestamp.fromDate(windowStart);
    _windowStart = windowStart;
    _windowGeneration++;
    _dueWindowLoaded = false;
    _upcomingWindowLoaded = false;
    _dueWindowFailed = false;
    _upcomingWindowFailed = false;
    _older = const [];
    _oldestLoaded = null;
    _hasMoreOlder = false;
    _loadingOlder = false;
    _dueSubscription = _collection
        .where(AdminNotification.fireAtField, isLessThanOrEqualTo: bound)
        .orderBy(AdminNotification.fireAtField, descending: true)
        .limit(listLimit)
        .snapshots()
        .listen(_onDueSnapshot, onError: (Object error) {
      _dueWindowLoaded = true;
      _dueWindowFailed = true;
      _onWindowsChanged();
    });
    _upcomingSubscription = _collection
        .where(AdminNotification.fireAtField, isGreaterThan: bound)
        .orderBy(AdminNotification.fireAtField)
        .limit(upcomingLimit)
        .snapshots()
        .listen(_onUpcomingSnapshot, onError: (Object error) {
      _upcomingWindowLoaded = true;
      _upcomingWindowFailed = true;
      _onWindowsChanged();
    });
    _armDayTimer(windowStart);
  }

  void _armDayTimer(DateTime now) {
    _dayTimer?.cancel();
    final DateTime nextDay = DateTime(now.year, now.month, now.day + 1);
    _dayTimer = Timer(
      nextDay.difference(now) + const Duration(seconds: 1),
      () {
        if (_uid != null) _subscribe();
      },
    );
  }

  void _stop({required bool notify, bool signedOut = false}) {
    final bool wasActive = _uid != null;
    _dueSubscription?.cancel();
    _dueSubscription = null;
    _upcomingSubscription?.cancel();
    _upcomingSubscription = null;
    _dueTimer?.cancel();
    _dueTimer = null;
    _dayTimer?.cancel();
    _dayTimer = null;
    if (wasActive) WidgetsBinding.instance.removeObserver(this);
    _delivery.detach(clearDevice: signedOut);
    _uid = null;
    _owner = null;
    _dueWindow = const [];
    _upcomingWindow = const [];
    _dueWindowLoaded = false;
    _upcomingWindowLoaded = false;
    _dueWindowFailed = false;
    _upcomingWindowFailed = false;
    _upcomingWindowFull = false;
    _windowGeneration++;
    _all = const [];
    _due = const [];
    _older = const [];
    _oldestLoaded = null;
    _hasMoreOlder = false;
    _loadingOlder = false;
    _loaded = false;
    _hasError = false;
    if (wasActive && notify) notifyListeners();
  }

  List<AdminNotification> _visible(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final String? uid = _uid;
    if (uid == null) return const [];
    return snapshot.docs
        .map(AdminNotification.fromDocument)
        .whereType<AdminNotification>()
        .where((n) => n.isVisibleTo(uid))
        .toList();
  }

  void _onDueSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _dueWindow = _visible(snapshot);
    _dueWindowLoaded = true;
    _dueWindowFailed = false;
    if (_older.isEmpty) {
      _oldestLoaded = snapshot.docs.isEmpty ? null : snapshot.docs.last;
      _hasMoreOlder = snapshot.docs.length >= listLimit;
    }
    _onWindowsChanged();
  }

  void _onUpcomingSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _upcomingWindow = _visible(snapshot);
    _upcomingWindowLoaded = true;
    _upcomingWindowFailed = false;
    _upcomingWindowFull = snapshot.docs.length >= upcomingLimit;
    _onWindowsChanged();
  }

  void _onWindowsChanged() {
    final bool failed = _dueWindowFailed || _upcomingWindowFailed;
    if (_uid == null || !_dueWindowLoaded || !_upcomingWindowLoaded) {
      if (failed) _hasError = true;
      return;
    }
    final Map<String, AdminNotification> byId = {
      for (final AdminNotification n in _dueWindow) n.id: n,
      for (final AdminNotification n in _upcomingWindow) n.id: n,
    };
    _all = byId.values.toList()
      ..sort((a, b) => b.fireAt.compareTo(a.fireAt));
    if (_older.isNotEmpty) {
      _older = _older.where((n) => !byId.containsKey(n.id)).toList();
    }
    _loaded = true;
    _hasError = failed;
    if (!failed) _syncDevice();
    _refreshDue();
  }

  void _syncDevice() {
    final String? uid = _uid;
    if (uid == null) return;
    final DateTime now = DateTime.now();
    _delivery.syncUpcoming(
      upcoming,
      inFlight: {
        for (final AdminNotification n in _all)
          if (n.isDueAt(now) && n.isUnreadFor(uid)) n.id,
      },
    );
  }

  void _refreshDue({bool resumed = false}) {
    if (_uid == null) return;
    final DateTime now = DateTime.now();
    _due = _all.where((n) => n.isDueAt(now)).toList();
    final Set<String> becameDueInForeground = _inForeground && !resumed
        ? {
            for (final AdminNotification n in _due)
              if (n.fireAt.isAfter(_lastDueCheck)) n.id,
          }
        : const {};
    _lastDueCheck = now;
    _delivery.announce(
      due: _due,
      now: now,
      inForeground: _inForeground,
      inBackground: _inBackground,
      becameDueInForeground: becameDueInForeground,
    );
    _armDueTimer(now);
    notifyListeners();
  }

  void _armDueTimer(DateTime now) {
    _dueTimer?.cancel();
    _dueTimer = null;
    DateTime? next;
    for (final AdminNotification n in _all) {
      if (n.isDueAt(now)) continue;
      if (next == null || n.fireAt.isBefore(next)) next = n.fireAt;
    }
    if (next == null) return;
    _dueTimer = Timer(next.difference(now) + const Duration(seconds: 1),
        () => _refreshDue());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool inForeground = state == AppLifecycleState.resumed;
    final bool inBackground = state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (inForeground == _inForeground && inBackground == _inBackground) {
      return;
    }
    _inForeground = inForeground;
    _inBackground = inBackground;
    if (inForeground &&
        _uid != null &&
        (_hasError || !DateFormatter.isSameDay(_windowStart, DateTime.now()))) {
      _lastDueCheck = DateTime.now();
      _subscribe();
      return;
    }
    _refreshDue(resumed: inForeground);
  }

  @override
  void dispose() {
    _stop(notify: false);
    super.dispose();
  }

  Future<void> loadOlder() async {
    final DocumentSnapshot<Map<String, dynamic>>? after = _oldestLoaded;
    if (!_hasMoreOlder || _loadingOlder || after == null) return;
    final int generation = _windowGeneration;
    _loadingOlder = true;
    notifyListeners();
    try {
      final QuerySnapshot<Map<String, dynamic>> page = await _collection
          .where(AdminNotification.fireAtField,
              isLessThanOrEqualTo: Timestamp.fromDate(_windowStart))
          .orderBy(AdminNotification.fireAtField, descending: true)
          .startAfterDocument(after)
          .limit(olderPageSize)
          .get();
      if (generation != _windowGeneration) return;
      final Set<String> known = {
        for (final n in _all) n.id,
        for (final n in _older) n.id,
      };
      _older = [
        ..._older,
        ..._visible(page).where((n) => !known.contains(n.id)),
      ];
      if (page.docs.isNotEmpty) _oldestLoaded = page.docs.last;
      _hasMoreOlder = page.docs.length >= olderPageSize;
    } finally {
      if (generation == _windowGeneration) {
        _loadingOlder = false;
        notifyListeners();
      }
    }
  }

  Future<void> markRead(String id) async {
    final String? uid = _uid ?? _currentUid;
    if (uid == null || id.isEmpty) return;
    final AdminNotification? local = _findLocal(id);
    if (local != null && !local.isUnreadFor(uid)) return;
    await _collection.doc(id).update({
      '${AdminNotification.readByField}.$uid': Timestamp.now(),
    });
    _markOlderRead({id}, uid);
  }

  Future<void> markAllRead() async {
    final String? uid = _uid;
    if (uid == null) return;
    final List<AdminNotification> unread =
        notifications.where((n) => n.isUnreadFor(uid)).toList();
    final Timestamp readAt = Timestamp.now();
    for (int start = 0; start < unread.length; start += _batchLimit) {
      final WriteBatch batch = _db.batch();
      for (final AdminNotification n
          in unread.skip(start).take(_batchLimit)) {
        batch.update(_collection.doc(n.id), {
          '${AdminNotification.readByField}.$uid': readAt,
        });
      }
      await batch.commit();
    }
    _markOlderRead({for (final n in unread) n.id}, uid);
  }

  void _markOlderRead(Set<String> ids, String uid) {
    if (_older.every((n) => !ids.contains(n.id))) return;
    final DateTime now = DateTime.now();
    _older = [
      for (final AdminNotification n in _older)
        ids.contains(n.id) ? n.markedReadBy(uid, now) : n,
    ];
    notifyListeners();
  }

  AdminNotification? _findLocal(String id) {
    for (final AdminNotification n in [..._all, ..._older]) {
      if (n.id == id) return n;
    }
    return null;
  }

  static const int _batchLimit = 450;

  Future<int> addBloodTestReminders({
    required String userId,
    required String userName,
    required DateTime testDate,
  }) async {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(testDate.year, testDate.month, testDate.day);
    await removePendingBloodTestRemindersBefore(userId: userId, testDate: day);

    final Map<BloodTestReminderStage, DateTime> plan =
        BloodTestReminderSchedule.plan(day, now);
    final WriteBatch batch = _db.batch();
    int written = 0;
    for (final MapEntry<BloodTestReminderStage, DateTime> entry
        in plan.entries) {
      final BloodTestReminderStage stage = entry.key;
      final DateTime fireAt = entry.value;
      final DocumentReference<Map<String, dynamic>> ref = _collection
          .doc(AdminNotification.bloodTestReminderId(userId, day, stage));
      if ((await ref.get()).exists) continue;
      written++;
      batch.set(ref, {
        AdminNotification.typeField:
            AdminNotificationType.bloodTestReminder.value,
        AdminNotification.titleField:
            AdminNotification.bloodTestReminderTitle(stage),
        AdminNotification.bodyField:
            AdminNotification.bloodTestReminderBody(userName, day, stage),
        AdminNotification.fireAtField: Timestamp.fromDate(fireAt),
        AdminNotification.userIdField: userId,
        AdminNotification.userNameField: userName,
        AdminNotification.testDateField: Timestamp.fromDate(day),
        AdminNotification.stageField: stage.value,
        AdminNotification.createdAtField: FieldValue.serverTimestamp(),
        AdminNotification.createdByField: _currentUid,
        AdminNotification.readByField: <String, Object>{},
      });
    }
    if (written > 0) await batch.commit();
    return written;
  }

  Stream<List<AdminNotification>> remindersOf(String userId) {
    return _collection
        .where(AdminNotification.userIdField, isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final String? uid = _uid ?? _currentUid;
      final List<AdminNotification> reminders = [];
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        final AdminNotification? n = AdminNotification.fromDocument(doc);
        if (n != null && uid != null && n.isVisibleTo(uid)) reminders.add(n);
      }
      return reminders..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    });
  }

  Future<void> removeBloodTestReminders({
    required String userId,
    required DateTime testDate,
  }) async {
    final WriteBatch batch = _db.batch();
    for (final BloodTestReminderStage stage in BloodTestReminderStage.values) {
      batch.delete(_collection.doc(AdminNotification.bloodTestReminderId(
          userId, DateTime(testDate.year, testDate.month, testDate.day), stage)));
    }
    await batch.commit();
  }

  Future<void> removePendingBloodTestRemindersBefore({
    required String userId,
    required DateTime testDate,
  }) async {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(testDate.year, testDate.month, testDate.day);
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
        .where(AdminNotification.userIdField, isEqualTo: userId)
        .get();
    final List<DocumentReference<Map<String, dynamic>>> stale = [];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final AdminNotification? n = AdminNotification.fromDocument(doc);
      final DateTime? reminderTestDate = n?.testDate;
      if (n == null ||
          n.isTest ||
          n.type != AdminNotificationType.bloodTestReminder ||
          reminderTestDate == null) {
        continue;
      }
      if (reminderTestDate.isBefore(day) && !n.isDueAt(now)) {
        stale.add(doc.reference);
      }
    }
    await _deleteAll(stale);
  }

  Future<void> removePendingNotificationsOfUser(String userId) async {
    final DateTime now = DateTime.now();
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
        .where(AdminNotification.userIdField, isEqualTo: userId)
        .get();
    await _deleteAll([
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        if (AdminNotification.fromDocument(doc)?.isDueAt(now) == false)
          doc.reference,
    ]);
  }

  Future<void> _deleteAll(
      List<DocumentReference<Map<String, dynamic>>> refs) async {
    for (int start = 0; start < refs.length; start += _batchLimit) {
      final WriteBatch batch = _db.batch();
      for (final DocumentReference<Map<String, dynamic>> ref
          in refs.skip(start).take(_batchLimit)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  Future<String?> addTestNotification({
    required DateTime fireAt,
    AdminTestNotificationKind kind = AdminTestNotificationKind.plain,
    List<NotificationCustomer> customers = const [],
    DateTime? testDate,
  }) async {
    final String? uid = _uid ?? _currentUid;
    if (uid == null) return null;
    final String id =
        'test_${uid}_${fireAt.microsecondsSinceEpoch}_${kind.name}';
    await _collection.doc(id).set({
      ..._testContent(kind, fireAt, customers, testDate),
      AdminNotification.fireAtField: Timestamp.fromDate(fireAt),
      AdminNotification.onlyForField: uid,
      AdminNotification.isTestField: true,
      AdminNotification.createdAtField: FieldValue.serverTimestamp(),
      AdminNotification.createdByField: uid,
      AdminNotification.readByField: <String, Object>{},
    });
    return id;
  }

  static Map<String, Object> _testContent(
    AdminTestNotificationKind kind,
    DateTime fireAt,
    List<NotificationCustomer> customers,
    DateTime? givenTestDate,
  ) {
    switch (kind) {
      case AdminTestNotificationKind.plain:
        return {
          AdminNotification.typeField: AdminNotificationType.test.value,
          AdminNotification.titleField: AdminNotification.testTitle,
          AdminNotification.bodyField: AdminNotification.testBody,
        };
      case AdminTestNotificationKind.bloodTestDayBefore:
      case AdminTestNotificationKind.bloodTestDueDay:
        if (customers.isEmpty) {
          throw ArgumentError.value(customers, 'customers', 'Danışan seçilmedi');
        }
        final NotificationCustomer customer = customers.first;
        final BloodTestReminderStage stage =
            kind == AdminTestNotificationKind.bloodTestDayBefore
                ? BloodTestReminderStage.dayBefore
                : BloodTestReminderStage.dueDay;
        final DateTime dueDay = DateTime(fireAt.year, fireAt.month,
            fireAt.day + (stage == BloodTestReminderStage.dayBefore ? 1 : 0));
        final DateTime testDate = givenTestDate == null
            ? BloodTestReminderSchedule.testDateDueOnOrAfter(dueDay)
            : DateTime(
                givenTestDate.year, givenTestDate.month, givenTestDate.day);
        return {
          AdminNotification.typeField:
              AdminNotificationType.bloodTestReminder.value,
          AdminNotification.titleField:
              AdminNotification.bloodTestReminderTitle(stage),
          AdminNotification.bodyField: AdminNotification.bloodTestReminderBody(
              customer.name, testDate, stage),
          AdminNotification.userIdField: customer.userId,
          AdminNotification.userNameField: customer.name,
          AdminNotification.testDateField: Timestamp.fromDate(testDate),
          AdminNotification.stageField: stage.value,
        };
      case AdminTestNotificationKind.missingBloodTests:
        return {
          AdminNotification.typeField:
              AdminNotificationType.missingBloodTests.value,
          AdminNotification.titleField:
              AdminNotification.missingBloodTestsTitle(customers.length),
          AdminNotification.bodyField:
              AdminNotification.missingBloodTestsBody(customers),
          AdminNotification.dayField: DateFormatter.formatIsoDate(fireAt),
          AdminNotification.customersField: [
            for (final NotificationCustomer customer in customers)
              customer.toMap(),
          ],
          AdminNotification.supersededField: false,
        };
    }
  }

  Future<int> removeTestNotifications() async {
    final String? uid = _uid ?? _currentUid;
    if (uid == null) return 0;
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
        .where(AdminNotification.onlyForField, isEqualTo: uid)
        .get();
    final List<DocumentReference<Map<String, dynamic>>> refs = [
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        if (AdminNotification.fromDocument(doc)?.isTest ?? false) doc.reference,
    ];
    await _deleteAll(refs);
    return refs.length;
  }

  Future<void> supersedeMissingBloodTestLists({String? exceptId}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
        .where(AdminNotification.typeField,
            isEqualTo: AdminNotificationType.missingBloodTests.value)
        .where(AdminNotification.supersededField, isEqualTo: false)
        .get();
    final List<DocumentReference<Map<String, dynamic>>> refs = [
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        if (doc.id != exceptId &&
            !(AdminNotification.fromDocument(doc)?.isTest ?? false))
          doc.reference,
    ];
    for (int start = 0; start < refs.length; start += _batchLimit) {
      final WriteBatch batch = _db.batch();
      for (final DocumentReference<Map<String, dynamic>> ref
          in refs.skip(start).take(_batchLimit)) {
        batch.update(ref, {AdminNotification.supersededField: true});
      }
      await batch.commit();
    }
  }

  Future<void> saveMissingBloodTestList({
    required String day,
    required List<NotificationCustomer> customers,
    required DateTime at,
  }) async {
    await _collection.doc(AdminNotification.missingBloodTestsId(day)).set({
      AdminNotification.typeField: AdminNotificationType.missingBloodTests.value,
      AdminNotification.titleField:
          AdminNotification.missingBloodTestsTitle(customers.length),
      AdminNotification.bodyField:
          AdminNotification.missingBloodTestsBody(customers),
      AdminNotification.fireAtField: Timestamp.fromDate(at),
      AdminNotification.dayField: day,
      AdminNotification.customersField: [
        for (final NotificationCustomer customer in customers) customer.toMap(),
      ],
      AdminNotification.supersededField: false,
      AdminNotification.createdAtField: FieldValue.serverTimestamp(),
      AdminNotification.createdByField: _currentUid,
    }, SetOptions(merge: true));
  }
}
