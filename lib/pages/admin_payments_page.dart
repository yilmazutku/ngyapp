import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../dialogs/edit_payment_dialog.dart';
import '../dialogs/add_payment_dialog.dart';
import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/user_model.dart';
import '../providers/payment_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';

final Logger logger = Logger.forClass(AdminPaymentsPage);
final DateFormat kDateFormat = DateFormat('d MMMM yyyy', 'tr_TR');

class AdminPaymentsPage extends StatefulWidget {
  const AdminPaymentsPage({super.key});

  @override
  createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends State<AdminPaymentsPage> {
  // Data
  List<PaymentModel> _allPayments = [];
  List<PaymentModel> _filteredPayments = [];
  List<UserModel> _users = [];
  late Map<String, UserModel> _userById = {};
  bool _isLoading = true;

  // Filters (applied only when user changes them)
  String? _searchQuery;
  PaymentStatus? _statusFilter;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _sortBy = 'dueDate';
  bool _sortAscending = true;

  // Stats (lazy: computed only when the user opens the stats)
  bool _showStats = false;
  bool _statsDirty = true;
  int _upcomingCount = 0;
  int _completedCount = 0;
  int _overdueCount = 0;
  double _totalAmountDue = 0;
  double _totalAmountPaid = 0;

  // Cached tab counts (avoid recomputing in build)
  int _countThisWeek = 0;
  int _countNextWeek = 0;
  int _countUpcoming = 0;
  int _countCompleted = 0;
  int _countOverdue = 0;

  /// One controller per tab list. Each Scrollbar + ListView shares the same controller.
  late final ScrollController _allCtrl;
  late final ScrollController _thisWeekCtrl;
  late final ScrollController _nextWeekCtrl;
  late final ScrollController _upcomingCtrl;
  late final ScrollController _completedCtrl;
  late final ScrollController _overdueCtrl;

  @override
  void initState() {
    super.initState();
    _allCtrl = ScrollController();
    _thisWeekCtrl = ScrollController();
    _nextWeekCtrl = ScrollController();
    _upcomingCtrl = ScrollController();
    _completedCtrl = ScrollController();
    _overdueCtrl = ScrollController();
    _loadData();
  }

  @override
  void dispose() {
    _allCtrl.dispose();
    _thisWeekCtrl.dispose();
    _nextWeekCtrl.dispose();
    _upcomingCtrl.dispose();
    _completedCtrl.dispose();
    _overdueCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    logger.info('Loading payment data for all users with Firebase-side filtering');

    try {
      // 1) Fetch users, build cache
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final users = await userProvider.fetchUsers();
      final map = {for (final u in users) u.userId: u};
      logger.info('Fetched ${users.length} users successfully');

      // 2) Fetch all payments with Firebase-side filtering (status only)
      // Date range filtering is done client-side due to conditional date field logic
      final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
      final allPayments = await paymentProvider.fetchAllPayments(
        statusFilter: _statusFilter,
      );

      if (!mounted) return;
      setState(() {
        _users = users;
        _userById = map;
        _allPayments = allPayments;

        // Apply remaining client-side filters (search, sorting)
        _applyClientSideFilters();

        // Refresh tab counts (labels) and mark stats dirty
        _recomputeTabCounts(_filteredPayments);
        _statsDirty = true;
        _isLoading = false;
      });

      logger.info('Total payments loaded: ${_allPayments.length}');
    } catch (e) {
      logger.err('Error loading data: {}', [e]);
      if (!mounted) return;
      setState(() => _isLoading = false);
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Veri yüklenirken bir hata oluştu: $e',
      );
    }
  }

  // Recompute only the tab counts (cheap integers) whenever data or filters change.
  void _recomputeTabCounts(List<PaymentModel> source) {
    final now = DateTime.now();

    // Week range (Mon..Sun)
    final firstDayOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeek = DateTime(firstDayOfWeek.year, firstDayOfWeek.month, firstDayOfWeek.day);
    final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    // Next week range
    final startOfNextWeek = startOfWeek.add(const Duration(days: 7));
    final endOfNextWeek =
    startOfNextWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    bool inRange(DateTime d, DateTime s, DateTime e) =>
        d.isAfter(s.subtract(const Duration(seconds: 1))) &&
            d.isBefore(e.add(const Duration(seconds: 1)));

    int thisWeek = 0, nextWeek = 0, upcoming = 0, completed = 0, overdue = 0;

    for (final p in source) {
      if (p.status == PaymentStatus.completed) {
        completed++;
      } else if (p.status == PaymentStatus.planned && p.dueDate != null) {
        if (p.dueDate!.isAfter(now)) {
          upcoming++;
        } else {
          overdue++;
        }
      }

      // Use paymentDate only if completed, otherwise fall back to dueDate
      final relevantDate = (p.status == PaymentStatus.completed && p.paymentDate != null)
          ? p.paymentDate
          : p.dueDate;
      if (relevantDate != null) {
        if (inRange(relevantDate, startOfWeek, endOfWeek)) thisWeek++;
        if (inRange(relevantDate, startOfNextWeek, endOfNextWeek)) nextWeek++;
      }
    }

    _countThisWeek = thisWeek;
    _countNextWeek = nextWeek;
    _countUpcoming = upcoming;
    _countCompleted = completed;
    _countOverdue = overdue;
  }

  /// Apply client-side filters (search, date range, and sorting)
  /// Status filter is applied on Firebase side
  void _applyClientSideFilters() {
    logger.info('Applying client-side filters - Search: "$_searchQuery", DateRange: $_startDate to $_endDate, SortBy: $_sortBy, SortAscending: $_sortAscending');

    List<PaymentModel> filtered = List.from(_allPayments);

    // Date range filtering (client-side: conditional date field based on status)
    if (_startDate != null && _endDate != null) {
      final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      
      filtered = filtered.where((p) {
        // Determine which date to check based on status filter and payment status
        if (_statusFilter == PaymentStatus.completed) {
          // Status filter is "completed" → check paymentDate
          final date = p.paymentDate;
          return date != null && !date.isBefore(start) && !date.isAfter(end);
        } else if (_statusFilter == PaymentStatus.planned) {
          // Status filter is "planned" → check dueDate
          final date = p.dueDate;
          return date != null && !date.isBefore(start) && !date.isAfter(end);
        } else {
          // Status filter is "all" → check appropriate date based on payment's own status
          // Include if either paymentDate (for completed) or dueDate (for planned) is in range
          if (p.status == PaymentStatus.completed && p.paymentDate != null) {
            return !p.paymentDate!.isBefore(start) && !p.paymentDate!.isAfter(end);
          } else if (p.dueDate != null) {
            return !p.dueDate!.isBefore(start) && !p.dueDate!.isAfter(end);
          }
          return false;
        }
      }).toList();
      logger.info('Date range filter applied: $_startDate to $_endDate, results: ${filtered.length}');
    }

    // Search (client-side: user name, surname, full name, email, notes)
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      final q = _searchQuery!.toLowerCase();
      filtered = filtered.where((p) {
        final u = _userById[p.userId];
        final name = (u?.name ?? '').toLowerCase();
        final surname = (u?.surname ?? '').toLowerCase();
        final fullName = '$name $surname'.trim();
        final email = (u?.email ?? '').toLowerCase();
        final notes = p.notes?.toLowerCase() ?? '';
        return name.contains(q) || surname.contains(q) || fullName.contains(q) || email.contains(q) || notes.contains(q);
      }).toList();
      logger.info('Search filter applied with query: "$_searchQuery", results: ${filtered.length}');
    }

    // Sort (client-side: complex sorting not supported by Firebase)
    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'dueDate':
          DateTime relevant(PaymentModel p) =>
              p.status == PaymentStatus.completed
                  ? (p.paymentDate ?? DateTime.fromMillisecondsSinceEpoch(0))
                  : (p.dueDate ?? DateTime.fromMillisecondsSinceEpoch(0));
          final da = relevant(a), db = relevant(b);
          return _sortAscending ? da.compareTo(db) : db.compareTo(da);
        case 'amount':
          return _sortAscending ? a.amount.compareTo(b.amount) : b.amount.compareTo(a.amount);
        case 'userName':
          final ua = _userById[a.userId]?.name ?? '';
          final ub = _userById[b.userId]?.name ?? '';
          return _sortAscending ? ua.compareTo(ub) : ub.compareTo(ua);
        default:
          return 0;
      }
    });
    logger.info('Sorting applied - SortBy: $_sortBy, SortAscending: $_sortAscending');

    _filteredPayments = filtered;
    _recomputeTabCounts(_filteredPayments); // update labels
    _statsDirty = true; // filters changed → stats must refresh next time they're shown

    logger.info('Client-side filters applied successfully. Total filtered payments: ${filtered.length}');
  }
  
  /// Apply filters and trigger data reload for Firebase-side filters
  /// Search and sort are applied client-side only
  void _applyFilters() {
    logger.info('Applying filters - Status: $_statusFilter, DateRange: $_startDate to $_endDate, SortBy: $_sortBy, SortAscending: $_sortAscending');
    
    // For status and date range changes, reload data from Firebase
    // Search and sort will be applied client-side in _loadData()
    _loadData();
  }

  void _resetFilters() {
    logger.info('Resetting all filters to default values');
    setState(() {
      _statusFilter = null;
      _startDate = null;
      _endDate = null;
      _searchQuery = null;
      _sortBy = 'dueDate';
      _sortAscending = true;
      _statsDirty = true;
    });
    // Reload data with no filters (Firebase-side)
    _loadData();
  }

  // Compute stats only when the user opens the stats section.
  void _onStatsButtonPressed() {
    if (_showStats) {
      setState(() => _showStats = false);
      return;
    }

    int upcoming = 0, completed = 0, overdue = 0;
    double amountDue = 0, amountPaid = 0;

    if (_statsDirty) {
      final now = DateTime.now();
      for (final p in _filteredPayments) {
        if (p.status == PaymentStatus.completed) {
          completed++;
          amountPaid += p.amount;
        } else if (p.status == PaymentStatus.planned) {
          if (p.dueDate != null) {
            if (p.dueDate!.isAfter(now)) {
              upcoming++;
            } else {
              overdue++;
            }
            amountDue += p.amount;
          }
        }
      }
    }

    setState(() {
      _showStats = true;
      if (_statsDirty) {
        _upcomingCount = upcoming;
        _completedCount = completed;
        _overdueCount = overdue;
        _totalAmountDue = amountDue;
        _totalAmountPaid = amountPaid;
        _statsDirty = false;
      }
    });

    logger.info('Stats computed on demand (lazy).');
  }

  /// Get user name from user ID via cache
  String _getUserName(String userId) => _userById[userId]?.name ?? 'Unknown';

  void _showEditPaymentDialog(PaymentModel payment) {
    logger.info(
        'Opening edit payment dialog for payment ${payment.paymentId} (User: ${_getUserName(payment.userId)})');
    showDialog(
      context: context,
      builder: (context) {
        return EditPaymentDialog(
          payment: payment,
          onPaymentUpdated: () {
            logger.info('Payment ${payment.paymentId} updated successfully');
            _loadData(); // refresh whole page/caches
          },
        );
      },
    );
  }

  void _showAddPaymentDialog(BuildContext context) {
    logger.info('Opening add payment dialog - Step 1: User selection');

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _UserSelectionDialog(
          users: _users,
          onUserSelected: (user) {
            logger.info('User selected for payment: ${user.name} (${user.userId})');
            Navigator.pop(dialogContext); // close user picker
            showDialog(
              context: context,
              builder: (context) {
                return AddPaymentDialog(
                  userId: user.userId,
                  onPaymentAdded: () {
                    logger.info('Payment added successfully for user ${user.name}');
                    _loadData();
                  },
                );
              },
            );
          },
          onCancel: () {
            logger.info('User selection canceled');
            Navigator.pop(dialogContext);
          },
        );
      },
    );
  }

  Widget _buildPaymentCard(PaymentModel payment) {
    final userName = _getUserName(payment.userId);
    return payment.buildPaymentCard(
      userName: userName,
      onEdit: () => _showEditPaymentDialog(payment),
      onDelete: () => _deletePayment(payment),
      showEditButton: true,
      showDeleteButton: true,
    );
  }

  Widget _buildStatsCard() {
    String dateRangeText = _startDate != null && _endDate != null
        ? '${kDateFormat.format(_startDate!)} - ${kDateFormat.format(_endDate!)}'
        : 'Tüm Tarihler';

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Ödeme İstatistikleri',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(dateRangeText, style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('Planlanan Ödemeler', _upcomingCount.toString(),
                    Icons.calendar_today, Colors.blue),
                _statItem('Tamamlanan Ödemeler', _completedCount.toString(),
                    Icons.check_circle, Colors.green),
                _statItem('Geciken Ödemeler', _overdueCount.toString(),
                    Icons.warning, Colors.red),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('Toplam Beklenen', '${_totalAmountDue.toStringAsFixed(2)} ₺',
                    Icons.account_balance_wallet, Colors.orange),
                _statItem('Toplam Ödenen', '${_totalAmountPaid.toStringAsFixed(2)} ₺',
                    Icons.paid, Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildAllPaymentsTab() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            onPressed: _onStatsButtonPressed,
            icon: Icon(_showStats ? Icons.expand_less : Icons.expand_more),
            label: Text(_showStats ? 'İstatistikleri Gizle' : 'İstatistikleri Göster'),
          ),
        ),
        AnimatedCrossFade(
          firstChild: _buildStatsCard(),
          secondChild: const SizedBox.shrink(),
          crossFadeState:
          _showStats ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 300),
        ),
        Expanded(
          child: _filteredPayments.isEmpty
              ? const Center(child: Text('Ödeme bulunamadı.'))
              : Scrollbar(
            thickness: 8.0,
            radius: const Radius.circular(4.0),
            controller: _allCtrl,
            child: ListView.builder(
              key: const PageStorageKey('all_payments'),
              controller: _allCtrl,
              addAutomaticKeepAlives: false,
              // itemExtent: 120, // <- if your cards have fixed height, uncomment for a big boost
              itemCount: _filteredPayments.length,
              itemBuilder: (context, index) {
                return _buildPaymentCard(_filteredPayments[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThisWeekPaymentsTab() {
    final now = DateTime.now();
    final firstDayOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfWeek =
    DateTime(firstDayOfWeek.year, firstDayOfWeek.month, firstDayOfWeek.day);
    final endOfWeek =
    startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    final thisWeekPayments = _filteredPayments.where((payment) {
      // Use paymentDate only if completed, otherwise fall back to dueDate
      final relevantDate = (payment.status == PaymentStatus.completed && payment.paymentDate != null)
          ? payment.paymentDate
          : payment.dueDate;
      if (relevantDate == null) return false;
      return relevantDate.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) &&
          relevantDate.isBefore(endOfWeek.add(const Duration(seconds: 1)));
    }).toList();

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : thisWeekPayments.isEmpty
        ? const Center(child: Text('Bu hafta için ödeme bulunamadı.'))
        : Scrollbar(
      thickness: 8.0,
      radius: const Radius.circular(4.0),
      controller: _thisWeekCtrl,
      child: ListView.builder(
        key: const PageStorageKey('this_week'),
        controller: _thisWeekCtrl,
        addAutomaticKeepAlives: false,
        itemCount: thisWeekPayments.length,
        itemBuilder: (context, index) {
          return _buildPaymentCard(thisWeekPayments[index]);
        },
      ),
    );
  }

  Widget _buildNextWeekPaymentsTab() {
    final now = DateTime.now();
    final firstDayOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfNextWeek =
    DateTime(firstDayOfWeek.year, firstDayOfWeek.month, firstDayOfWeek.day)
        .add(const Duration(days: 7));
    final endOfNextWeek =
    startOfNextWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

    final nextWeekPayments = _filteredPayments.where((payment) {
      // Use paymentDate only if completed, otherwise fall back to dueDate
      final relevantDate = (payment.status == PaymentStatus.completed && payment.paymentDate != null)
          ? payment.paymentDate
          : payment.dueDate;
      if (relevantDate == null) return false;
      return relevantDate.isAfter(startOfNextWeek.subtract(const Duration(seconds: 1))) &&
          relevantDate.isBefore(endOfNextWeek.add(const Duration(seconds: 1)));
    }).toList();

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : nextWeekPayments.isEmpty
        ? const Center(child: Text('Gelecek hafta için ödeme bulunamadı.'))
        : Scrollbar(
      thickness: 8.0,
      radius: const Radius.circular(4.0),
      controller: _nextWeekCtrl,
      child: ListView.builder(
        key: const PageStorageKey('next_week'),
        controller: _nextWeekCtrl,
        addAutomaticKeepAlives: false,
        itemCount: nextWeekPayments.length,
        itemBuilder: (context, index) {
          return _buildPaymentCard(nextWeekPayments[index]);
        },
      ),
    );
  }

  Widget _buildUpcomingPaymentsTab() {
    final now = DateTime.now();
    final upcomingPayments = _filteredPayments.where((payment) {
      return payment.status == PaymentStatus.planned &&
          payment.dueDate != null &&
          payment.dueDate!.isAfter(now);
    }).toList();

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : upcomingPayments.isEmpty
        ? const Center(child: Text('Planlanan ödeme bulunamadı.'))
        : Scrollbar(
      thickness: 8.0,
      radius: const Radius.circular(4.0),
      controller: _upcomingCtrl,
      child: ListView.builder(
        key: const PageStorageKey('upcoming'),
        controller: _upcomingCtrl,
        addAutomaticKeepAlives: false,
        itemCount: upcomingPayments.length,
        itemBuilder: (context, index) {
          return _buildPaymentCard(upcomingPayments[index]);
        },
      ),
    );
  }

  Widget _buildCompletedPaymentsTab() {
    final completedPayments =
    _filteredPayments.where((p) => p.status == PaymentStatus.completed).toList();

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : completedPayments.isEmpty
        ? const Center(child: Text('Tamamlanan ödeme bulunamadı.'))
        : Scrollbar(
      thickness: 8.0,
      radius: const Radius.circular(4.0),
      controller: _completedCtrl,
      child: ListView.builder(
        key: const PageStorageKey('completed'),
        controller: _completedCtrl,
        addAutomaticKeepAlives: false,
        itemCount: completedPayments.length,
        itemBuilder: (context, index) {
          return _buildPaymentCard(completedPayments[index]);
        },
      ),
    );
  }

  Widget _buildOverduePaymentsTab() {
    final now = DateTime.now();
    final overduePayments = _filteredPayments.where((payment) {
      return payment.status == PaymentStatus.planned &&
          payment.dueDate != null &&
          payment.dueDate!.isBefore(now);
    }).toList();

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : overduePayments.isEmpty
        ? const Center(child: Text('Geciken ödeme bulunamadı.'))
        : Scrollbar(
      thickness: 8.0,
      radius: const Radius.circular(4.0),
      controller: _overdueCtrl,
      child: ListView.builder(
        key: const PageStorageKey('overdue'),
        controller: _overdueCtrl,
        addAutomaticKeepAlives: false,
        itemCount: overduePayments.length,
        itemBuilder: (context, index) {
          return _buildPaymentCard(overduePayments[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    logger.info('Building AdminPaymentsPage UI');

    return Scaffold(
      appBar: AppBarWithBack(
        title: 'Ödemeler',
        actions: [
          Tooltip(
            message: 'Ödeme Ekle',
            preferBelow: false,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Ödeme Ekle'),
              onPressed: () => _showAddPaymentDialog(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrele',
            onPressed: () => _showFilterDialog(context),
          ),
          if (_statusFilter != null || _startDate != null || _endDate != null || _searchQuery != null)
            IconButton(
              icon: const Icon(Icons.filter_list_off),
              tooltip: 'Filtreleri Temizle',
              onPressed: _resetFilters,
            ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              await showSearch(
                context: context,
                delegate: PaymentSearchDelegate(
                  allPayments: _allPayments,
                  users: _users,
                  userById: _userById,
                  onPaymentSelected: (payment) => _showEditPaymentDialog(payment),
                ),
              );
            },
          ),
          Tooltip(
            message: 'Yenile',
            preferBelow: false,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Yenile'),
              onPressed: _loadData,
            ),
          ),
        ],
      ),
      body: DefaultTabController(
        length: 6,
        child: Column(
          children: [
            Container(
              color: Colors.blue.shade50,
              child: TabBar(
                tabs: [
                  Tab(text: 'Tüm Ödemeler (${_filteredPayments.length})'),
                  Tab(text: 'Bu Hafta (${_countThisWeek})'),
                  Tab(text: 'Gelecek Hafta (${_countNextWeek})'),
                  Tab(text: 'Gelecek (${_countUpcoming})'),
                  Tab(text: 'Tamamlanan (${_countCompleted})'),
                  Tab(text: 'Geciken (${_countOverdue})'),
                ],
                isScrollable: true,
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.blue,
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildAllPaymentsTab(),
                  _buildThisWeekPaymentsTab(),
                  _buildNextWeekPaymentsTab(),
                  _buildUpcomingPaymentsTab(),
                  _buildCompletedPaymentsTab(),
                  _buildOverduePaymentsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show filter dialog for payments
  void _showFilterDialog(BuildContext context) {
    // Create temporary filter values
    PaymentStatus? tempStatus = _statusFilter;
    DateTime? tempStartDate = _startDate;
    DateTime? tempEndDate = _endDate;
    String? tempSearchQuery = _searchQuery;
    String? tempSortBy = _sortBy;
    bool tempSortAscending = _sortAscending;

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ödeme Filtreleri'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search field
                      const Text('Arama:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Kullanıcı adı, email veya notlara göre ara...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                        controller: TextEditingController(text: tempSearchQuery),
                        onChanged: (value) => tempSearchQuery = value.isEmpty ? null : value,
                      ),
                      const SizedBox(height: 16),
                      
                      // Status filter
                      const Text('Durum:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<PaymentStatus?>(
                        value: tempStatus,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Tümü',
                        ),
                        items: [
                          const DropdownMenuItem<PaymentStatus?>(
                            value: null,
                            child: Text('Tümü'),
                          ),
                          ...PaymentStatus.values.map((status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          )),
                        ],
                        onChanged: (value) => setDialogState(() => tempStatus = value),
                      ),
                      const SizedBox(height: 16),
                      
                      // Date range
                      const Text('Tarih Aralığı:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today),
                              label: Text(
                                tempStartDate != null && tempEndDate != null
                                    ? '${kDateFormat.format(tempStartDate!)} - ${kDateFormat.format(tempEndDate!)}'
                                    : 'Tarih seçin',
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () async {
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                  initialDateRange: tempStartDate != null && tempEndDate != null
                                      ? DateTimeRange(start: tempStartDate!, end: tempEndDate!)
                                      : null,
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    tempStartDate = picked.start;
                                    tempEndDate = picked.end;
                                  });
                                }
                              },
                            ),
                          ),
                          if (tempStartDate != null || tempEndDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setDialogState(() {
                                tempStartDate = null;
                                tempEndDate = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Sort options
                      const Text('Sıralama:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: tempSortBy,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: 'dueDate', child: Text('Tarihe Göre')),
                          const DropdownMenuItem(value: 'amount', child: Text('Tutara Göre')),
                          const DropdownMenuItem(value: 'userName', child: Text('Kullanıcı Adına Göre')),
                        ],
                        onChanged: (value) => setDialogState(() => tempSortBy = value),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Artan Sıralama'),
                        value: tempSortAscending,
                        onChanged: (value) => setDialogState(() => tempSortAscending = value),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _statusFilter = tempStatus;
                      _startDate = tempStartDate;
                      _endDate = tempEndDate;
                      _searchQuery = tempSearchQuery;
                      _sortBy = tempSortBy;
                      _sortAscending = tempSortAscending;
                    });
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

  Future<void> _deletePayment(PaymentModel payment) async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Ödeme Sil',
      message:
      '${_getUserName(payment.userId)} kullanıcısına ait ${payment.amount.toStringAsFixed(2)} ₺ tutarındaki ödemeyi silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );
    if (!confirmed) return;

    try {
      final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
      await paymentProvider.deletePayment(payment.paymentId, payment.userId);

      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Ödeme başarıyla silindi.',
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Ödeme silinirken bir hata oluştu: $e',
      );
    }
  }
}

/// Stateful dialog for user selection with working search functionality
class _UserSelectionDialog extends StatefulWidget {
  final List<UserModel> users;
  final Function(UserModel) onUserSelected;
  final VoidCallback onCancel;

  const _UserSelectionDialog({
    required this.users,
    required this.onUserSelected,
    required this.onCancel,
  });

  @override
  State<_UserSelectionDialog> createState() => _UserSelectionDialogState();
}

class _UserSelectionDialogState extends State<_UserSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _filteredUsers = widget.users;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = widget.users;
      } else {
        final searchQuery = query.toLowerCase();
        _filteredUsers = widget.users.where((user) {
          final name = user.name.toLowerCase();
          final surname = (user.surname ?? '').toLowerCase();
          final fullName = '$name $surname'.trim();
          final email = user.email.toLowerCase();
          return name.contains(searchQuery) ||
              surname.contains(searchQuery) ||
              fullName.contains(searchQuery) ||
              email.contains(searchQuery);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kullanıcı Seçin'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Kullanıcı ara...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                ),
                onChanged: _filterUsers,
              ),
            ),
            Expanded(
              child: _filteredUsers.isEmpty
                  ? const Center(child: Text('Kullanıcı bulunamadı'))
                  : ListView.builder(
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?'),
                          ),
                          title: Text('${user.name} ${user.surname ?? ''}'.trim()),
                          subtitle: Text(user.email),
                          onTap: () => widget.onUserSelected(user),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('İptal'),
        ),
      ],
    );
  }
}

class PaymentSearchDelegate extends SearchDelegate<String> {
  final List<PaymentModel> allPayments;
  final List<UserModel> users;
  final Map<String, UserModel> userById;
  final Function(PaymentModel) onPaymentSelected;

  PaymentSearchDelegate({
    required this.allPayments,
    required this.users,
    required this.userById,
    required this.onPaymentSelected,
  });

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  String _getUserName(String userId) => userById[userId]?.name ?? 'Unknown';

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return const Center(child: Text('Kullanıcı adı veya notlara göre arayın'));
    }

    final searchQuery = query.toLowerCase();
    final suggestions = allPayments.where((p) {
      final name = (_getUserName(p.userId)).toLowerCase();
      final email = (userById[p.userId]?.email ?? '').toLowerCase();
      final notes = p.notes?.toLowerCase() ?? '';
      return name.contains(searchQuery) || email.contains(searchQuery) || notes.contains(searchQuery);
    }).take(100) // cap to reduce build cost
        .toList();

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final payment = suggestions[index];
        final userName = _getUserName(payment.userId);

        return ListTile(
          title: Text(userName),
          subtitle: Text(
            'Tutar: ${payment.amount} ₺, Durum: ${payment.status.label}, '
                '${payment.dueDate != null ? 'Tarih: ${kDateFormat.format(payment.dueDate!)}' : ''}',
          ),
          onTap: () {
            onPaymentSelected(payment);
            close(context, '');
          },
        );
      },
    );
  }
}
