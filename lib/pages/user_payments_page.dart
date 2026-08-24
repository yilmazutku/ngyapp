import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/payment_model.dart';
import '../models/logger.dart';
import '../providers/payment_provider.dart';
import '../widgets/app_bar_with_back.dart';

/// A page that displays a user's payments, grouped as overdue, then planned,
/// then completed, newest first inside each group. No filters: the client is
/// looking at their own handful of payments, not searching a ledger.
/// Overdue first, then planned, then completed.
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

  /// All payments fetched for this user.
  List<PaymentModel> _allPayments = [];

  /// A filtered list of payments based on status, date range, etc.
  List<PaymentModel> _filteredPayments = [];

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
  /// If there's an error, shows a dialog in Turkish.
  void _fetchUserPayments() {
    setState(() => _isLoading = true);

    final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
    paymentProvider
        .fetchPayments(
      null,
      userId: widget.userId,
      showAllPayments: true,
    )
        .then((payments) {
      _logger.info('Fetched ${payments.length} payments for user ${widget.userId}.');
      setState(() {
        _allPayments = payments;
        _applyFilters(); // Apply filters after fetching
        _isLoading = false;
      });
    }).catchError((error, stackTrace) {
      _logger.err('Error fetching payments: {}', [error]);
      _logger.err('Stack trace: {}', [stackTrace]);
      setState(() => _isLoading = false);

      _showMessageDialog('Ödemeler alınırken bir hata oluştu.');
    });
  }

  // --------------------------------------------------
  // Filtering & Sorting
  // --------------------------------------------------

  /// 1) Filter by status (if any).
  /// 2) Filter by date range (if any).
  /// 3) Finally, group-sort:
  ///     - Overdue first
  ///     - Planned
  ///     - Completed
  ///    and within each group, sort by date ascending/descending.
  void _applyFilters() {
    _logger.info('Applying filters in UserPaymentsPage.');

    List<PaymentModel> filtered = List.from(_allPayments);

    // Group sort: Overdue -> Planned -> Completed
    filtered.sort((a, b) {
      final scoreA = _getStatusScore(a);
      final scoreB = _getStatusScore(b);

      // Compare group scores first
      if (scoreA != scoreB) {
        // Overdue (0) < Planned (1) < Completed (2)
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

    setState(() {
      _filteredPayments = filtered;
    });

    _logger.info('Filtering complete. After all filters: ${_filteredPayments.length} payments.');
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
  // Dialogs
  // --------------------------------------------------

  /// Show a dialog with a message in Turkish.
  void _showMessageDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Mesaj'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
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

  /// Builds the scrollable list of filtered payments. If empty, show a placeholder message.
  Widget _buildPaymentsList() {
    if (_filteredPayments.isEmpty) {
      return const Center(
        child: Text('Henüz görüntülenecek bir ödeme bulunmuyor.'),
      );
    }

    return ListView.builder(
      itemCount: _filteredPayments.length,
      itemBuilder: (BuildContext context, int index) {
        final payment = _filteredPayments[index];

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
