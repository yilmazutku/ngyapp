import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../models/admin_notification.dart';
import '../services/admin_notification_delivery.dart';

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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  List<AdminNotification> _all = const [];

  List<AdminNotification> _due = const [];

  List<AdminNotification> _older = const [];

  DocumentSnapshot<Map<String, dynamic>>? _oldestLoaded;
  bool _hasMoreOlder = false;
  bool _loadingOlder = false;

  bool _loaded = false;
  bool _hasError = false;
  bool _inForeground = true;
  DateTime _lastDueCheck = DateTime.now();
  Timer? _dueTimer;

  List<AdminNotification> get notifications =>
      _older.isEmpty ? _due : [..._due, ..._older];

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
    if (_uid == uid && _subscription != null) return;
    _stop(notify: false);
    _owner = owner;
    _uid = uid;
    _inForeground = true;
    _lastDueCheck = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    _delivery.attach(uid);
    _subscription = _collection
        .orderBy(AdminNotification.fireAtField, descending: true)
        .limit(listLimit)
        .snapshots()
        .listen(_onSnapshot, onError: (Object error) {
      _hasError = true;
      _loaded = true;
      notifyListeners();
    });
  }

  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _stop(notify: true);
  }

  void _stop({required bool notify}) {
    final bool wasActive = _uid != null;
    _subscription?.cancel();
    _subscription = null;
    _dueTimer?.cancel();
    _dueTimer = null;
    if (wasActive) WidgetsBinding.instance.removeObserver(this);
    _delivery.detach();
    _uid = null;
    _owner = null;
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

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    _all = snapshot.docs
        .map(AdminNotification.fromDocument)
        .whereType<AdminNotification>()
        .toList();
    if (_older.isEmpty) {
      _oldestLoaded = snapshot.docs.isEmpty ? null : snapshot.docs.last;
      _hasMoreOlder = snapshot.docs.length >= listLimit;
    } else {
      final Set<String> live = {for (final n in _all) n.id};
      _older = _older.where((n) => !live.contains(n.id)).toList();
    }
    _loaded = true;
    _hasError = false;
    final DateTime now = DateTime.now();
    _delivery.syncUpcoming(
      _all.where((n) => !n.isDueAt(now)).toList().reversed.toList(),
    );
    _refreshDue(viaTimer: false);
  }

  void _refreshDue({required bool viaTimer}) {
    if (_uid == null) return;
    final DateTime now = DateTime.now();
    _due = _all.where((n) => n.isDueAt(now)).toList();
    final Set<String> becameDueInForeground = viaTimer && _inForeground
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
        () => _refreshDue(viaTimer: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool inForeground = state == AppLifecycleState.resumed;
    if (inForeground == _inForeground) return;
    _inForeground = inForeground;
    _refreshDue(viaTimer: false);
  }

  @override
  void dispose() {
    _stop(notify: false);
    super.dispose();
  }

  Future<void> loadOlder() async {
    final DocumentSnapshot<Map<String, dynamic>>? after = _oldestLoaded;
    if (!_hasMoreOlder || _loadingOlder || after == null) return;
    _loadingOlder = true;
    notifyListeners();
    try {
      final QuerySnapshot<Map<String, dynamic>> page = await _collection
          .orderBy(AdminNotification.fireAtField, descending: true)
          .startAfterDocument(after)
          .limit(olderPageSize)
          .get();
      final Set<String> known = {
        for (final n in _all) n.id,
        for (final n in _older) n.id,
      };
      _older = [
        ..._older,
        ...page.docs
            .map(AdminNotification.fromDocument)
            .whereType<AdminNotification>()
            .where((n) => !known.contains(n.id)),
      ];
      if (page.docs.isNotEmpty) _oldestLoaded = page.docs.last;
      _hasMoreOlder = page.docs.length >= olderPageSize;
    } finally {
      _loadingOlder = false;
      notifyListeners();
    }
  }

  Future<void> markRead(String id) async {
    final String? uid = _uid ?? _currentUid;
    if (uid == null || id.isEmpty) return;
    final AdminNotification? local = _findLocal(id);
    if (local != null && !local.isUnreadFor(uid)) return;
    await _collection.doc(id).update({
      '${AdminNotification.readByField}.$uid': FieldValue.serverTimestamp(),
    });
    _markOlderRead({id}, uid);
  }

  Future<void> markAllRead() async {
    final String? uid = _uid;
    if (uid == null) return;
    final List<AdminNotification> unread =
        notifications.where((n) => n.isUnreadFor(uid)).toList();
    for (int start = 0; start < unread.length; start += _batchLimit) {
      final WriteBatch batch = _db.batch();
      for (final AdminNotification n
          in unread.skip(start).take(_batchLimit)) {
        batch.update(_collection.doc(n.id), {
          '${AdminNotification.readByField}.$uid':
              FieldValue.serverTimestamp(),
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

  Future<void> addBloodTestReminders({
    required String userId,
    required String userName,
    required DateTime testDate,
  }) async {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(testDate.year, testDate.month, testDate.day);
    await _removePendingRemindersBefore(userId: userId, testDate: day, now: now);

    final Map<BloodTestReminderStage, DateTime> plan =
        BloodTestReminderSchedule.plan(day, now);
    final WriteBatch batch = _db.batch();
    bool hasWrites = false;
    for (final MapEntry<BloodTestReminderStage, DateTime> entry
        in plan.entries) {
      final BloodTestReminderStage stage = entry.key;
      final DateTime fireAt = entry.value;
      final DocumentReference<Map<String, dynamic>> ref = _collection
          .doc(AdminNotification.bloodTestReminderId(userId, day, stage));
      if ((await ref.get()).exists) continue;
      hasWrites = true;
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
    if (hasWrites) await batch.commit();
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

  Future<void> _removePendingRemindersBefore({
    required String userId,
    required DateTime testDate,
    required DateTime now,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
        .where(AdminNotification.userIdField, isEqualTo: userId)
        .get();
    final List<DocumentReference<Map<String, dynamic>>> stale = [];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      final AdminNotification? n = AdminNotification.fromDocument(doc);
      final DateTime? reminderTestDate = n?.testDate;
      if (n == null ||
          n.type != AdminNotificationType.bloodTestReminder ||
          reminderTestDate == null) {
        continue;
      }
      if (reminderTestDate.isBefore(testDate) && !n.isDueAt(now)) {
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

  Future<void> supersedeMissingBloodTestLists({String? exceptId}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
        .where(AdminNotification.typeField,
            isEqualTo: AdminNotificationType.missingBloodTests.value)
        .where(AdminNotification.supersededField, isEqualTo: false)
        .get();
    final List<DocumentReference<Map<String, dynamic>>> refs = [
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs)
        if (doc.id != exceptId) doc.reference,
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
