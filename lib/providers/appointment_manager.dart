import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/appointment_model.dart';
import '../models/logger.dart';
import '../models/user_model.dart';
import '../models/filter_params.dart';
import '../providers/sub_provider.dart'; // << make sure this path matches your project

class AppointmentManager extends ChangeNotifier {
  static const String _fieldMeetingsCompleted = 'meetingsCompleted';
  static const String _fieldMeetingsBurned = 'meetingsBurned';

  final Logger logger = Logger.forClass(AppointmentManager);
  final SubProvider subProvider;

  AppointmentManager({required this.subProvider});

  AppointmentStatus _statusFromLabelSafe(String? label) {
    if (label == null) return AppointmentStatus.scheduled;
    try {
      return AppointmentStatus.fromLabel(label);
    } catch (_) {
      return AppointmentStatus.scheduled;
    }
  }

  // ---------------------- CREATE ----------------------

  /// The subscription counter a status feeds, or null when the status moves no
  /// counter at all. Keeps the counter field names in one place.
  static String? _meetingCounterField(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.completed:
        return _fieldMeetingsCompleted;
      case AppointmentStatus.burned:
        return _fieldMeetingsBurned;
      default:
        return null;
    }
  }

  /// The counter [data] (a raw appointment document) feeds, or null.
  /// Tartım visits never move a counter, on either side of an edit.
  String? _meetingCounterFieldOfDoc(Map<String, dynamic> data) {
    final counts = AppointmentType
        .fromLabel(data['appointmentType'] as String? ?? '')
        .countsTowardMeetings;
    if (!counts) return null;
    return _meetingCounterField(_statusFromLabelSafe(data['status'] as String?));
  }

  /// The counter [appointment] feeds, or null (Tartım visits move none).
  String? _meetingCounterFieldOf(AppointmentModel appointment) =>
      appointment.countsTowardMeetings
          ? _meetingCounterField(appointment.status)
          : null;

  DocumentReference<Map<String, dynamic>> _subRef(String userId, String subId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('subscriptions')
          .doc(subId);

  DocumentReference<Map<String, dynamic>> _apptRef(
          String userId, String appointmentId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('appointments')
          .doc(appointmentId);

  /// Whether [subId] points at a subscription that still exists.
  /// `update()` fails on a missing document, so a counter is only queued once
  /// its subscription is known to be there.
  Future<bool> _subscriptionExists(String userId, String? subId) async {
    if (subId == null || subId.isEmpty) return false;
    final snap = await _subRef(userId, subId).get();
    return snap.exists;
  }

  /// Adds a new appointment; if created as "Yapıldı" or "Yakıldı", increments the subscription counter.
  ///
  /// The appointment and its counter are committed in a single batch: a partial
  /// write would leave meetingsCompleted/meetingsBurned drifting from reality.
  Future<void> addAppointment(AppointmentModel appointment) async {
    try {
      final db = FirebaseFirestore.instance;
      final apptRef = _apptRef(appointment.userId, appointment.appointmentId);

      final String? subId = appointment.subscriptionId;
      // Only a status that actually moves a counter is worth a subscription
      // read; plain "Planlandı" adds now go straight to the write.
      final String? counterField = _meetingCounterFieldOf(appointment);
      final bool touchesSub = counterField != null &&
          await _subscriptionExists(appointment.userId, subId);

      // An appointment without a subscription is normal; only a named-but-gone
      // subscription is worth warning about.
      if (counterField != null && (subId?.isNotEmpty ?? false) && !touchesSub) {
        logger.warn(
          'Sub missing during add: user={}, sub={}',
          [appointment.userId, subId],
        );
      }

      final batch = db.batch();
      batch.set(apptRef, appointment.toMap());
      if (touchesSub) {
        batch.update(_subRef(appointment.userId, subId!), <String, Object?>{
          counterField: FieldValue.increment(1),
        });
      }
      await batch.commit();

      if (touchesSub) {
        subProvider.markChanged();
      }

      logger.info('Appointment added: {}', [appointment]);
    } catch (e) {
      logger.err('Error adding appointment: {}', [e]);
      rethrow;
    }
  }

  // ---------------------- UPDATE ----------------------

  /// Rewrites an appointment and re-balances the subscription counters it
  /// affects.
  ///
  /// Counter deltas are accumulated per subscription first, so moving an
  /// appointment between two statuses of the same package costs one write
  /// instead of two, and everything (appointment + counters) lands in a single
  /// batch.
  Future<void> updateAppointment(AppointmentModel updated) async {
    try {
      final db = FirebaseFirestore.instance;
      final apptRef = _apptRef(updated.userId, updated.appointmentId);

      // subId -> counter field -> net delta
      final deltas = <String, Map<String, int>>{};
      void addDelta(String? subId, String? field, int delta) {
        if (subId == null || subId.isEmpty || field == null) return;
        final perSub = deltas.putIfAbsent(subId, () => <String, int>{});
        perSub[field] = (perSub[field] ?? 0) + delta;
      }

      final prevSnap = await apptRef.get();
      final Map<String, dynamic>? prev =
          prevSnap.exists ? prevSnap.data() as Map<String, dynamic> : null;

      if (prev == null) {
        logger.info(
            'updateAppointment: previous appointment not found, treating as add. apptId={}',
            [updated.appointmentId]);
      }

      final String? prevSubId =
          prev == null ? null : prev['subscriptionId'] as String?;
      final String? prevField =
          prev == null ? null : _meetingCounterFieldOfDoc(prev);
      final String? newSubId = updated.subscriptionId;
      final String? newField = _meetingCounterFieldOf(updated);

      // A counter only moves when the (subscription, field) pair actually
      // changes; an untouched pair keeps its current value. An appointment
      // without a subscription moves nothing on either side.
      final bool samePair = prevSubId == newSubId && prevField == newField;
      final bool releasesPrev =
          prevField != null && (prevSubId?.isNotEmpty ?? false) && !samePair;
      final bool claimsNew =
          newField != null && (newSubId?.isNotEmpty ?? false) && !samePair;

      // Both subscription documents are checked at once instead of one after
      // the other.
      final existence = await Future.wait([
        releasesPrev
            ? _subscriptionExists(updated.userId, prevSubId)
            : Future<bool>.value(false),
        claimsNew
            ? _subscriptionExists(updated.userId, newSubId)
            : Future<bool>.value(false),
      ]);
      final bool prevExists = existence[0];
      final bool newExists = existence[1];

      if (releasesPrev) {
        if (prevExists) {
          addDelta(prevSubId, prevField, -1);
        } else {
          logger.warn(
            'Prev sub missing during update decrement ({}): user={}, sub={}',
            [prevField, updated.userId, prevSubId],
          );
        }
      }
      if (claimsNew) {
        if (newExists) {
          addDelta(newSubId, newField, 1);
        } else {
          logger.warn(
            'New sub missing during update increment ({}): user={}, sub={}',
            [newField, updated.userId, newSubId],
          );
        }
      }

      final batch = db.batch();
      // A missing previous document is an add, so set() (not update()) is used.
      if (prev == null) {
        batch.set(apptRef, updated.toMap());
      } else {
        batch.update(apptRef, updated.toMap());
      }
      final bool subChanged = _queueCounterUpdates(batch, updated.userId, deltas);
      await batch.commit();

      if (subChanged) {
        subProvider.markChanged();
      }

      logger.info('Appointment updated: {}', [updated]);
    } catch (e) {
      logger.err('Error updating appointment: {}', [e]);
      rethrow;
    }
  }

  /// Queues one update per subscription for the accumulated [deltas].
  /// Returns whether anything was queued, i.e. whether SubProvider must be
  /// notified after the commit.
  bool _queueCounterUpdates(
    WriteBatch batch,
    String userId,
    Map<String, Map<String, int>> deltas,
  ) {
    bool queued = false;
    for (final entry in deltas.entries) {
      final updates = <String, Object?>{
        for (final counter in entry.value.entries)
          if (counter.value != 0) counter.key: FieldValue.increment(counter.value),
      };
      if (updates.isEmpty) continue;
      logger.info(
        'Subscription counters user={}, sub={}, deltas={}',
        [userId, entry.key, entry.value],
      );
      batch.update(_subRef(userId, entry.key), updates);
      queued = true;
    }
    return queued;
  }

  // ---------------------- DELETE / CANCEL ----------------------

  Future<bool> deleteAppointment(
      String appointmentId,
      String userId, {
        required String deletedBy,
      }) async {
    return _releaseAppointment(
      appointmentId: appointmentId,
      userId: userId,
      actor: deletedBy,
      operation: 'deleteAppointment',
      applyWrite: (batch, apptRef) => batch.delete(apptRef),
    );
  }

  Future<bool> cancelAppointment(
      String appointmentId,
      String userId, {
        required String canceledBy,
      }) async {
    final now = Timestamp.now();
    return _releaseAppointment(
      appointmentId: appointmentId,
      userId: userId,
      actor: canceledBy,
      operation: 'cancelAppointment',
      applyWrite: (batch, apptRef) => batch.update(apptRef, {
        'status': AppointmentStatus.canceled.label,
        'canceledBy': canceledBy,
        'canceledAt': now,
        'updateDate': now,
        'updateUser': canceledBy,
      }),
    );
  }

  /// Shared body of delete and cancel: both take the appointment out of the
  /// schedule and must give back the subscription meeting it had consumed.
  /// The appointment write and the counter land in one batch.
  Future<bool> _releaseAppointment({
    required String appointmentId,
    required String userId,
    required String actor,
    required String operation,
    required void Function(
            WriteBatch batch, DocumentReference<Map<String, dynamic>> apptRef)
        applyWrite,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final apptRef = _apptRef(userId, appointmentId);

      final snap = await apptRef.get();
      if (!snap.exists) {
        logger.warn(
          '{}: appointment not found, user={}, appt={}',
          [operation, userId, appointmentId],
        );
        return false;
      }

      final data = snap.data() as Map<String, dynamic>;
      final String? subId = data['subscriptionId'] as String?;
      // Tartım visits never incremented the counters, so they must not be
      // decremented here either.
      final String? counterField = _meetingCounterFieldOfDoc(data);
      final bool touchesSub = counterField != null &&
          await _subscriptionExists(userId, subId);

      final batch = db.batch();
      applyWrite(batch, apptRef);
      if (touchesSub) {
        logger.info(
          '{}: decrement {} for user={}, sub={}',
          [operation, counterField, userId, subId],
        );
        batch.update(_subRef(userId, subId!), <String, Object?>{
          counterField: FieldValue.increment(-1),
        });
      }
      await batch.commit();

      if (touchesSub) {
        subProvider.markChanged();
      }

      logger.info('{} by={}: appointmentId={}', [operation, actor, appointmentId]);
      return true;
    } catch (e) {
      logger.err('Error in {}: {}', [operation, e]);
      rethrow;
    }
  }

  // ---------------------- THE REST (unchanged) ----------------------

  Future<List<AppointmentModel>> fetchAppointments(String? subscriptionId,
      {required bool showAllAppointments, required String userId, AppointmentFilterParams? filterParams}) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('appointments')
          .where('isDeleted', isNull:true );

      if (!showAllAppointments && subscriptionId != null) {
        query = query.where('subscriptionId', isEqualTo: subscriptionId);
      }

      // Apply filter parameters if provided
      if (filterParams != null) {
        // Status filter
        if (filterParams.status != null) {
          query = query.where('status', isEqualTo: filterParams.status);
        }

        // Meeting type filter
        if (filterParams.meetingType != null) {
          query = query.where('meetingType', isEqualTo: filterParams.meetingType);
        }

        // Date range filter
        if (filterParams.dateRange != null) {
          query = query
              .where('appointmentDateTime', isGreaterThanOrEqualTo: filterParams.dateRange!.start)
              .where('appointmentDateTime', isLessThanOrEqualTo: DateTime(
                filterParams.dateRange!.end.year,
                filterParams.dateRange!.end.month,
                filterParams.dateRange!.end.day,
                23,
                59,
                59,
              ));
        }
        
        // Note: Search query filtering (notes) cannot be done efficiently in Firestore
        // without full-text search. This will need to be done client-side for now.
      }
      
      // Apply ordering
      query = query.orderBy('appointmentDateTime', descending: false);

      final snapshot = await query.get();
      logger.info('snapshot.iscache={}',[snapshot.metadata.isFromCache]);
      var appointments = snapshot.docs.map((doc) => AppointmentModel.fromDocument(doc)).toList();

      // Apply client-side search filter if needed (Firestore doesn't support full-text search efficiently)
      if (filterParams?.searchQuery != null && filterParams!.searchQuery!.isNotEmpty) {
        final searchLower = filterParams.searchQuery!.toLowerCase();
        appointments = appointments.where((a) {
          return a.notes?.toLowerCase().contains(searchLower) ?? false;
        }).toList();
      }
      logger.info('Appointments fetched successfully with filters: {}', [filterParams?.toDebugMap()]);
      return appointments;
    } catch (e) {
      logger.err('Error fetching appointments: {}', [e]);
      rethrow;
    }
  }


  // Future<List<AppointmentModel>> fetchAppointmentsForDateRange(
  //     DateTime startDate,
  //     DateTime endDate, {
  //       bool includeAllUsers = false,
  //       String? userId,
  //       AppointmentStatus? statusFilter,
  //     }) async {
  //   try {
  //     Query query;
  //
  //     if (includeAllUsers) {
  //       query = FirebaseFirestore.instance
  //           .collectionGroup('appointments')
  //           .where('isDeleted',isNull:true )
  //           .where('appointmentDateTime', isGreaterThanOrEqualTo: startDate)
  //           .where('appointmentDateTime', isLessThan: endDate);
  //     } else if (userId != null) {
  //       query = FirebaseFirestore.instance
  //           .collection('users')
  //           .doc(userId)
  //           .collection('appointments')
  //           .where('isDeleted', isNull:true )
  //           .where('appointmentDateTime', isGreaterThanOrEqualTo: startDate)
  //           .where('appointmentDateTime', isLessThan: endDate);
  //     } else {
  //       throw ArgumentError('Either includeAllUsers must be true or userId must be provided');
  //     }
  //
  //     if (statusFilter != null) {
  //       query = query.where('status', isEqualTo: statusFilter.label);
  //     }
  //
  //     final snapshot = await query.get();
  //     final appointments = snapshot.docs.map((doc) => AppointmentModel.fromDocument(doc)).toList();
  //
  //     logger.info('Fetched {} appointments for date range {}-{}', [appointments.length, startDate, endDate]);
  //     return appointments;
  //   } catch (e) {
  //     logger.err('Error fetching appointments for date range: {}', [e]);
  //     rethrow;
  //   }
  // }

  ///ADMIN APPTS PAGE
  Future<List<AppointmentModel>> fetchAppointmentsWithUsers({
    DateTime? startDate,
    DateTime? endDate,
    AppointmentStatus? statusFilter,
    MeetingType? meetingTypeFilter,
    Set<AppointmentStatus>? statusesFilter,
  }) async {
    try {
      final Map<String, AppointmentModel> appointmentsMap = {};

      // Query 1: Fetch appointments by appointmentDateTime
      Query query1 = FirebaseFirestore.instance
          .collectionGroup('appointments')
          .where('isDeleted', isNull:true );
      if (startDate != null) {
        query1 = query1.where('appointmentDateTime', isGreaterThanOrEqualTo: startDate);
      }
      if (endDate != null) {
        query1 = query1.where('appointmentDateTime', isLessThan: endDate.add(const Duration(days: 1)));
      }
      if (statusFilter != null) {
        query1 = query1.where('status', isEqualTo: statusFilter.label);
      }
      if (meetingTypeFilter != null) {
        query1 = query1.where('meetingType', isEqualTo: meetingTypeFilter.label);
      }

      final snapshot1 = await query1.get();
      for (final doc in snapshot1.docs) {
        final appointment = AppointmentModel.fromDocument(doc);
        appointmentsMap[appointment.appointmentId] = appointment;
      }

      // Query 2: Fetch postponed appointments by postponedDate (if date range specified)
      if (startDate != null || endDate != null) {
        Query query2 = FirebaseFirestore.instance
            .collectionGroup('appointments')
            .where('isDeleted', isNull:true );
        query2 = query2.where('status', isEqualTo: AppointmentStatus.postponed.label);
        if (startDate != null) {
          query2 = query2.where('postponedDate', isGreaterThanOrEqualTo: startDate);
        }
        if (endDate != null) {
          query2 = query2.where('postponedDate', isLessThan: endDate.add(const Duration(days: 1)));
        }
        if (meetingTypeFilter != null) {
          query2 = query2.where('meetingType', isEqualTo: meetingTypeFilter.label);
        }

        final snapshot2 = await query2.get();
        for (final doc in snapshot2.docs) {
          final appointment = AppointmentModel.fromDocument(doc);
          // Add only if not already in map (avoid duplicates)
          if (!appointmentsMap.containsKey(appointment.appointmentId)) {
            appointmentsMap[appointment.appointmentId] = appointment;
          }
        }
      }

      // Fetch user data for all appointments. One read per *client*, not per
      // appointment: a client usually has several appointments in the range, so
      // the ids are de-duplicated first and the remaining reads run in parallel.
      final fetchedAppointments = appointmentsMap.values.toList();
      final userById = await _fetchUsersByIds(
        fetchedAppointments.map((a) => a.userId).toSet(),
      );
      for (final appointment in fetchedAppointments) {
        appointment.user = userById[appointment.userId];
      }

      // Apply multiple status filter client-side (Firestore doesn't support WHERE IN with multiple range queries)
      var filtered = fetchedAppointments;
      if (statusesFilter != null && statusesFilter.isNotEmpty && statusesFilter.length < AppointmentStatus.values.length) {
        filtered = filtered.where((a) => statusesFilter.contains(a.status)).toList();
      }

      logger.info('Fetched {} appointments with user data (Firebase + client filtering)', [filtered.length]);
      return filtered;
    } catch (e) {
      logger.err('Error fetching appointments with users: {}', [e]);
      rethrow;
    }
  }

  /// Reads the given users once each, in parallel, and returns them by id.
  /// Missing users are simply absent from the map.
  Future<Map<String, UserModel>> _fetchUsersByIds(Set<String> userIds) async {
    if (userIds.isEmpty) return const {};

    final usersCollection = FirebaseFirestore.instance.collection('users');
    final ids = userIds.toList();
    final snapshots = await Future.wait(
      ids.map((id) => usersCollection.doc(id).get()),
    );

    final result = <String, UserModel>{};
    for (int i = 0; i < ids.length; i++) {
      final doc = snapshots[i];
      if (doc.exists) {
        result[ids[i]] = UserModel.fromDocument(doc);
      }
    }
    return result;
  }

  /// Returns the non-canceled appointments on the same day whose time interval
  /// overlaps `[start, start + durationMinutes)`. Used to warn the admin
  /// (without blocking) when a new appointment or event clashes with an
  /// existing meeting. Each returned appointment has its [AppointmentModel.user]
  /// populated and the list is sorted by start time.
  Future<List<AppointmentModel>> findOverlappingAppointments({
    required DateTime start,
    required int durationMinutes,
  }) async {
    final DateTime dayStart = DateTime(start.year, start.month, start.day);
    final DateTime newEnd = start.add(Duration(minutes: durationMinutes));

    DateTime effectiveStart(AppointmentModel a) =>
        (a.status == AppointmentStatus.postponed && a.postponedDate != null)
            ? a.postponedDate!
            : a.appointmentDateTime;

    final dayAppointments = await fetchAppointmentsWithUsers(
      startDate: dayStart,
      endDate: dayStart,
    );

    final overlapping = dayAppointments.where((a) {
      if (a.status == AppointmentStatus.canceled) return false;
      final effStart = effectiveStart(a);
      final effEnd = effStart.add(Duration(minutes: a.durationMinutes));
      // Half-open interval overlap test.
      return start.isBefore(effEnd) && effStart.isBefore(newEnd);
    }).toList()
      ..sort((a, b) => effectiveStart(a).compareTo(effectiveStart(b)));

    return overlapping;
  }
}
