import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/payment_model.dart';
import '../models/logger.dart';
import '../providers/payment_provider.dart';
import '../widgets/app_bar_with_back.dart';

/// A page that displays a user's payments with filtering and sorting.
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

  // --------------------------------------------------
  // Filter Fields
  // --------------------------------------------------

  /// Selected status for filtering (if null, show all).
  PaymentStatus? _selectedStatus;

  /// Selected date range for filtering (if null, no date constraint).
  DateTimeRange? _selectedDateRange;

  /// Ascending or descending sort by date (applied *within* each group).
  bool _isDateAscending = true;

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

    // Start with all
    List<PaymentModel> filtered = List.from(_allPayments);

    // 1) Filter by status
    if (_selectedStatus != null) {
      filtered = filtered.where((p) => p.status == _selectedStatus).toList();
      _logger.info('Status filter: ${_selectedStatus!.label}, results: ${filtered.length}.');
    }

    // 2) Filter by date range
    if (_selectedDateRange != null) {
      final start = _selectedDateRange!.start;
      final end = _selectedDateRange!.end;

      filtered = filtered.where((p) {
        // If completed, we compare paymentDate
        // otherwise, we compare dueDate
        final relevantDate = (p.status == PaymentStatus.completed)
            ? p.paymentDate
            : p.dueDate;
        if (relevantDate == null) return false;

        return relevantDate.isAfter(start.subtract(const Duration(days: 1))) &&
            relevantDate.isBefore(end.add(const Duration(days: 1)));
      }).toList();

      _logger.info(
          'Date range filter: '
              '${DateFormat('dd.MM.yyyy').format(start)} - '
              '${DateFormat('dd.MM.yyyy').format(end)}, '
              'results: ${filtered.length}.'
      );
    }

    // 3) Group sort: Overdue -> Planned -> Completed
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

      return _isDateAscending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
    });

    setState(() {
      _filteredPayments = filtered;
    });

    _logger.info('Filtering complete. After all filters: ${_filteredPayments.length} payments.');
  }

  /// Returns an integer that represents the "priority" of the payment.
  /// 0 = Overdue, 1 = Planned, 2 = Completed
  int _getStatusScore(PaymentModel p) {
    final now = DateTime.now();
    final isOverdue = (p.status == PaymentStatus.planned) &&
        (p.dueDate != null) &&
        p.dueDate!.isBefore(now);
    if (isOverdue) return 0; // Overdue first
    if (p.status == PaymentStatus.planned) return 1; // Planned next
    return 2; // Completed last
  }

  /// Clear all filters, revert to ascending date
  void _clearFilters() {
    _logger.info('Clearing all filters in UserPaymentsPage.');
    setState(() {
      _selectedStatus = null;
      _selectedDateRange = null;
      _isDateAscending = true;
    });
    _applyFilters();
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

  /// Open a filter dialog for PaymentStatus, date range, and sort direction.
  void _showFilterDialog() {
    _logger.info('Opening filter dialog in UserPaymentsPage.');

    // Temporary copies
    PaymentStatus? tempStatus = _selectedStatus;
    DateTimeRange? tempDateRange = _selectedDateRange;
    bool tempIsDateAscending = _isDateAscending;

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Filtre Seçenekleri'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status Filter
                    DropdownButtonFormField<PaymentStatus>(
                      value: tempStatus,
                      decoration: const InputDecoration(
                        labelText: 'Durum',
                      ),
                      items: PaymentStatus.values.map((PaymentStatus status) {
                        return DropdownMenuItem<PaymentStatus>(
                          value: status,
                          child: Text(status.label),
                        );
                      }).toList()
                        ..insert(
                          0,
                          const DropdownMenuItem<PaymentStatus>(
                            value: null,
                            child: Text('Tümü'),
                          ),
                        ),
                      onChanged: (PaymentStatus? newValue) {
                        setDialogState(() {
                          tempStatus = newValue;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Date Range Filter
                    ElevatedButton(
                      onPressed: () async {
                        final DateTimeRange? picked = await showDateRangePicker(
                          context: dialogContext,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDateRange: tempDateRange ??
                              DateTimeRange(
                                start: DateTime.now(),
                                end: DateTime.now().add(const Duration(days: 7)),
                              ),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            tempDateRange = picked;
                          });
                        }
                      },
                      child: Text(
                        (tempDateRange == null)
                            ? 'Tarih Aralığı Seç'
                            : '${DateFormat('dd.MM.yyyy').format(tempDateRange!.start)} - '
                            '${DateFormat('dd.MM.yyyy').format(tempDateRange!.end)}',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sort Order Toggle
                    SwitchListTile(
                      title: const Text('Tarihi Artan Sırada Göster'),
                      value: tempIsDateAscending,
                      onChanged: (bool value) {
                        setDialogState(() {
                          tempIsDateAscending = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(); // Close w/o applying
                  },
                  child: const Text('Vazgeç'),
                ),
                TextButton(
                  onPressed: () {
                    // Apply chosen filters
                    setState(() {
                      _selectedStatus = tempStatus;
                      _selectedDateRange = tempDateRange;
                      _isDateAscending = tempIsDateAscending;
                    });
                    Navigator.of(dialogContext).pop();
                    _applyFilters();
                  },
                  child: const Text('Uygula'),
                ),
              ],
            );
          },
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
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clearFilters,
          ),
        ],
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
