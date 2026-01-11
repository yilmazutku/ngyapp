import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../models/user_model.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/loading_overlay.dart';

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
        'Opening admin edit payment dialog for payment ${payment.paymentId} (User: ${_getUserName(payment.userId)})');
    showDialog(
      context: context,
      builder: (context) {
        return _AdminEditPaymentDialog(
          payment: payment,
          users: _users,
          userById: _userById,
          onPaymentUpdated: () {
            logger.info('Payment ${payment.paymentId} updated successfully');
            _loadData(); // refresh whole page/caches
          },
        );
      },
    );
  }

  void _showAddPaymentDialog(BuildContext context) {
    logger.info('Opening admin add payment dialog');

    showDialog(
      context: context,
      builder: (context) {
        return _AdminAddPaymentDialog(
          users: _users,
          onPaymentAdded: () {
            logger.info('Payment added successfully');
            _loadData();
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

/// Admin Add Payment Dialog with user and subscription selection
/// Matches the logic flow of AddPaymentDialog but with user selection
class _AdminAddPaymentDialog extends StatefulWidget {
  final List<UserModel> users;
  final Function onPaymentAdded;

  const _AdminAddPaymentDialog({
    required this.users,
    required this.onPaymentAdded,
  });

  @override
  State<_AdminAddPaymentDialog> createState() => _AdminAddPaymentDialogState();
}

class _AdminAddPaymentDialogState extends State<_AdminAddPaymentDialog>
    with LoadingStateMixin {
  final Logger _logger = Logger.forClass(_AdminAddPaymentDialog);
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _userSearchController = TextEditingController();
  final DateFormat _df = DateFormat('d MMMM yyyy', 'tr_TR');
  final ImagePicker _picker = ImagePicker();

  // User selection
  UserModel? _selectedUser;
  List<UserModel> _filteredUsers = [];
  bool _showUserDropdown = false;

  // Subscription selection
  List<SubscriptionModel> _subscriptions = [];
  SubscriptionModel? _selectedSubscription;
  bool _isLoadingSubscriptions = false;

  // Payment details
  DateTime? _selectedPaymentDate = DateTime.now();
  DateTime? _selectedDueDate;
  PaymentStatus _paymentStatus = PaymentStatus.completed;
  File? _dekontImage;

  @override
  void initState() {
    super.initState();
    _filteredUsers = widget.users;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _userSearchController.dispose();
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
          final surname = user.surname.toLowerCase();
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

  Future<void> _onUserSelected(UserModel user) async {
    setState(() {
      _selectedUser = user;
      _userSearchController.text = '${user.name} ${user.surname}'.trim();
      _showUserDropdown = false;
      _isLoadingSubscriptions = true;
      _selectedSubscription = null;
      _subscriptions = [];
    });

    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final subs = await subProvider.fetchSubscriptions(
        userId: user.userId,
        showAllSubscriptions: false, // Only active subscriptions
      );

      if (!mounted) return;
      setState(() {
        _subscriptions = subs;
        _isLoadingSubscriptions = false;
        // Default to first active subscription if available
        if (subs.isNotEmpty) {
          _selectedSubscription = subs.first;
        }
      });
    } catch (e) {
      _logger.err('Error fetching subscriptions: {}', [e]);
      if (!mounted) return;
      setState(() => _isLoadingSubscriptions = false);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Abonelikler yüklenirken bir hata oluştu: $e',
        );
      }
    }
  }

  Future<void> _pickDekontImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    setState(() {
      if (pickedFile != null) {
        _dekontImage = File(pickedFile.path);
        _logger.info('Dekont image selected: ${pickedFile.path}');
      } else {
        _logger.err('No dekont image selected.');
      }
    });
  }

  Future<void> _addPayment() async {
    // Validation - matches AddPaymentDialog
    if (_selectedUser == null) {
      _logger.err('_addPayment: User is required.');
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen bir kullanıcı seçiniz.',
        );
      }
      return;
    }

    if (_amountController.text.isEmpty) {
      _logger.err('_addPayment: Amount is required.');
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen miktarı giriniz.',
        );
      }
      return;
    }

    if (_paymentStatus == PaymentStatus.completed && _selectedPaymentDate == null) {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen ödeme tarihini seçiniz.',
        );
      }
      return;
    }

    if (_paymentStatus == PaymentStatus.planned && _selectedDueDate == null) {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen planlanan tarihi seçiniz.',
        );
      }
      return;
    }

    // Show confirmation dialog - matches AddPaymentDialog style
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ödeme Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aşağıdaki ödemeyi eklemek istediğinizden emin misiniz?'),
              const SizedBox(height: 16),
              Text('Kullanıcı: ${_selectedUser!.name} ${_selectedUser!.surname}'),
              Text('Miktar: ${_amountController.text} TL'),
              Text('Bağlı Paket: ${_selectedSubscription?.packageName ?? "Yok"}'),
              Text('Durum: ${_paymentStatus.label}'),
              if (_selectedDueDate != null)
                Text(
                  'Planlanan Tarih: ${_df.format(_selectedDueDate!)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (_selectedPaymentDate != null)
                Text(
                  'Ödeme Tarihi: ${_df.format(_selectedPaymentDate!)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (_dekontImage != null) const Text('Dekont: Yüklendi'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Evet'),
            ),
          ],
        );
      },
    );

    if (shouldSave != true) return;

    startLoading();

    try {
      final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
      final paymentAmount = double.parse(_amountController.text);

      await paymentProvider.addPayment(
        userId: _selectedUser!.userId,
        subscription: _selectedSubscription,
        amount: paymentAmount,
        paymentDate: _selectedPaymentDate,
        status: _paymentStatus,
        dekontImage: _dekontImage,
        dueDate: _selectedDueDate,
      );

      // Update subscription's amountPaid if a subscription is selected and payment is completed
      if (_selectedSubscription != null && _paymentStatus == PaymentStatus.completed) {
        final subscriptionId = _selectedSubscription!.subscriptionId;
        final newAmountPaid = _selectedSubscription!.amountPaid + paymentAmount;

        final subProvider = Provider.of<SubProvider>(context, listen: false);
        await subProvider.updateAmountPaid(
          userId: _selectedUser!.userId,
          subscriptionId: subscriptionId,
          amountPaid: newAmountPaid,
        );

        _selectedSubscription!.amountPaid = newAmountPaid;
        _logger.info('Updated subscription $subscriptionId amountPaid to $newAmountPaid');
      }

      widget.onPaymentAdded();
      if (mounted) {
        Navigator.of(context).pop();
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Ödeme başarıyla eklendi.\n\n'
              'Kullanıcı: ${_selectedUser!.name} ${_selectedUser!.surname}\n'
              'Miktar: ${_amountController.text} TL\n'
              'Bağlı Paket: ${_selectedSubscription?.packageName ?? "Yok"}\n'
              'Durum: ${_paymentStatus.label}\n'
              '${_selectedDueDate != null ? 'Planlanan Tarih: ${_df.format(_selectedDueDate!)}\n' : ''}'
              '${_selectedPaymentDate != null ? 'Ödeme Tarihi: ${_df.format(_selectedPaymentDate!)}\n' : ''}',
        );
      }
    } catch (e) {
      _logger.err('Error adding payment: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Ödeme eklenirken bir hata oluştu: $e',
        );
      }
    } finally {
      stopLoading();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AlertDialog(
          title: const Text('Ödeme Ekle'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 450,
              child: ListBody(
                children: [
                  // User Selection
                  TextField(
                    controller: _userSearchController,
                    decoration: InputDecoration(
                      labelText: 'Kullanıcı',
                      hintText: 'Kullanıcı ara...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_search),
                      suffixIcon: _selectedUser != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _selectedUser = null;
                                  _userSearchController.clear();
                                  _subscriptions = [];
                                  _selectedSubscription = null;
                                  _filteredUsers = widget.users;
                                });
                              },
                            )
                          : null,
                    ),
                    onTap: () => setState(() => _showUserDropdown = true),
                    onChanged: (value) {
                      _filterUsers(value);
                      setState(() => _showUserDropdown = true);
                    },
                  ),
                  if (_showUserDropdown && _selectedUser == null)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _filteredUsers.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Kullanıcı bulunamadı'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = _filteredUsers[index];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?'),
                                  ),
                                  title: Text('${user.name} ${user.surname}'.trim()),
                                  subtitle: Text(user.email, style: const TextStyle(fontSize: 12)),
                                  onTap: () => _onUserSelected(user),
                                );
                              },
                            ),
                    ),
                  const SizedBox(height: 16),

                  // Subscription Dropdown
                  if (_selectedUser == null)
                    const Text('Önce kullanıcı seçiniz', style: TextStyle(color: Colors.grey))
                  else if (_isLoadingSubscriptions)
                    const Center(child: CircularProgressIndicator())
                  else
                    DropdownButtonFormField<SubscriptionModel?>(
                      value: _selectedSubscription,
                      items: [
                        const DropdownMenuItem<SubscriptionModel?>(
                          value: null,
                          child: Text('Paketsiz ödeme'),
                        ),
                        ..._subscriptions.map((sub) {
                          String amountInfo = '';
                          if (sub.amountPaid < sub.totalAmount) {
                            final remaining = sub.totalAmount - sub.amountPaid;
                            amountInfo = ' (Kalan ödeme: ${remaining.toStringAsFixed(2)} TL)';
                          }
                          return DropdownMenuItem<SubscriptionModel?>(
                            value: sub,
                            child: Text('${sub.packageName}$amountInfo'),
                          );
                        }),
                      ],
                      onChanged: (newValue) => setState(() => _selectedSubscription = newValue),
                      decoration: const InputDecoration(
                        labelText: 'Bağlı Paket',
                        hintText: 'Paket seçin (opsiyonel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Amount Field
                  TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Miktar (TL)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payment status dropdown
                  DropdownButtonFormField<PaymentStatus>(
                    value: _paymentStatus,
                    items: PaymentStatus.values.map((PaymentStatus status) {
                      return DropdownMenuItem<PaymentStatus>(
                        value: status,
                        child: Text(status.label),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() {
                        _paymentStatus = newValue!;
                        if (_paymentStatus == PaymentStatus.completed) {
                          _selectedPaymentDate = DateTime.now();
                          _selectedDueDate = null;
                        } else {
                          _selectedPaymentDate = null;
                        }
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Ödeme Durumu',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Due Date Picker (for planned)
                  if (_paymentStatus == PaymentStatus.planned) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _selectedDueDate == null
                            ? 'Planlanan Tarih Seç'
                            : 'Planlanan Tarih: ${_df.format(_selectedDueDate!)}',
                        style: _selectedDueDate != null
                            ? const TextStyle(fontWeight: FontWeight.bold)
                            : null,
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: _selectedDueDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2030),
                        );
                        if (pickedDate != null) {
                          setState(() => _selectedDueDate = pickedDate);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Payment Date Picker (for completed)
                  if (_paymentStatus == PaymentStatus.completed) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _selectedPaymentDate == null
                            ? 'Ödeme Tarihi Seç'
                            : 'Ödeme Tarihi: ${_df.format(_selectedPaymentDate!)}${DateUtils.isSameDay(_selectedPaymentDate!, DateTime.now()) ? ' (Bugün)' : ''}',
                        style: _selectedPaymentDate != null
                            ? const TextStyle(fontWeight: FontWeight.bold)
                            : null,
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: _selectedPaymentDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        setState(() => _selectedPaymentDate = pickedDate);
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _pickDekontImage(),
                      child: const Text('Dekont Yükle (Opsiyonel)'),
                    ),
                    const SizedBox(height: 16),
                    _dekontImage != null
                        ? Image.file(_dekontImage!, height: 100)
                        : const Text('Dekont Seçilmedi'),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () => _addPayment(),
              child: const Text('Ödeme Ekle'),
            ),
          ],
        ),
        if (isLoading) const LoadingOverlay(message: 'Ödeme ekleniyor...'),
      ],
    );
  }
}

/// Admin Edit Payment Dialog with user change capability
/// Matches the logic flow of EditPaymentDialog but with user selection
class _AdminEditPaymentDialog extends StatefulWidget {
  final PaymentModel payment;
  final List<UserModel> users;
  final Map<String, UserModel> userById;
  final Function onPaymentUpdated;

  const _AdminEditPaymentDialog({
    required this.payment,
    required this.users,
    required this.userById,
    required this.onPaymentUpdated,
  });

  @override
  State<_AdminEditPaymentDialog> createState() => _AdminEditPaymentDialogState();
}

class _AdminEditPaymentDialogState extends State<_AdminEditPaymentDialog>
    with LoadingStateMixin {
  final Logger _logger = Logger.forClass(_AdminEditPaymentDialog);
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _userSearchController = TextEditingController();
  final DateFormat _df = DateFormat('d MMMM yyyy', 'tr_TR');
  final ImagePicker _picker = ImagePicker();

  // User selection
  late UserModel? _selectedUser;
  late String _originalUserId;
  List<UserModel> _filteredUsers = [];
  bool _showUserDropdown = false;

  // Subscription selection
  List<SubscriptionModel> _availableSubscriptions = [];
  String? _selectedSubscriptionId;
  bool _loadingSubscriptions = true;

  // Payment details
  DateTime? _selectedPaymentDate;
  DateTime? _selectedDueDate;
  late PaymentStatus _paymentStatus;
  File? _dekontImage;

  @override
  void initState() {
    super.initState();
    _originalUserId = widget.payment.userId;
    _selectedUser = widget.userById[widget.payment.userId];
    _userSearchController.text = _selectedUser != null
        ? '${_selectedUser!.name} ${_selectedUser!.surname}'.trim()
        : 'Bilinmeyen Kullanıcı';
    _filteredUsers = widget.users;

    _amountController.text = widget.payment.amount.toString();
    _selectedPaymentDate = widget.payment.paymentDate ?? DateTime.now();
    _selectedDueDate = widget.payment.dueDate;
    _paymentStatus = widget.payment.status;
    _selectedSubscriptionId = widget.payment.subscriptionId;

    _loadSubscriptions();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _userSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadSubscriptions() async {
    if (_selectedUser == null) {
      setState(() => _loadingSubscriptions = false);
      return;
    }

    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final subscriptions = await subProvider.fetchSubscriptions(
        userId: _selectedUser!.userId,
        showAllSubscriptions: true,
      );
      if (mounted) {
        setState(() {
          _availableSubscriptions = subscriptions;

          // Check if selected subscription still exists, if not reset to null (Paketsiz)
          if (_selectedSubscriptionId != null) {
            final exists = subscriptions.any((s) => s.subscriptionId == _selectedSubscriptionId);
            if (!exists) {
              _logger.warn('Selected subscription $_selectedSubscriptionId no longer exists, resetting to Paketsiz');
              _selectedSubscriptionId = null;
            }
          }

          _loadingSubscriptions = false;
        });
      }
    } catch (e) {
      _logger.err('Error loading subscriptions: {}', [e]);
      if (mounted) {
        setState(() => _loadingSubscriptions = false);
      }
    }
  }

  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = widget.users;
      } else {
        final searchQuery = query.toLowerCase();
        _filteredUsers = widget.users.where((user) {
          final name = user.name.toLowerCase();
          final surname = user.surname.toLowerCase();
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

  Future<void> _onUserSelected(UserModel user) async {
    final bool userChanged = _selectedUser?.userId != user.userId;

    setState(() {
      _selectedUser = user;
      _userSearchController.text = '${user.name} ${user.surname}'.trim();
      _showUserDropdown = false;

      if (userChanged) {
        _loadingSubscriptions = true;
        _selectedSubscriptionId = null; // Reset subscription when user changes
        _availableSubscriptions = [];
      }
    });

    if (userChanged) {
      await _loadSubscriptions();
    }
  }

  Future<void> _pickDekontImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    setState(() {
      if (pickedFile != null) {
        _dekontImage = File(pickedFile.path);
        _logger.info('Dekont image selected: ${pickedFile.path}');
      } else {
        _logger.err('No dekont image selected.');
      }
    });
  }

  /// TR/EN-friendly numeric parser - matches EditPaymentDialog
  double? _parseAmountOrNull(String text) {
    String s = text.trim().replaceAll(' ', '');
    if (s.isEmpty) return null;

    if (s.contains('.') && s.contains(',')) {
      s = s.replaceAll('.', '');
      s = s.replaceAll(',', '.');
    } else if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    }
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;

    try {
      final v = double.parse(s);
      if (v.isNaN || v.isInfinite) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  Future<void> _updatePayment() async {
    // Validation - matches EditPaymentDialog
    if (_selectedUser == null) {
      _logger.warn('User is required on _updatePayment.');
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen bir kullanıcı seçiniz.',
        );
      }
      return;
    }

    final rawAmount = _amountController.text;
    if (rawAmount.trim().isEmpty) {
      _logger.warn('Amount is required on _updatePayment.');
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen miktarı giriniz.',
        );
      }
      return;
    }

    final parsedAmount = _parseAmountOrNull(rawAmount);
    if (parsedAmount == null) {
      _logger.warn('Invalid amount input: "{}"', [rawAmount]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Miktar geçersiz. Lütfen sayısal bir değer giriniz.\nÖrnek: 1200,50',
        );
      }
      return;
    }

    // Status-specific date requirements
    if (_paymentStatus == PaymentStatus.completed) {
      if (_selectedPaymentDate == null) {
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Lütfen ödeme tarihini seçiniz.',
          );
        }
        return;
      }
    } else if (_paymentStatus == PaymentStatus.planned) {
      if (_selectedDueDate == null) {
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Lütfen planlanan tarihi seçiniz.',
          );
        }
        return;
      }
    }

    // Original values
    final oldPayment = widget.payment;
    final oldAmount = oldPayment.amount;
    final oldStatus = oldPayment.status;
    final oldSubsId = oldPayment.subscriptionId;
    final userChanged = _selectedUser!.userId != _originalUserId;

    final newAmount = parsedAmount;

    // Get subscription names for display
    String? oldSubName;
    String? newSubName;
    if (oldSubsId != null) {
      try {
        final oldSub = _availableSubscriptions.firstWhere((s) => s.subscriptionId == oldSubsId);
        oldSubName = oldSub.packageName;
      } catch (e) {
        oldSubName = 'Silinmiş Paket';
      }
    }
    if (_selectedSubscriptionId != null) {
      try {
        final newSub = _availableSubscriptions.firstWhere((s) => s.subscriptionId == _selectedSubscriptionId);
        newSubName = newSub.packageName;
      } catch (e) {
        newSubName = 'Bilinmeyen Paket';
      }
    }

    // Confirm - matches EditPaymentDialog style
    final shouldUpdate = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ödeme Güncelle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aşağıdaki değişiklikleri yapmak istediğinizden emin misiniz?'),
                const SizedBox(height: 16),
                Text('Kullanıcı: ${_selectedUser!.name} ${_selectedUser!.surname}'),
                Text('Miktar: ${NumberFormat.decimalPattern('tr_TR').format(newAmount)} TL'),
                Text('Durum: ${_paymentStatus.label}'),
                if (_selectedSubscriptionId != null)
                  Text('Bağlı Paket: $newSubName')
                else
                  const Text('Bağlı Paket: Yok'),
                if (_selectedSubscriptionId != oldSubsId)
                  Text(
                    'Paket Değişti: ${oldSubName ?? "Yok"} → ${newSubName ?? "Yok"}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                if (userChanged)
                  Text(
                    'Kullanıcı Değişti: ${widget.userById[_originalUserId]?.name ?? "Bilinmeyen"} → ${_selectedUser!.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                if (_selectedDueDate != null)
                  Text(
                    'Planlanan Tarih: ${_df.format(_selectedDueDate!)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                if (_selectedPaymentDate != null)
                  Text(
                    'Ödeme Tarihi: ${_df.format(_selectedPaymentDate!)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                if (_dekontImage != null) const Text('Dekont: Yüklendi'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Evet'),
            ),
          ],
        );
      },
    );
    if (shouldUpdate != true) {
      _logger.info('Payment update cancelled by user for payment ${oldPayment.paymentId}');
      return;
    }

    startLoading();

    try {
      // Upload dekont if selected
      String? dekontUrl = widget.payment.dekontUrl;
      if (_dekontImage != null) {
        _logger.info('Uploading new dekont image for payment ${oldPayment.paymentId}');
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('payments')
            .child('${widget.payment.paymentId}_${DateTime.now().millisecondsSinceEpoch}');
        await storageRef.putFile(_dekontImage!);
        dekontUrl = await storageRef.getDownloadURL();
        _logger.info('New dekont image uploaded successfully, URL: $dekontUrl');
      }

      final amountDifference = newAmount - oldAmount;
      final String? oldSubscriptionId = widget.payment.subscriptionId;
      final String? newSubscriptionId = _selectedSubscriptionId;
      final bool subscriptionChanged = oldSubscriptionId != newSubscriptionId;
      final statusChanged = oldStatus != _paymentStatus;

      _logger.info('Payment update initiated for payment ${oldPayment.paymentId}:');
      _logger.info('- User changed: $userChanged');
      _logger.info('- Amount: $oldAmount -> $newAmount');
      _logger.info('- Status: ${oldStatus.label} -> ${_paymentStatus.label}');
      _logger.info('- Subscription changed: $subscriptionChanged');

      final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);

      if (userChanged) {
        // User changed: delete from old user, add to new user
        _logger.info('User changed from $_originalUserId to ${_selectedUser!.userId}');

        // Remove from old subscription if payment was completed
        if (oldSubscriptionId != null && oldStatus == PaymentStatus.completed) {
          _logger.info('Removing amount from old subscription $oldSubscriptionId');
          try {
            final oldSubDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(_originalUserId)
                .collection('subscriptions')
                .doc(oldSubscriptionId)
                .get();

            if (oldSubDoc.exists) {
              final oldSubData = oldSubDoc.data() as Map<String, dynamic>;
              double currentAmountPaid = (oldSubData['amountPaid'] ?? 0).toDouble();
              double newAmountPaid = (currentAmountPaid - oldAmount).clamp(0, double.infinity);

              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(_originalUserId)
                  .collection('subscriptions')
                  .doc(oldSubscriptionId)
                  .update({'amountPaid': newAmountPaid});

              _logger.info('Updated old subscription $oldSubscriptionId amountPaid from $currentAmountPaid to $newAmountPaid');
            }
          } catch (e) {
            _logger.err('Error updating old subscription $oldSubscriptionId: {}', [e]);
          }
        }

        // Delete payment from old user
        await paymentProvider.deletePayment(oldPayment.paymentId, _originalUserId);
        _logger.info('Deleted payment from old user $_originalUserId');

        // Add payment to new user
        await paymentProvider.addPayment(
          userId: _selectedUser!.userId,
          subscription: newSubscriptionId != null
              ? _availableSubscriptions.where((s) => s.subscriptionId == newSubscriptionId).firstOrNull
              : null,
          amount: newAmount,
          paymentDate: _selectedPaymentDate,
          status: _paymentStatus,
          dekontImage: _dekontImage,
          dueDate: _selectedDueDate,
        );
        _logger.info('Added payment to new user ${_selectedUser!.userId}');

        // Add to new subscription if payment is completed
        if (newSubscriptionId != null && _paymentStatus == PaymentStatus.completed) {
          _logger.info('Adding amount to new subscription $newSubscriptionId');
          try {
            final newSubDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(_selectedUser!.userId)
                .collection('subscriptions')
                .doc(newSubscriptionId)
                .get();

            if (newSubDoc.exists) {
              final newSubData = newSubDoc.data() as Map<String, dynamic>;
              double currentAmountPaid = (newSubData['amountPaid'] ?? 0).toDouble();
              double adjustedAmountPaid = currentAmountPaid + newAmount;

              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(_selectedUser!.userId)
                  .collection('subscriptions')
                  .doc(newSubscriptionId)
                  .update({'amountPaid': adjustedAmountPaid});

              _logger.info('Updated new subscription $newSubscriptionId amountPaid from $currentAmountPaid to $adjustedAmountPaid');
            }
          } catch (e) {
            _logger.err('Error updating new subscription $newSubscriptionId: {}', [e]);
          }
        }
      } else {
        // User didn't change - update payment in place
        final updatedPayment = PaymentModel(
          paymentId: widget.payment.paymentId,
          userId: _selectedUser!.userId,
          subscriptionId: _selectedSubscriptionId,
          amount: newAmount,
          status: _paymentStatus,
          paymentDate: _selectedPaymentDate,
          dueDate: _selectedDueDate,
          dekontUrl: dekontUrl,
          createDate: widget.payment.createDate,
          createUser: widget.payment.createUser,
          updateDate: DateTime.now(),
          updateUser: 'admin',
          notes: widget.payment.notes,
          notificationTimes: widget.payment.notificationTimes,
        );

        _logger.info('Updating payment in database...');
        await paymentProvider.updatePayment(updatedPayment);
        _logger.info('Payment ${updatedPayment.paymentId} updated successfully in database');

        // Handle subscription amount adjustments - matches EditPaymentDialog logic
        if (subscriptionChanged || statusChanged || (oldStatus == PaymentStatus.completed && amountDifference != 0)) {
          _logger.info('Processing subscription adjustments...');

          if (subscriptionChanged) {
            // Subscription changed: remove from old, add to new

            // Step 1: Remove amount from old subscription if it was completed
            if (oldSubscriptionId != null && oldStatus == PaymentStatus.completed) {
              _logger.info('Removing amount from old subscription $oldSubscriptionId');
              try {
                final oldSubDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_selectedUser!.userId)
                    .collection('subscriptions')
                    .doc(oldSubscriptionId)
                    .get();

                if (oldSubDoc.exists) {
                  final oldSubData = oldSubDoc.data() as Map<String, dynamic>;
                  double currentAmountPaid = (oldSubData['amountPaid'] ?? 0).toDouble();
                  double newAmountPaid = (currentAmountPaid - oldAmount).clamp(0, double.infinity);

                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(_selectedUser!.userId)
                      .collection('subscriptions')
                      .doc(oldSubscriptionId)
                      .update({'amountPaid': newAmountPaid});

                  _logger.info('Updated old subscription $oldSubscriptionId amountPaid from $currentAmountPaid to $newAmountPaid (removed $oldAmount)');
                }
              } catch (e) {
                _logger.err('Error updating old subscription $oldSubscriptionId: {}', [e]);
              }
            }

            // Step 2: Add amount to new subscription if it is completed
            if (newSubscriptionId != null && _paymentStatus == PaymentStatus.completed) {
              _logger.info('Adding amount to new subscription $newSubscriptionId');
              try {
                final newSubDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_selectedUser!.userId)
                    .collection('subscriptions')
                    .doc(newSubscriptionId)
                    .get();

                if (newSubDoc.exists) {
                  final newSubData = newSubDoc.data() as Map<String, dynamic>;
                  double currentAmountPaid = (newSubData['amountPaid'] ?? 0).toDouble();
                  double adjustedAmountPaid = currentAmountPaid + newAmount;

                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(_selectedUser!.userId)
                      .collection('subscriptions')
                      .doc(newSubscriptionId)
                      .update({'amountPaid': adjustedAmountPaid});

                  _logger.info('Updated new subscription $newSubscriptionId amountPaid from $currentAmountPaid to $adjustedAmountPaid (added $newAmount)');
                }
              } catch (e) {
                _logger.err('Error updating new subscription $newSubscriptionId: {}', [e]);
              }
            }
          } else if (newSubscriptionId != null) {
            // Same subscription, but amount or status changed
            _logger.info('Same subscription - adjusting amount for subscription $newSubscriptionId');
            try {
              final subDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(_selectedUser!.userId)
                  .collection('subscriptions')
                  .doc(newSubscriptionId)
                  .get();

              if (subDoc.exists) {
                final subData = subDoc.data() as Map<String, dynamic>;
                double currentAmountPaid = (subData['amountPaid'] ?? 0).toDouble();

                double adjustmentAmount = 0;
                if (statusChanged) {
                  if (_paymentStatus == PaymentStatus.completed && oldStatus != PaymentStatus.completed) {
                    adjustmentAmount = newAmount;
                    _logger.info('Status changed to completed - adding full amount $newAmount');
                  } else if (_paymentStatus != PaymentStatus.completed && oldStatus == PaymentStatus.completed) {
                    adjustmentAmount = -oldAmount;
                    _logger.info('Status changed from completed - subtracting old amount $oldAmount');
                  }
                } else if (_paymentStatus == PaymentStatus.completed && amountDifference != 0) {
                  adjustmentAmount = amountDifference;
                  _logger.info('Amount changed for completed payment - adjusting by $amountDifference');
                }

                if (adjustmentAmount != 0) {
                  final newAmountPaid = (currentAmountPaid + adjustmentAmount).clamp(0, double.infinity);
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(_selectedUser!.userId)
                      .collection('subscriptions')
                      .doc(newSubscriptionId)
                      .update({'amountPaid': newAmountPaid});

                  _logger.info('Adjusted subscription $newSubscriptionId amountPaid from $currentAmountPaid to $newAmountPaid (adjustment: $adjustmentAmount)');
                }
              }
            } catch (e) {
              _logger.err('Error adjusting subscription $newSubscriptionId: {}', [e]);
            }
          }
        }
      }

      _logger.info('Payment update completed successfully');

      widget.onPaymentUpdated();
      if (mounted) {
        Navigator.of(context).pop();
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Ödeme başarıyla güncellendi.\n\n'
              'Kullanıcı: ${_selectedUser!.name} ${_selectedUser!.surname}\n'
              'Miktar: ${NumberFormat.decimalPattern('tr_TR').format(newAmount)} TL\n'
              'Durum: ${_paymentStatus.label}\n'
              '${newSubName != null ? 'Bağlı Paket: $newSubName\n' : 'Bağlı Paket: Yok\n'}'
              '${_selectedDueDate != null ? 'Planlanan Tarih: ${_df.format(_selectedDueDate!)}\n' : ''}'
              '${_selectedPaymentDate != null ? 'Ödeme Tarihi: ${_df.format(_selectedPaymentDate!)}\n' : ''}',
        );
      }
    } catch (e) {
      _logger.err('Error updating payment ${widget.payment.paymentId}: {}', [e]);

      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Ödeme güncellenirken bir hata oluştu: $e',
        );
      }
    } finally {
      stopLoading();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AlertDialog(
          title: const Text('Ödemeyi Düzenle'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 450,
              child: ListBody(
                children: [
                  // User Selection
                  TextField(
                    controller: _userSearchController,
                    decoration: InputDecoration(
                      labelText: 'Kullanıcı',
                      hintText: 'Kullanıcı ara...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_drop_down),
                        onPressed: () => setState(() => _showUserDropdown = !_showUserDropdown),
                      ),
                    ),
                    onTap: () => setState(() => _showUserDropdown = true),
                    onChanged: (value) {
                      _filterUsers(value);
                      setState(() => _showUserDropdown = true);
                    },
                  ),
                  if (_showUserDropdown)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _filteredUsers.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Kullanıcı bulunamadı'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = _filteredUsers[index];
                                final isSelected = _selectedUser?.userId == user.userId;
                                return ListTile(
                                  dense: true,
                                  selected: isSelected,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isSelected ? Theme.of(context).primaryColor : null,
                                    child: Text(
                                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                      style: TextStyle(color: isSelected ? Colors.white : null),
                                    ),
                                  ),
                                  title: Text('${user.name} ${user.surname}'.trim()),
                                  subtitle: Text(user.email, style: const TextStyle(fontSize: 12)),
                                  onTap: () => _onUserSelected(user),
                                );
                              },
                            ),
                    ),
                  if (_selectedUser?.userId != _originalUserId && _selectedUser != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kullanıcı değiştirilecek! Ödeme yeni kullanıcıya aktarılacak.',
                              style: TextStyle(color: Colors.orange.shade900, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Amount Field (with numeric guard)
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(labelText: 'Miktar (TL)'),
                  ),
                  const SizedBox(height: 16),

                  // Subscription Selection Dropdown
                  if (_loadingSubscriptions)
                    const Center(child: CircularProgressIndicator())
                  else
                    DropdownButtonFormField<String?>(
                      value: _selectedSubscriptionId,
                      decoration: const InputDecoration(
                        labelText: 'Bağlı Paket',
                        hintText: 'Paket seçin (opsiyonel)',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Paketsiz ödeme'),
                        ),
                        ..._availableSubscriptions.map((sub) {
                          return DropdownMenuItem<String?>(
                            value: sub.subscriptionId,
                            child: Text(
                              '${sub.packageName} (${_df.format(sub.startDate)})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (newValue) => setState(() => _selectedSubscriptionId = newValue),
                    ),
                  const SizedBox(height: 16),

                  // Payment Status Dropdown (no clearing on toggle)
                  DropdownButtonFormField<PaymentStatus>(
                    value: _paymentStatus,
                    items: PaymentStatus.values.map((PaymentStatus status) {
                      return DropdownMenuItem<PaymentStatus>(
                        value: status,
                        child: Text(status.label),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setState(() {
                        _paymentStatus = newValue!;
                        // DO NOT clear the other date anymore.
                        // We keep both in memory so the picker reopens with the last chosen date.
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Ödeme Durumu'),
                  ),
                  const SizedBox(height: 16),

                  // "Planlanan tarihi seç" ONLY when Planned
                  if (_paymentStatus == PaymentStatus.planned) ...[
                    ListTile(
                      title: Text(
                        _selectedDueDate == null
                            ? 'Planlanan tarihi seç'
                            : 'Planlanan tarih: ${_df.format(_selectedDueDate!)}',
                        style: _selectedDueDate != null ? const TextStyle(fontWeight: FontWeight.bold) : null,
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final now = DateTime.now();
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: _selectedDueDate ?? now,
                          firstDate: now.subtract(const Duration(days: 365)),
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        setState(() {
                          _selectedDueDate = pickedDate;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // "Ödeme tarihi seç" ONLY when Completed
                  if (_paymentStatus == PaymentStatus.completed) ...[
                    ListTile(
                      title: Text(
                        _selectedPaymentDate == null
                            ? 'Ödeme tarihi seç'
                            : 'Ödeme Tarihi: ${_df.format(_selectedPaymentDate!)}${DateUtils.isSameDay(_selectedPaymentDate!, DateTime.now()) ? ' (Bugün)' : ''}',
                        style: _selectedPaymentDate != null ? const TextStyle(fontWeight: FontWeight.bold) : null,
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: _selectedPaymentDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        setState(() {
                          _selectedPaymentDate = pickedDate;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Dekont only when completed
                    ElevatedButton(
                      onPressed: () => _pickDekontImage(),
                      child: const Text('Dekont Görseli Yükle (Opsiyonel)'),
                    ),
                    const SizedBox(height: 16),
                    _dekontImage != null
                        ? Image.file(_dekontImage!, height: 100)
                        : widget.payment.dekontUrl != null
                            ? Image.network(widget.payment.dekontUrl!, height: 100)
                            : const Text('Dekont Görseli Seçilmedi'),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () => _updatePayment(),
              child: const Text('Ödemeyi Güncelle'),
            ),
          ],
        ),
        if (isLoading) const LoadingOverlay(message: 'Ödeme güncelleniyor...'),
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
