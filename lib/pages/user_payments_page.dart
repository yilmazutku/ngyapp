import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/payment_model.dart';
import '../models/logger.dart';
import '../providers/payment_provider.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';

/// A page that displays a user's payments, grouped as overdue, then planned,
/// then completed, newest first inside each group. No filters: the client is
/// looking at their own handful of payments, not searching a ledger.
class UserPaymentsPage extends StatefulWidget {
  final String userId;

  const UserPaymentsPage({
    super.key,
    required this.userId,
  });

  @override
  State<UserPaymentsPage> createState() => _UserPaymentsPageState();
}

class _UserPaymentsPageState extends State<UserPaymentsPage> {
  final Logger _logger = Logger.forClass(UserPaymentsPage);

  /// The user's payments, already ordered for display by [_sortForDisplay].
  List<PaymentModel> _payments = [];

  /// Whether we're loading data (show a spinner).
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _logger.info('Initializing UserPaymentsPage for userId=${widget.userId}.');
    _fetchUserPayments();
  }

  // --------------------------------------------------
  // Data Loading
  // --------------------------------------------------

  /// Fetch user payments from PaymentProvider.
  /// If there's an error, shows an error dialog in Turkish.
  Future<void> _fetchUserPayments() async {
    setState(() => _isLoading = true);

    final paymentProvider =
        Provider.of<PaymentProvider>(context, listen: false);

    try {
      final payments = await paymentProvider.fetchPayments(
        null,
        userId: widget.userId,
        showAllPayments: true,
      );
      _logger.info(
          'Fetched ${payments.length} payments for user ${widget.userId}.');

      if (!mounted) return;
      setState(() {
        _payments = _sortForDisplay(payments);
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      _logger.err('Error fetching payments: {}', [error]);
      _logger.err('Stack trace: {}', [stackTrace]);

      if (!mounted) return;
      setState(() => _isLoading = false);
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Ödemeler alınırken bir hata oluştu.',
      );
    }
  }

  // --------------------------------------------------
  // Sorting
  // --------------------------------------------------

  /// Orders payments for display: overdue first, then planned, then completed,
  /// and newest first inside each group.
  List<PaymentModel> _sortForDisplay(List<PaymentModel> payments) {
    final sorted = List<PaymentModel>.from(payments);

    sorted.sort((a, b) {
      final scoreA = _getStatusScore(a);
      final scoreB = _getStatusScore(b);

      // Compare group scores first: Overdue (0) < Planned (1) < Completed (2).
      if (scoreA != scoreB) {
        return scoreA.compareTo(scoreB);
      }

      // If same group, compare by date
      final dateA = a.status == PaymentStatus.completed
          ? (a.paymentDate ?? DateTime.fromMillisecondsSinceEpoch(0))
          : (a.dueDate ?? DateTime.fromMillisecondsSinceEpoch(0));

      final dateB = b.status == PaymentStatus.completed
          ? (b.paymentDate ?? DateTime.fromMillisecondsSinceEpoch(0))
          : (b.dueDate ?? DateTime.fromMillisecondsSinceEpoch(0));

      // Newest first: August's payments belong above July's.
      return dateB.compareTo(dateA);
    });

    return sorted;
  }

  /// Returns an integer that represents the "priority" of the payment.
  /// 0 = Overdue, 1 = Planned, 2 = Completed
  int _getStatusScore(PaymentModel p) {
    // Day-granularity: a payment due today is not overdue yet (see isOverdue).
    if (p.isOverdue) return 0; // Overdue first
    if (p.status == PaymentStatus.planned) return 1; // Planned next
    return 2; // Completed last
  }

  // --------------------------------------------------
  // Build Methods
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _logger.info('Building UserPaymentsPage UI for userId=${widget.userId}.');
    return Scaffold(
      appBar: AppBarWithBack(
        title: 'Ödemelerim',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildPaymentsList(),
    );
  }

  /// Builds the scrollable list of payments. If empty, show a placeholder message.
  Widget _buildPaymentsList() {
    if (_payments.isEmpty) {
      return const Center(
        child: Text('Henüz görüntülenecek bir ödeme bulunmuyor.'),
      );
    }

    return ListView.builder(
      itemCount: _payments.length,
      itemBuilder: (BuildContext context, int index) {
        final payment = _payments[index];

        // No onTap. The user can't tap the card
        return payment.buildUserPaymentCard(
          userDisplayName: 'Ödemeniz',
          onTap: null,
          showEditButton: false,
        );
      },
    );
  }
}
