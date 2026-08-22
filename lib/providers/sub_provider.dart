import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/logger.dart';
import '../models/subs_model.dart';
import '../models/filter_params.dart';

final Logger logger = Logger.forClass(SubProvider);

/// Provides subscription management functionality, including CRUD operations
/// for user subscription packages. Implements ChangeNotifier pattern for state management.
class SubProvider extends ChangeNotifier {
  bool _subChanged = false;

  bool get subChanged => _subChanged;
  void resetSubChanged() => _subChanged = false;

  /// Call this after an external transaction changed a subscription,
  /// so UI can refresh filtered lists etc.
  void markChanged() { //zararı yok kalabilir.
    if(_subChanged)
      return;
    _subChanged = true;
    logger.info('** SUB MARK CHANGED.**');
    notifyListeners();
  }

  /// Adjusts 'meetingsCompleted' by [delta] atomically inside the caller's Firestore [tx].
  /// Clamps into [0, totalMeetings].
// SubProvider additions:

  /// Atomically adjusts 'meetingsCompleted' by [delta].
  /// If you pass [prefetched], it will NOT call tx.get, preventing "read after write".
  Future<void> adjustMeetingsCompletedInTx({
    required Transaction tx,
    required String userId,
    required String subscriptionId,
    required int delta,
    Map<String, dynamic>? prefetched,
  }) async {
    if (delta == 0) return;

    final subRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('subscriptions')
        .doc(subscriptionId);

    Map<String, dynamic>? data = prefetched;
    if (data == null) {
      final snap = await tx.get(subRef);
      if (!snap.exists) {
        logger.warn('Sub not found for counter update: user={}, sub={}', [userId, subscriptionId]);
        return;
      }
      data = snap.data() as Map<String, dynamic>;
    }

    final rawCompleted = data['meetingsCompleted'];
    final rawTotal = data['totalMeetings'];

    final int currentCompleted = rawCompleted is int ? rawCompleted : int.tryParse('$rawCompleted') ?? 0;
    final int totalMeetings   = rawTotal     is int ? rawTotal     : int.tryParse('$rawTotal')     ?? 0;

    final int newCompleted = (currentCompleted + delta).clamp(0, totalMeetings);
    tx.update(subRef, {'meetingsCompleted': newCompleted});

    logger.info('meetingsCompleted adjusted: user={}, sub={}, delta={}, from {} to {}',
        [userId, subscriptionId, delta, currentCompleted, newCompleted]);
  }

  /// Fetches subscriptions for a user
  /// 
  /// @param userId The ID of the user whose subscriptions to fetch
  /// @param showAllSubscriptions If true, returns all subscriptions regardless of status; 
  ///        if false, returns only active subscriptions
  /// @param filterParams Optional filter parameters for Firebase-side filtering
  /// 
  /// @return A list of SubscriptionModel objects representing the user's subscriptions
  Future<List<SubscriptionModel>> fetchSubscriptions({
    required String userId,
    required bool showAllSubscriptions,
    SubscriptionFilterParams? filterParams,
  }) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('subscriptions');

      // Apply filter parameters if provided
      if (filterParams != null) {
        // Status filter
        if (filterParams.status != null) {
          query = query.where('status', isEqualTo: filterParams.status);
        }

        // Date range filter (on startDate)
        if (filterParams.dateRange != null) {
          query = query
              .where('startDate', isGreaterThanOrEqualTo: filterParams.dateRange!.start)
              .where('startDate', isLessThanOrEqualTo: DateTime(
                filterParams.dateRange!.end.year,
                filterParams.dateRange!.end.month,
                filterParams.dateRange!.end.day,
                23,
                59,
                59,
              ));
        }
      }
      
      query = query.orderBy('startDate', descending: true);

      final snapshot = await query.get();
      // Convert raw document data to SubscriptionModel objects
      var list = snapshot.docs
          .map((doc) => SubscriptionModel.fromDocument(doc))
          .toList();
      
      // Apply client-side search filter if needed
      if (filterParams?.searchQuery != null && filterParams!.searchQuery!.isNotEmpty) {
        final searchLower = filterParams.searchQuery!.toLowerCase();
        list = list.where((s) {
          return s.packageName.toLowerCase().contains(searchLower);
        }).toList();
      }
      
      logger.info('Fetched {} subscriptions with filters: {}', [list.length, filterParams?.toDebugMap()]);
      return list;
    } catch (e) {
      logger.err('Error fetching subscriptions for userId={}: {}', [userId, e]);
      rethrow;
    }
  }

  /// Adds a new subscription for a user
  /// 
  /// @param userId The ID of the user to add the subscription for
  /// @param subscriptionData The raw subscription data to add
  /// 
  /// @return The ID of the newly created subscription
  Future<String> addSubscription({
    required String userId,
    required Map<String, dynamic> subscriptionData,
  }) async {
    try {
      // Generate a new document ID
      final subscriptionId = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('subscriptions')
          .doc()
          .id;

      // Add the IDs to the subscription data map
      final Map<String, dynamic> finalData = {
        ...subscriptionData,
        'subscriptionId': subscriptionId,
        'userId': userId,
      };

      // Save the raw data directly to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('subscriptions')
          .doc(subscriptionId)
          .set(finalData);

      logger.info('New subscription added: {}', [finalData]);
      _subChanged = true;
      notifyListeners();
      
      return subscriptionId;
    } catch (e) {
      logger.err('Error adding subscription for userId={}: {}', [userId, e]);
      rethrow;
    }
  }

  /// Updates an existing subscription
  /// 
  /// @param userId The ID of the user whose subscription to update
  /// @param subscriptionId The ID of the subscription to update
  /// @param updateData The raw data to update in the subscription
  /// 
  /// @return A boolean indicating whether the update was successful
  Future<bool> updateSubscription({
    required String userId,
    required String subscriptionId,
    required Map<String, dynamic> updateData,
  }) async {
    try {
      // Update the subscription data directly without creating a model object
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('subscriptions')
          .doc(subscriptionId)
          .update(updateData);

      logger.info('Subscription updated: {}', [subscriptionId]);
      _subChanged = true;
      notifyListeners();
      return true;
    } catch (e) {
      logger.err('Error updating subscription id={} for userId={}: {}', 
          [subscriptionId, userId, e]);
      rethrow;
    }
  }

  /// Checks if a subscription has related data (appointments, payments, etc.)
  /// 
  /// @param userId The ID of the user whose subscription to check
  /// @param subscriptionId The ID of the subscription to check
  /// 
  /// @return A map with boolean values indicating if related data exists and counts
  // Future<Map<String, dynamic>> checkSubscriptionRelatedData({
  //   required String userId,
  //   required String subscriptionId,
  // }) async {
  //   try {
  //     final result = {
  //       'hasAppointments': false,
  //       'appointmentCount': 0,
  //       'hasPayments': false,
  //       'paymentCount': 0,
  //       'hasDietPlans': false,
  //       'dietPlanCount': 0,
  //       'canDelete': true,
  //     };
  //
  //     // Check appointments
  //     final appointmentsSnap = await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(userId)
  //         .collection('appointments')
  //         .where('subscriptionId', isEqualTo: subscriptionId)
  //         .count()
  //         .get();
  //
  //     result['appointmentCount'] = appointmentsSnap.count;
  //     result['hasAppointments'] = appointmentsSnap.count > 0;
  //
  //     // Check payments
  //     final paymentsSnap = await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(userId)
  //         .collection('payments')
  //         .where('subscriptionId', isEqualTo: subscriptionId)
  //         .count()
  //         .get();
  //
  //     result['paymentCount'] = paymentsSnap.count;
  //     result['hasPayments'] = paymentsSnap.count > 0;
  //
  //     // Check diet plans
  //     final dietPlansSnap = await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(userId)
  //         .collection('dietlists')
  //         .where('subscriptionId', isEqualTo: subscriptionId)
  //         .count()
  //         .get();
  //
  //     result['dietPlanCount'] = dietPlansSnap.count;
  //     result['hasDietPlans'] = dietPlansSnap.count > 0;
  //
  //     // Determine if the subscription can be safely deleted
  //     result['canDelete'] = !result['hasAppointments'] &&
  //                          !result['hasPayments'] &&
  //                          !result['hasDietPlans'];
  //
  //     return result;
  //   } catch (e) {
  //     logger.err('Error checking related data for subscription id={} for userId={}: {}',
  //         [subscriptionId, userId, e]);
  //     rethrow;
  //   }
  // }

  /// Deletes a subscription together with every record linked to it.
  ///
  /// Appointments and payments point back to their subscription through the
  /// `subscriptionId` foreign key (see [AppointmentModel] / [PaymentModel]), so
  /// the relationship is resolved by querying those collections rather than by
  /// duplicating references on the subscription document. Removing a
  /// subscription cascade-deletes its linked appointments and payments so no
  /// orphaned records are left behind.
  ///
  /// @param userId The ID of the user whose subscription to delete
  /// @param subscriptionId The ID of the subscription to delete
  ///
  /// @return A boolean indicating whether the deletion was successful
  Future<bool> deleteSubscription({
    required String userId,
    required String subscriptionId,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(userId);

      // Kick off both lookups in parallel: everything linked to this
      // subscription is found via the `subscriptionId` foreign key.
      final appointmentsFuture = userRef
          .collection('appointments')
          .where('subscriptionId', isEqualTo: subscriptionId)
          .get();
      final paymentsFuture = userRef
          .collection('payments')
          .where('subscriptionId', isEqualTo: subscriptionId)
          .get();

      final appointmentsSnap = await appointmentsFuture;
      final paymentsSnap = await paymentsFuture;

      // Cascade-delete the subscription and all of its linked records.
      final refsToDelete = <DocumentReference<Map<String, dynamic>>>[
        ...appointmentsSnap.docs.map((doc) => doc.reference),
        ...paymentsSnap.docs.map((doc) => doc.reference),
        userRef.collection('subscriptions').doc(subscriptionId),
      ];
      await _commitDeletesInChunks(db, refsToDelete);

      logger.info(
        'Subscription {} deleted with {} linked appointment(s) and {} linked payment(s)',
        [subscriptionId, appointmentsSnap.docs.length, paymentsSnap.docs.length],
      );
      _subChanged = true;
      notifyListeners();
      return true;
    } catch (e) {
      logger.err('Error deleting subscription id={} for userId={}: {}', 
          [subscriptionId, userId, e]);
      rethrow;
    }
  }

  /// Deletes [refs] using Firestore write batches, splitting them so each batch
  /// stays within Firestore's 500-write limit.
  Future<void> _commitDeletesInChunks(
    FirebaseFirestore db,
    List<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    if (refs.isEmpty) return;
    const int maxPerBatch = 450; // safety margin below Firestore's 500 cap
    for (var start = 0; start < refs.length; start += maxPerBatch) {
      final end = (start + maxPerBatch < refs.length)
          ? start + maxPerBatch
          : refs.length;
      final batch = db.batch();
      for (final ref in refs.sublist(start, end)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  /// Fetches a subscription's package name by its ID
  ///
  /// @param userId The ID of the user whose subscription to fetch
  /// @param subscriptionId The ID of the subscription to fetch
  ///
  /// @return The package name of the subscription, or null if not found
  Future<String?> getSubscriptionPackageName({ //????
    required String userId,
    required String subscriptionId,
  }) async {
    try {
      if (subscriptionId.isEmpty) return null;
      
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('subscriptions')
          .doc(subscriptionId)
          .get();
      
      if (!docSnapshot.exists) return null;
      
      final data = docSnapshot.data();
      return data?['packageName'] as String?;
    } catch (e) {
      logger.err('Error fetching subscription package name for userId={}, subscriptionId={}: {}', 
          [userId, subscriptionId, e]);
      return null;
    }
  }

  /// Moves a subscription's `amountPaid` by [delta], atomically.
  ///
  /// Callers used to read the current total — often from a stale in-memory
  /// subscription model — add their own amount and write the result back. Two
  /// payments recorded around the same time then overwrote each other and the
  /// package's paid total silently drifted. The delta is applied against the
  /// stored value instead, and the total is never pushed below zero.
  ///
  /// Returns whether the adjustment was applied.
  Future<bool> adjustAmountPaid({
    required String userId,
    required String subscriptionId,
    required double delta,
  }) async {
    if (subscriptionId.isEmpty || delta == 0) return true;

    try {
      final subRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('subscriptions')
          .doc(subscriptionId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(subRef);
        if (!snap.exists) {
          logger.warn('Sub not found for amountPaid update: user={}, sub={}',
              [userId, subscriptionId]);
          return;
        }

        final raw = snap.data()?['amountPaid'];
        final double current =
            raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
        final double next = (current + delta).clamp(0, double.infinity).toDouble();

        tx.update(subRef, {'amountPaid': next});
        logger.info(
          'amountPaid adjusted: user={}, sub={}, delta={}, from {} to {}',
          [userId, subscriptionId, delta, current, next],
        );
      });

      _subChanged = true;
      notifyListeners();
      return true;
    } catch (e) {
      logger.err('Error adjusting amountPaid for userId={}, subscriptionId={}: {}',
          [userId, subscriptionId, e]);
      return false;
    }
  }

  /// Deletes a subscription and optionally its related data
  /// 
  /// @param userId The ID of the user whose subscription to delete
  /// @param subscriptionId The ID of the subscription to delete
  /// @param deleteRelatedData If true, also deletes related data (appointments, payments, etc.)
  /// 
  /// @return A boolean indicating whether the deletion was successful
  Future<bool> deleteSubscriptionWithRelatedData({
    required String userId,
    required String subscriptionId,
    required bool deleteRelatedData,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(userId);
      final subRef = userRef.collection('subscriptions').doc(subscriptionId);

      if (deleteRelatedData) {
        // The three lookups share nothing, so they are issued together rather
        // than one after the other.
        final appointmentsFuture = userRef
            .collection('appointments')
            .where('subscriptionId', isEqualTo: subscriptionId)
            .get();
        final paymentsFuture = userRef
            .collection('payments')
            .where('subscriptionId', isEqualTo: subscriptionId)
            .get();
        final dietPlansFuture = userRef
            .collection('dietlists')
            .where('subscriptionId', isEqualTo: subscriptionId)
            .get();

        final appointmentsSnap = await appointmentsFuture;
        final paymentsSnap = await paymentsFuture;
        final dietPlansSnap = await dietPlansFuture;

        // Chunked: a single batch would throw once a subscription had more than
        // 500 linked documents.
        await _commitDeletesInChunks(db, <DocumentReference<Map<String, dynamic>>>[
          ...appointmentsSnap.docs.map((doc) => doc.reference),
          ...paymentsSnap.docs.map((doc) => doc.reference),
          ...dietPlansSnap.docs.map((doc) => doc.reference),
          subRef,
        ]);
      } else {
        // Delete just the subscription
        await subRef.delete();
      }

      logger.info('Subscription deleted: {}', [subscriptionId]);
      _subChanged = true;
      notifyListeners();
      return true;
    } catch (e) {
      logger.err('Error deleting subscription id={} for userId={}: {}', 
          [subscriptionId, userId, e]);
      rethrow;
    }
  }
} 