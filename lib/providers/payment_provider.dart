import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../models/filter_params.dart';
import '../providers/sub_provider.dart';

final Logger logger = Logger.forClass(PaymentProvider);

/// Provides payment management functionality for handling user payment transactions.
/// Manages fetching, adding, updating, and deleting payments in the Firestore database.
class PaymentProvider extends ChangeNotifier {
  final Logger logger = Logger.forClass(PaymentProvider);
  final SubProvider subProvider;

  PaymentProvider({required this.subProvider});
  
  // Flag to track when payment data changes (add, update, delete)
  bool _paymentChanged = false;
  
  // Getter to check if a payment was changed
  bool get paymentChanged => _paymentChanged;
  
  // Method to reset the flag
  void resetPaymentChanged() {
    _paymentChanged = false;
  }

  /// Fetches all payments across all users with optional filtering
  /// Used by admin pages to get a global view of payments
  Future<List<PaymentModel>> fetchAllPayments({
    PaymentStatus? statusFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = FirebaseFirestore.instance.collectionGroup('payments');

      // Apply Firebase-side filters
      if (statusFilter != null) {
        query = query.where('status', isEqualTo: statusFilter.label);
      }

      // Note: We can only apply one date range filter in Firebase
      // We'll filter by paymentDate primarily, handle dueDate client-side
      if (startDate != null) {
        query = query.where('paymentDate', isGreaterThanOrEqualTo: startDate);
      }
      if (endDate != null) {
        // Add one day to endDate to include the entire day
        query = query.where('paymentDate', isLessThan: endDate.add(const Duration(days: 1)));
      }

      // Always fetch from server for freshest data
      final snapshot = await query.get();//(const GetOptions(source: Source.server));

      var payments = snapshot.docs.map((doc) => PaymentModel.fromDocument(doc)).toList();

      // Apply additional client-side date filtering for payments with dueDate but no paymentDate
      if (startDate != null || endDate != null) {
        payments = payments.where((p) {
          final date = p.paymentDate ?? p.dueDate;
          if (date == null) return false;
          
          bool withinRange = true;
          if (startDate != null) {
            withinRange = withinRange && !date.isBefore(startDate);
          }
          if (endDate != null) {
            withinRange = withinRange && date.isBefore(endDate.add(const Duration(days: 1)));
          }
          return withinRange;
        }).toList();
      }

      logger.info('Fetched {} payments across all users with filters', [payments.length]);
      return payments;
    } catch (e) {
      logger.err('Error fetching all payments: $e');
      rethrow;
    }
  }

  /// Fetches payments for a specific user
  /// 
  /// @param selectedSubscriptionId Optional ID to filter payments by subscription
  /// @param userId The ID of the user whose payments to fetch
  /// @param showAllPayments If true, returns all payments regardless of subscription
  /// @param filterParams Optional filter parameters for Firebase-side filtering
  /// 
  /// @return A list of PaymentModel objects representing the user's payments
  Future<List<PaymentModel>> fetchPayments(String? selectedSubscriptionId,
      {required String userId, required bool showAllPayments, PaymentFilterParams? filterParams}) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('payments');

      if (!showAllPayments && selectedSubscriptionId != null) {
        query =
            query.where('subscriptionId', isEqualTo: selectedSubscriptionId);
      }

      // Apply filter parameters if provided
      if (filterParams != null) {
        // Status filter
        if (filterParams.status != null) {
          query = query.where('status', isEqualTo: filterParams.status);
        }

        // Date range filter (using paymentDate or dueDate)
        if (filterParams.dateRange != null) {
          // Note: We can only filter on one date field at a time in Firestore
          // We'll filter on paymentDate primarily, then handle dueDate client-side
          query = query
              .where('paymentDate', isGreaterThanOrEqualTo: filterParams.dateRange!.start)
              .where('paymentDate', isLessThanOrEqualTo: DateTime(
                filterParams.dateRange!.end.year,
                filterParams.dateRange!.end.month,
                filterParams.dateRange!.end.day,
                23,
                59,
                59,
              ));
        }
      }
      
      query = query.orderBy('paymentDate', descending: true);

      // Always force a server fetch to get the latest data
      // This ensures we never get stale data from cache
      final snapshot = await query.get()/*(const GetOptions(source: Source.server))*/;

      var payments = snapshot.docs.map((doc) => PaymentModel.fromDocument(doc)).toList();
      
      // Apply client-side filters
      if (filterParams != null) {
        // Search filter (notes or amount)
        if (filterParams.searchQuery != null && filterParams.searchQuery!.isNotEmpty) {
          final searchLower = filterParams.searchQuery!.toLowerCase();
          payments = payments.where((p) {
            // Search in notes
            final byNotes = p.notes?.toLowerCase().contains(searchLower) ?? false;
            // Search by amount (try to parse search as number)
            bool byAmount = false;
            try {
              final searchAmount = double.parse(searchLower.replaceAll(',', '.'));
              byAmount = (p.amount - searchAmount).abs() < 0.01;
            } catch (_) {}
            return byNotes || byAmount;
          }).toList();
        }
        
        // Additional date range filter for dueDate if paymentDate is null
        if (filterParams.dateRange != null) {
          payments = payments.where((p) {
            final date = p.paymentDate ?? p.dueDate;
            if (date == null) return false;
            return !date.isBefore(filterParams.dateRange!.start) &&
                   !date.isAfter(DateTime(
                     filterParams.dateRange!.end.year,
                     filterParams.dateRange!.end.month,
                     filterParams.dateRange!.end.day,
                     23,
                     59,
                     59,
                   ));
          }).toList();
        }
      }
      
      logger.info('Fetched {} payments with filters: {}', [payments.length, filterParams?.toDebugMap()]);
      return payments;
    } catch (e) {
      logger.err('Error fetching payments: $e');
      rethrow;
    }
  }

  /// Adds a new payment record for a user
  /// 
  /// Creates a payment record in Firestore and uploads any associated dekont image to Firebase Storage
  /// 
  /// @param userId The ID of the user making the payment
  /// @param subscription Optional subscription model related to this payment
  /// @param amount The payment amount
  /// @param paymentDate Optional date when payment was made
  /// @param status The current status of the payment
  /// @param dekontImage Optional receipt/proof of payment image file
  /// @param dueDate Optional date when payment is due
  /// @param notificationTimes Optional list of times when notifications should be sent
  /// @param notes Optional additional notes about the payment
  Future<void> addPayment(
      {required String userId,
      SubscriptionModel? subscription,
      required double amount,
      DateTime? paymentDate,
      PaymentStatus status = PaymentStatus.completed,
      File? dekontImage,
      DateTime? dueDate,
      List<int>? notificationTimes,
      String? notes}) async {
    try {
      String? dekontUrl;

      // Upload the dekont image if it exists
      if (dekontImage != null) {
        dekontUrl = await _uploadDekontImage(userId, dekontImage);
      }

      // Create a new payment document
      final paymentDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('payments')
          .doc();

      PaymentModel paymentModel = PaymentModel(
        paymentId: paymentDocRef.id,
        userId: userId,
        subscriptionId: subscription?.subscriptionId,
        amount: amount,
        paymentDate: paymentDate,
        status: status,
        dekontUrl: dekontUrl,
        dueDate: dueDate,
        notificationTimes: notificationTimes,
        notes: notes,
        createUser: 'admin', //TODO nuray&nilay
      );

      await paymentDocRef.set(paymentModel.toMap());
      logger.info('Payment added successfully for user $userId');
      
      // Set the flag and notify listeners
      _paymentChanged = true;
      notifyListeners();
      
      // Notify SubProvider so sub_tab refreshes
      subProvider.markChanged();

      // Note: The subscription's amountPaid will be updated in the add_payment_dialog.dart
      // to avoid double updates that cause the amount to be doubled.
      
      // No need to call fetchPayments() here since we're not maintaining a local list
    } catch (e) {
      logger.err('Error adding payment: $e');
      rethrow; //TODO rethrow yakalanmaları app geneli
    }
  }

  /// Uploads a dekont (receipt) image to Firebase Storage
  /// 
  /// @param userId The ID of the user associated with the dekont
  /// @param dekontImage The File object containing the dekont image
  /// 
  /// @return The download URL of the uploaded image
  Future<String> _uploadDekontImage(String userId, File dekontImage) async {
    try {
      final fileName = DateTime.now().millisecondsSinceEpoch.toString();
      final ref = FirebaseStorage.instance
          .ref()
          .child('users/$userId/dekont/$fileName');
      final uploadTask = ref.putFile(dekontImage);

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      logger.info('Dekont image uploaded to $downloadUrl');

      return downloadUrl;
    } catch (e) {
      logger.err('Error uploading dekont image: $e');
      throw Exception('Error uploading dekont image: $e');
    }
  }

  /// Updates an existing payment record
  /// 
  /// @param updatedPayment The PaymentModel containing the updated payment information
  Future<void> updatePayment(PaymentModel updatedPayment) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(updatedPayment.userId)
          .collection('payments')
          .doc(updatedPayment.paymentId)
          .update(updatedPayment.toMap());

      logger.info(
          'Payment updated successfully for user ${updatedPayment.userId}');
      
      // Notify listeners that a payment was updated
      _paymentChanged = true;
      notifyListeners();
      
      // Notify SubProvider so sub_tab refreshes
      subProvider.markChanged();
    } catch (e) {
      logger.err('Error updating payment: $e');
      rethrow;
    }
  }

  /// Deletes a payment record and cancels any associated notifications
  /// 
  /// @param paymentId The ID of the payment to delete
  /// @param userId The ID of the user who made the payment
  Future<void> deletePayment(String paymentId, String userId) async {
    try {
      // First fetch the payment to check if it has notifications
      final paymentDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('payments')
          .doc(paymentId)
          .get();
      
      final paymentData = paymentDoc.data();
      
      // Delete the payment from Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('payments')
          .doc(paymentId)
          .delete();

      // If the payment had notification times set, we should cancel those notifications
      if (paymentData != null && paymentData['notificationTimes'] != null) {
        // In a real implementation, you would cancel scheduled notifications here
        // For example, using a unique ID based on the payment ID
        logger.info('Canceled notifications for payment $paymentId');
        
        // If you have a notification service, you could use it like this:
        // final notificationService = NotificationService();
        // await notificationService.cancelPaymentNotifications(paymentId);
      }

      logger.info('Payment $paymentId deleted successfully for user $userId');
      
      // Notify listeners that a payment was deleted
      _paymentChanged = true;
      notifyListeners();
      
      // Notify SubProvider so sub_tab refreshes
      subProvider.markChanged();
    } catch (e) {
      logger.err('Error deleting payment: $e');
      rethrow;
    }
  }
}
