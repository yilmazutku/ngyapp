import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/customer_summary_row.dart';
import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../models/user_model.dart';

final Logger logger = Logger.forClass(CustomerSummaryProvider);

/// Aggregates, for every non-admin customer that owns an *active*
/// subscription, the data needed by the "Danışanlar Özet" overview page:
/// last payment (date / amount / type), the active package name, and up to
/// [CustomerSummaryRow.maxSeans] session (appointment) dates.
///
/// All Firestore access lives here (per project provider convention); the UI
/// only renders the returned [CustomerSummaryRow]s.
class CustomerSummaryProvider extends ChangeNotifier {
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');
  final NumberFormat _amountFormat = NumberFormat('#,##0.##', 'tr_TR');

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      FirebaseFirestore.instance.collection('users');

  /// Builds the overview rows for every customer with at least one active
  /// subscription. Customers without an active subscription are skipped.
  /// Rows are sorted alphabetically by full name.
  Future<List<CustomerSummaryRow>> fetchActiveCustomerSummaries() async {
    try {
      // 1) Start from all non-admin customers.
      final customersSnap =
          await _usersRef.where('role', isEqualTo: 'customer').get();

      final customers = customersSnap.docs
          .map((doc) => UserModel.fromDocument(doc))
          .toList();

      logger.info('Building summary for {} customer(s)', [customers.length]);

      // 2) Resolve each customer in parallel; null => no active subscription.
      final rows = await Future.wait(
        customers.map(_buildRowForCustomer),
      );

      final result = rows.whereType<CustomerSummaryRow>().toList()
        ..sort((a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

      logger.info('Summary built: {} customer(s) with active subscription',
          [result.length]);
      return result;
    } catch (e) {
      logger.err('Error building customer summaries: {}', [e]);
      rethrow;
    }
  }

  /// Returns a row for [user] if they have an active subscription, otherwise
  /// null. Per-section failures degrade to "Hata" cells rather than dropping
  /// the whole customer.
  Future<CustomerSummaryRow?> _buildRowForCustomer(UserModel user) async {
    final SubscriptionModel? activeSub = await _findActiveSubscription(user.userId);
    if (activeSub == null) return null;

    final fullName = '${user.name} ${user.surname}'.trim();

    final dosyaNo = (user.dosyaNo != null && user.dosyaNo!.trim().isNotEmpty)
        ? SummaryCell(user.dosyaNo!.trim())
        : const SummaryCell.empty();

    final packageInfo = activeSub.packageName.trim().isNotEmpty
        ? SummaryCell(activeSub.packageName.trim())
        : const SummaryCell.error();

    final payment = await _resolveLastPayment(user.userId);
    final seans = await _resolveSeans(user.userId, activeSub.subscriptionId);

    return CustomerSummaryRow(
      userId: user.userId,
      dosyaNo: dosyaNo,
      fullName: fullName.isEmpty ? '(İsimsiz)' : fullName,
      paymentDate: payment.date,
      paymentAmount: payment.amount,
      paymentType: payment.type,
      packageInfo: packageInfo,
      seans: seans,
    );
  }

  /// Finds the customer's active subscription (most recent by start date when
  /// several are active). Returns null when none is active.
  Future<SubscriptionModel?> _findActiveSubscription(String userId) async {
    try {
      final snap = await _usersRef
          .doc(userId)
          .collection('subscriptions')
          .where('status', isEqualTo: SubActiveStatus.active.label)
          .get();

      if (snap.docs.isEmpty) return null;

      final subs = <SubscriptionModel>[];
      for (final doc in snap.docs) {
        try {
          subs.add(SubscriptionModel.fromDocument(doc));
        } catch (e) {
          logger.warn('Skipping malformed subscription {} for user {}: {}',
              [doc.id, userId, e]);
        }
      }
      if (subs.isEmpty) return null;

      subs.sort((a, b) => b.startDate.compareTo(a.startDate));
      return subs.first;
    } catch (e) {
      logger.err('Error fetching active subscription for user {}: {}',
          [userId, e]);
      return null;
    }
  }

  /// Resolves the most recent completed payment into display cells.
  /// - No completed payment => empty cells (nothing to show yet).
  /// - Completed payment with no payment date => "Hata" for the date cell.
  Future<_PaymentCells> _resolveLastPayment(String userId) async {
    try {
      final snap =
          await _usersRef.doc(userId).collection('payments').get();

      final completed = <PaymentModel>[];
      for (final doc in snap.docs) {
        try {
          final p = PaymentModel.fromDocument(doc);
          if (p.status == PaymentStatus.completed) completed.add(p);
        } catch (e) {
          logger.warn('Skipping malformed payment {} for user {}: {}',
              [doc.id, userId, e]);
        }
      }

      if (completed.isEmpty) return const _PaymentCells.empty();

      // Latest first, using createDate as a fallback ordering key so payments
      // with a missing paymentDate still participate instead of vanishing.
      completed.sort((a, b) => (b.paymentDate ?? b.createDate)
          .compareTo(a.paymentDate ?? a.createDate));

      final last = completed.first;

      final dateCell = last.paymentDate != null
          ? SummaryCell(_dateFormat.format(last.paymentDate!))
          : const SummaryCell.error();

      final amountCell = SummaryCell(_amountFormat.format(last.amount));

      final typeCell = SummaryCell(last.paymentType.label);

      return _PaymentCells(date: dateCell, amount: amountCell, type: typeCell);
    } catch (e) {
      logger.err('Error resolving last payment for user {}: {}', [userId, e]);
      return const _PaymentCells.error();
    }
  }

  /// Resolves the session (seans) date cells for the active subscription.
  /// Non-deleted appointments linked to [subscriptionId] are used, ordered by
  /// date. Missing/`null` appointment dates become "Hata" cells. The returned
  /// list always has [CustomerSummaryRow.maxSeans] entries (empty-padded).
  Future<List<SummaryCell>> _resolveSeans(
      String userId, String subscriptionId) async {
    const int max = CustomerSummaryRow.maxSeans;
    try {
      final snap = await _usersRef
          .doc(userId)
          .collection('appointments')
          .where('subscriptionId', isEqualTo: subscriptionId)
          .get();

      final validDates = <DateTime>[];
      int nullDateCount = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        // Match the app convention: only "live" appointments (isDeleted null).
        if (data['isDeleted'] != null) continue;

        final rawDate = data['appointmentDateTime'];
        if (rawDate is Timestamp) {
          validDates.add(rawDate.toDate());
        } else {
          // Field expected but missing/null => surface as an error cell.
          nullDateCount++;
        }
      }

      validDates.sort((a, b) => a.compareTo(b));

      // Keep the most recent [max] when a package has more sessions than slots.
      final trimmed = validDates.length > max
          ? validDates.sublist(validDates.length - max)
          : validDates;

      final cells = <SummaryCell>[
        ...trimmed.map((d) => SummaryCell(_dateFormat.format(d))),
      ];

      // Append error cells for appointments whose date is broken/null.
      for (int i = 0; i < nullDateCount && cells.length < max; i++) {
        cells.add(const SummaryCell.error());
      }

      // Pad remaining slots so every row has a fixed column count.
      while (cells.length < max) {
        cells.add(const SummaryCell.empty());
      }

      return cells;
    } catch (e) {
      logger.err('Error resolving seans for user {} sub {}: {}',
          [userId, subscriptionId, e]);
      return List<SummaryCell>.filled(max, const SummaryCell.error());
    }
  }
}

/// Internal holder for the three payment-related cells.
class _PaymentCells {
  final SummaryCell date;
  final SummaryCell amount;
  final SummaryCell type;

  const _PaymentCells({
    required this.date,
    required this.amount,
    required this.type,
  });

  const _PaymentCells.empty()
      : date = const SummaryCell.empty(),
        amount = const SummaryCell.empty(),
        type = const SummaryCell.empty();

  const _PaymentCells.error()
      : date = const SummaryCell.error(),
        amount = const SummaryCell.error(),
        type = const SummaryCell.error();
}
