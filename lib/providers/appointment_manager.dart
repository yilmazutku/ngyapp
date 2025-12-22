import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/appointment_model.dart';
import '../models/logger.dart';
import '../models/user_model.dart';
import '../models/filter_params.dart';
import '../providers/sub_provider.dart'; // << make sure this path matches your project

class AppointmentManager extends ChangeNotifier {
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

  /// Adds a new appointment; if created as "Yapıldı" or "Yakıldı", increments the subscription counter.
  Future<void> addAppointment(AppointmentModel appointment) async {
    try {
      final db = FirebaseFirestore.instance;
  // önceki hali runTransaction
      final apptRef = db
          .collection('users')
          .doc(appointment.userId)
          .collection('appointments')
          .doc(appointment.appointmentId);

      final String? subId = appointment.subscriptionId;
      bool subUpdated = false;

// 1) Write the appointment itself
      await apptRef.set(appointment.toMap());

// 2) If appointment is completed or burned and has a subscription, update subscription
      if (subId != null && subId.isNotEmpty) {
        final subRef = db
            .collection('users')
            .doc(appointment.userId)
            .collection('subscriptions')
            .doc(subId);

        final subSnap = await subRef.get();

        if (!subSnap.exists) {
          logger.warn(
            'Sub missing during add (non-tx): user={}, sub={}',
            [appointment.userId, subId],
          );
        } else {
          // Increment meetingsCompleted if completed
          if (appointment.status == AppointmentStatus.completed) {
            await subRef.update(<String, Object?>{
              'meetingsCompleted': FieldValue.increment(1),
            });
            subUpdated = true;
          }
          // Increment meetingsBurned if burned
          if (appointment.status == AppointmentStatus.burned) {
            await subRef.update(<String, Object?>{
              'meetingsBurned': FieldValue.increment(1),
            });
            subUpdated = true;
          }
        }

        // 3) Notify provider so UI can react
        if (subUpdated) {
          subProvider.markChanged();
        }
      }


      logger.info('Appointment added: {}', [appointment]);
    } catch (e) {
      logger.err('Error adding appointment: {}', [e]);
      rethrow;
    }
  }

  // ---------------------- UPDATE ----------------------
  Future<void> updateAppointment(AppointmentModel updated) async {
    try {
      final db = FirebaseFirestore.instance;
      final apptRef = db
          .collection('users')
          .doc(updated.userId)
          .collection('appointments')
          .doc(updated.appointmentId);

      bool subChanged = false;

      // ---------- READ CURRENT APPOINTMENT ----------
      final prevSnap = await apptRef.get();

      if (!prevSnap.exists) {
        // Treat as add edge-case: read new sub if needed and then write
        logger.info('updateAppointment: previous appointment not found, treating as add. apptId={}', [updated.appointmentId]);

        final bool newDone = updated.status == AppointmentStatus.completed;
        final bool newBurned = updated.status == AppointmentStatus.burned;
        final String? newSubId = updated.subscriptionId;

        Map<String, dynamic>? newSubData;

        if ((newDone || newBurned) && newSubId != null && newSubId.isNotEmpty) {
          final newSubRef = db
              .collection('users')
              .doc(updated.userId)
              .collection('subscriptions')
              .doc(newSubId);
          final newSubSnap = await newSubRef.get();
          if (newSubSnap.exists) {
            newSubData = newSubSnap.data();
          } else {
            logger.warn(
              'Sub missing during update(add): user={}, sub={}',
              [updated.userId, newSubId],
            );
          }
        }

        // ---------- WRITE APPOINTMENT ----------
        await apptRef.set(updated.toMap());

        // Increment subscription counter if subscription exists and is valid
        if (newSubData != null && (updated.subscriptionId?.isNotEmpty ?? false)) {
          final newSubRef = db
              .collection('users')
              .doc(updated.userId)
              .collection('subscriptions')
              .doc(updated.subscriptionId!);

          if (newDone) {
            logger.info(
              'updateAppointment(add): increment meetingsCompleted for user={}, sub={}, delta=1',
              [updated.userId, updated.subscriptionId],
            );
            await newSubRef.update(<String, Object?>{
              'meetingsCompleted': FieldValue.increment(1),
            });
            subChanged = true;
          }

          if (newBurned) {
            logger.info(
              'updateAppointment(add): increment meetingsBurned for user={}, sub={}, delta=1',
              [updated.userId, updated.subscriptionId],
            );
            await newSubRef.update(<String, Object?>{
              'meetingsBurned': FieldValue.increment(1),
            });
            subChanged = true;
          }
        }

        if (subChanged) {
          subProvider.markChanged();
        }

        logger.info('Appointment updated (add edge-case): {}', [updated]);
        //subProvider.markChanged(); // Always notify SubProvider so sub_tab refreshes
        return;
      }

      // ---------- NORMAL UPDATE CASE ----------
      final prev = prevSnap.data() as Map<String, dynamic>;

      final AppointmentStatus prevStatus =
      _statusFromLabelSafe(prev['status'] as String?);
      final String? prevSubId = prev['subscriptionId'] as String?;

      final bool prevDone = prevStatus == AppointmentStatus.completed;
      final bool prevBurned = prevStatus == AppointmentStatus.burned;
      final bool newDone = updated.status == AppointmentStatus.completed;
      final bool newBurned = updated.status == AppointmentStatus.burned;
      final String? newSubId = updated.subscriptionId;

      // Pre-read any sub docs we might touch
      Map<String, dynamic>? prevSubData;
      Map<String, dynamic>? newSubData;

      if ((prevDone || prevBurned) && (prevSubId?.isNotEmpty ?? false)) {
        final prevSubRef = db
            .collection('users')
            .doc(updated.userId)
            .collection('subscriptions')
            .doc(prevSubId!);
        final prevSubSnap = await prevSubRef.get();
        if (prevSubSnap.exists) {
          prevSubData = prevSubSnap.data();
        }
      }

      if ((newDone || newBurned) && (newSubId?.isNotEmpty ?? false)) {
        final newSubRef = db
            .collection('users')
            .doc(updated.userId)
            .collection('subscriptions')
            .doc(newSubId!);
        final newSubSnap = await newSubRef.get();
        if (newSubSnap.exists) {
          newSubData = newSubSnap.data();
        }
      }

      // ---------- UPDATE APPOINTMENT ----------
      await apptRef.update(updated.toMap());

      // Decrement meetingsCompleted from previous if needed
      if (prevDone &&
          (prevSubId?.isNotEmpty ?? false) &&
          (!newDone || prevSubId != newSubId)) {
        if (prevSubData != null) {
          final prevSubRef = db
              .collection('users')
              .doc(updated.userId)
              .collection('subscriptions')
              .doc(prevSubId!);

          logger.info(
            'updateAppointment: decrement meetingsCompleted for user={}, sub={}, delta=-1',
            [updated.userId, prevSubId],
          );

          await prevSubRef.update(<String, Object?>{
            'meetingsCompleted': FieldValue.increment(-1),
          });

          subChanged = true;
        } else {
          logger.warn(
            'Prev sub missing during update decrement (completed): userId={}, prevSubId={}',
            [updated.userId, prevSubId],
          );
        }
      }

      // Decrement meetingsBurned from previous if needed
      if (prevBurned &&
          (prevSubId?.isNotEmpty ?? false) &&
          (!newBurned || prevSubId != newSubId)) {
        if (prevSubData != null) {
          final prevSubRef = db
              .collection('users')
              .doc(updated.userId)
              .collection('subscriptions')
              .doc(prevSubId!);

          logger.info(
            'updateAppointment: decrement meetingsBurned for user={}, sub={}, delta=-1',
            [updated.userId, prevSubId],
          );

          await prevSubRef.update(<String, Object?>{
            'meetingsBurned': FieldValue.increment(-1),
          });

          subChanged = true;
        } else {
          logger.warn(
            'Prev sub missing during update decrement (burned): userId={}, prevSubId={}',
            [updated.userId, prevSubId],
          );
        }
      }

      // Increment meetingsCompleted on new if needed
      if (newDone &&
          (newSubId?.isNotEmpty ?? false) &&
          (!prevDone || prevSubId != newSubId)) {
        if (newSubData != null) {
          final newSubRef = db
              .collection('users')
              .doc(updated.userId)
              .collection('subscriptions')
              .doc(newSubId!);

          logger.info(
            'updateAppointment: increment meetingsCompleted for user={}, sub={}, delta=1',
            [updated.userId, newSubId],
          );

          await newSubRef.update(<String, Object?>{
            'meetingsCompleted': FieldValue.increment(1),
          });

          subChanged = true;
        } else {
          logger.warn(
            'New sub missing during update increment (completed): user={}, sub={}',
            [updated.userId, newSubId],
          );
        }
      }

      // Increment meetingsBurned on new if needed
      if (newBurned &&
          (newSubId?.isNotEmpty ?? false) &&
          (!prevBurned || prevSubId != newSubId)) {
        if (newSubData != null) {
          final newSubRef = db
              .collection('users')
              .doc(updated.userId)
              .collection('subscriptions')
              .doc(newSubId!);

          logger.info(
            'updateAppointment: increment meetingsBurned for user={}, sub={}, delta=1',
            [updated.userId, newSubId],
          );

          await newSubRef.update(<String, Object?>{
            'meetingsBurned': FieldValue.increment(1),
          });

          subChanged = true;
        } else {
          logger.warn(
            'New sub missing during update increment (burned): user={}, sub={}',
            [updated.userId, newSubId],
          );
        }
      }

      if (subChanged) {
        subProvider.markChanged();
      }

      logger.info('Appointment updated: {}', [updated]);
      //subProvider.markChanged(); // Always notify SubProvider so sub_tab refreshes
    } catch (e) {
      logger.err('Error updating appointment: {}', [e]);
      rethrow;
    }
  }
  Future<bool> deleteAppointment(
      String appointmentId,
      String userId, {
        required String deletedBy,
      }) async {
    try {
      final db = FirebaseFirestore.instance;
      final apptRef = db
          .collection('users')
          .doc(userId)
          .collection('appointments')
          .doc(appointmentId);

      bool subChanged = false;

      // ---------- READ APPOINTMENT ----------
      final snap = await apptRef.get();
      if (!snap.exists) {
        logger.warn(
          'deleteAppointment: appointment not found, user={}, appt={}',
          [userId, appointmentId],
        );
        return false;
      }

      final data = snap.data() as Map<String, dynamic>;
      final AppointmentStatus status =
      _statusFromLabelSafe(data['status'] as String?);
      final String? subId = data['subscriptionId'] as String?;

      Map<String, dynamic>? subData;

      if ((status == AppointmentStatus.completed || status == AppointmentStatus.burned) &&
          (subId?.isNotEmpty ?? false)) {
        final subRef = db
            .collection('users')
            .doc(userId)
            .collection('subscriptions')
            .doc(subId!);
        final subSnap = await subRef.get();
        if (subSnap.exists) {
          subData = subSnap.data();
        }
      }

      // ---------- DELETE APPOINTMENT ----------
      await apptRef.delete();

      // ---------- UPDATE SUBSCRIPTION COUNTER ----------
      if ((subId?.isNotEmpty ?? false) && subData != null) {
        final subRef = db
            .collection('users')
            .doc(userId)
            .collection('subscriptions')
            .doc(subId!);

        if (status == AppointmentStatus.completed) {
          logger.info(
            'deleteAppointment: decrement meetingsCompleted for user={}, sub={}, delta=-1',
            [userId, subId],
          );

          await subRef.update(<String, Object?>{
            'meetingsCompleted': FieldValue.increment(-1),
          });

          subChanged = true;
        }

        if (status == AppointmentStatus.burned) {
          logger.info(
            'deleteAppointment: decrement meetingsBurned for user={}, sub={}, delta=-1',
            [userId, subId],
          );

          await subRef.update(<String, Object?>{
            'meetingsBurned': FieldValue.increment(-1),
          });

          subChanged = true;
        }
      }

      if (subChanged) {
        subProvider.markChanged();
      }

      logger.info(
        'Appointment deletedBy={}: appointmentId={}',
        [deletedBy, appointmentId],
      );
      return true;
    } catch (e) {
      logger.err('Error deleting appointment: {}', [e]);
      rethrow;
    }
  }
  Future<bool> cancelAppointment(
      String appointmentId,
      String userId, {
        required String canceledBy,
      }) async {
    try {
      final db = FirebaseFirestore.instance;
      final apptRef = db
          .collection('users')
          .doc(userId)
          .collection('appointments')
          .doc(appointmentId);

      bool subChanged = false;

      // ---------- READ APPOINTMENT ----------
      final snap = await apptRef.get();
      if (!snap.exists) {
        logger.warn(
          'cancelAppointment: appointment not found, user={}, appt={}',
          [userId, appointmentId],
        );
        return false;
      }

      final data = snap.data() as Map<String, dynamic>;
      final AppointmentStatus prevStatus =
      _statusFromLabelSafe(data['status'] as String?);
      final String? subId = data['subscriptionId'] as String?;

      Map<String, dynamic>? subData;
      final bool wasDone = prevStatus == AppointmentStatus.completed;
      final bool wasBurned = prevStatus == AppointmentStatus.burned;

      if ((wasDone || wasBurned) && (subId?.isNotEmpty ?? false)) {
        final subRef = db
            .collection('users')
            .doc(userId)
            .collection('subscriptions')
            .doc(subId!);
        final subSnap = await subRef.get();
        if (subSnap.exists) {
          subData = subSnap.data();
        }
      }

      // ---------- UPDATE APPOINTMENT STATUS ----------
      final now = Timestamp.now();
      await apptRef.update({
        'status': AppointmentStatus.canceled.label,
        'canceledBy': canceledBy,
        'canceledAt': now,
        'updateDate': now,
        'updateUser': canceledBy,
      });

      // ---------- UPDATE SUBSCRIPTION COUNTER ----------
      if ((subId?.isNotEmpty ?? false) && subData != null) {
        final subRef = db
            .collection('users')
            .doc(userId)
            .collection('subscriptions')
            .doc(subId!);

        if (wasDone) {
          logger.info(
            'cancelAppointment: decrement meetingsCompleted for user={}, sub={}, delta=-1',
            [userId, subId],
          );

          await subRef.update(<String, Object?>{
            'meetingsCompleted': FieldValue.increment(-1),
          });

          subChanged = true;
        }

        if (wasBurned) {
          logger.info(
            'cancelAppointment: decrement meetingsBurned for user={}, sub={}, delta=-1',
            [userId, subId],
          );

          await subRef.update(<String, Object?>{
            'meetingsBurned': FieldValue.increment(-1),
          });

          subChanged = true;
        }
      }

      if (subChanged) {
        subProvider.markChanged();
      }

      logger.info(
        'Appointment canceledBy={}, appointmentId={}',
        [canceledBy, appointmentId],
      );
      return true;
    } catch (e) {
      logger.err('Error canceling appointment: {}', [e]);
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
      final usersCollection = FirebaseFirestore.instance.collection('users');
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

      // Fetch user data for all appointments
      final fetchedAppointments = await Future.wait(appointmentsMap.values.map((appointment) async {
        final userDoc = await usersCollection.doc(appointment.userId).get();
        if (userDoc.exists) {
          appointment.user = UserModel.fromDocument(userDoc);
        }
        return appointment;
      }).toList());

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
}
