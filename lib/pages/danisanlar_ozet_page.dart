import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer_summary_row.dart';
import '../models/logger.dart';
import '../models/subs_model.dart';
import '../providers/customer_summary_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import 'customer_sum.dart';
import '../widgets/labeled_action_button.dart';

final Logger logger = Logger.forClass(DanisanlarOzetPage);

/// Admin overview: customers grouped by subscription status. The first tab
/// lists everyone with an *active* subscription; the second lists everyone
/// with a *frozen* (Donduruldu) subscription. Each row shows the latest
/// payment (date / amount / type), the package, and up to
/// [CustomerSummaryRow.maxSeans] session (seans) dates.
class DanisanlarOzetPage extends StatefulWidget {
  const DanisanlarOzetPage({super.key});

  @override
  State<DanisanlarOzetPage> createState() => _DanisanlarOzetPageState();
}

class _DanisanlarOzetPageState extends State<DanisanlarOzetPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<_CustomerSummaryTabState> _weeklyKey = GlobalKey();
  final GlobalKey<_CustomerSummaryTabState> _weightTrackingKey = GlobalKey();
  final GlobalKey<_CustomerSummaryTabState> _frozenKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshCurrent() {
    final key = switch (_tabController.index) {
      0 => _weeklyKey,
      1 => _weightTrackingKey,
      _ => _frozenKey,
    };
    key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danışanlar Özet'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          LabeledActionButton(
            icon: Icons.refresh,
            label: 'Yenile',
            onPressed: _refreshCurrent,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Aktif / Haftalık'),
            Tab(text: 'Aktif / Kilo Takip'),
            Tab(text: 'Dondurulmuş'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CustomerSummaryTab(
            key: _weeklyKey,
            status: SubActiveStatus.activeWeekly,
            emptyMessage: 'Aktif/Haftalık paketi olan danışan bulunamadı.',
          ),
          _CustomerSummaryTab(
            key: _weightTrackingKey,
            status: SubActiveStatus.activeWeightTracking,
            emptyMessage: 'Aktif/Kilo Takip paketi olan danışan bulunamadı.',
            // Weight-tracking packages have no payment; hide payment columns.
            showPayment: false,
          ),
          _CustomerSummaryTab(
            key: _frozenKey,
            status: SubActiveStatus.frozen,
            emptyMessage: 'Dondurulmuş paketi olan danışan bulunamadı.',
          ),
        ],
      ),
    );
  }
}

/// Loads and renders the customer-summary table for a single subscription
/// [status]. Keeps its own scroll/loading state so switching tabs does not
/// discard already-loaded data.
class _CustomerSummaryTab extends StatefulWidget {
  final SubActiveStatus status;
  final String emptyMessage;
  final bool showPayment;

  const _CustomerSummaryTab({
    super.key,
    required this.status,
    required this.emptyMessage,
    this.showPayment = true,
  });

  @override
  State<_CustomerSummaryTab> createState() => _CustomerSummaryTabState();
}

class _CustomerSummaryTabState extends State<_CustomerSummaryTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  bool _loading = true;
  String? _error;
  List<CustomerSummaryRow> _rows = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  /// Public entry point so the parent page can trigger a refresh.
  Future<void> reload() => _load();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final provider =
          Provider.of<CustomerSummaryProvider>(context, listen: false);
      final rows =
          await provider.fetchCustomerSummariesByStatus(widget.status);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      logger.err('Failed to load customer summaries: {}', [e]);
      if (!mounted) return;
      setState(() {
        _error = 'Özet verileri yüklenirken bir hata oluştu.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildBody();
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (_rows.isEmpty) {
      return Center(child: Text(widget.emptyMessage));
    }

    // Total-count banner (top-left) above the table, showing how many customers
    // are currently listed in this tab.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTotalCountHeader(),
        Expanded(child: _buildTable()),
      ],
    );
  }

  /// A small banner in the top-left showing the number of customers listed in
  /// this tab (`Toplam Danışan Sayısı`).
  Widget _buildTotalCountHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people, size: 18, color: Colors.blue.shade800),
              const SizedBox(width: 6),
              Text(
                'Toplam Danışan Sayısı: ${_rows.length}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    // Postponed-date columns are dynamic: use the widest row so every row lines
    // up, then pad shorter rows with empty cells.
    final int postponedColumns = _rows.fold<int>(
      0,
      (m, r) => r.postponedDates.length > m ? r.postponedDates.length : m,
    );

    // Both scrollbars wrap both scroll views (canonical two-axis pattern) so
    // the vertical and horizontal thumbs are always visible and draggable,
    // even when the table is smaller than the window.
    return Scrollbar(
      controller: _verticalController,
      thumbVisibility: true,
      child: Scrollbar(
        controller: _horizontalController,
        thumbVisibility: true,
        notificationPredicate: (notification) => notification.depth == 1,
        child: SingleChildScrollView(
          controller: _verticalController,
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: DataTable(
                // Tighter spacing so no column is unnecessarily wide.
                columnSpacing: 18,
                horizontalMargin: 12,
                headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
                columns: _buildColumns(postponedColumns),
                rows: _rows.map((r) => _buildRow(r, postponedColumns)).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<DataColumn> _buildColumns(int postponedColumns) {
    return <DataColumn>[
      const DataColumn(label: Text('Dosya No')),
      const DataColumn(label: Text('Ad-Soyad')),
      if (widget.showPayment) ...[
        const DataColumn(label: Text('Ödeme Tarihi')),
        const DataColumn(label: Text('Ödeme Tutarı'), numeric: true),
        const DataColumn(label: Text('Ödeme Şekli')),
      ],
      const DataColumn(label: Text('Paket Tipi')),
      if (widget.status == SubActiveStatus.frozen)
        const DataColumn(label: Text('Dondurulma Tarihi')),
      for (int i = 1; i <= CustomerSummaryRow.maxSeans; i++)
        DataColumn(label: Text('$i.Seans')),
      for (int i = 1; i <= postponedColumns; i++)
        DataColumn(label: Text('$i. Ertelenen Randevu')),
      const DataColumn(label: Text('Kalan Erteleme Hakkı'), numeric: true),
    ];
  }

  DataRow _buildRow(CustomerSummaryRow row, int postponedColumns) {
    return DataRow(
      cells: <DataCell>[
        _cell(row.dosyaNo),
        DataCell(
          Text(
            row.fullName,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade800,
              decoration: TextDecoration.underline,
            ),
          ),
          onTap: () => _openCustomerDetails(row),
        ),
        if (widget.showPayment) ...[
          _cell(row.paymentDate),
          _cell(row.paymentAmount),
          _cell(row.paymentType),
        ],
        _cell(row.packageType),
        if (widget.status == SubActiveStatus.frozen) _cell(row.freezeDate),
        for (final seans in row.seans) _cell(seans),
        for (int i = 0; i < postponedColumns; i++)
          _cell(i < row.postponedDates.length
              ? row.postponedDates[i]
              : const SummaryCell.empty()),
        _cell(row.remainingPostponements),
      ],
    );
  }

  /// Opens the customer's own page on its "Detay" tab. Pushed on top of this
  /// page, so its back button returns here; opened from anywhere else it
  /// returns to whatever pushed it.
  Future<void> _openCustomerDetails(CustomerSummaryRow row) async {
    // The summary row only carries the id, and the customer page needs the full
    // user record for its header.
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: 'Danışan açılıyor...');
      loadingOpen = true;
    }

    void closeLoading() {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
    }

    try {
      final user = await userProvider.fetchUserDetails(userId: row.userId);
      closeLoading();
      if (!mounted) return;

      if (user == null) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: '${row.fullName} için danışan kaydı bulunamadı.',
        );
        return;
      }

      logger.info('Opening customer details from summary: userId={}', [row.userId]);
      // The details tab pops back with the deleted user's id when the admin
      // removes them, so the row is dropped here instead of leaving a customer
      // listed who no longer exists.
      final deletedUserId = await Navigator.push<Object?>(
        context,
        MaterialPageRoute(builder: (_) => CustomerSummaryPage(user: user)),
      );
      if (!mounted) return;
      if (deletedUserId is String && deletedUserId.isNotEmpty) {
        setState(() {
          _rows = _rows.where((r) => r.userId != deletedUserId).toList();
        });
      }
    } catch (e) {
      logger.err('Could not open customer details for {}: {}', [row.userId, e]);
      closeLoading();
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Danışan bilgileri açılırken bir hata oluştu: $e',
      );
    }
  }

  DataCell _cell(SummaryCell cell) {
    return DataCell(
      Text(
        cell.text,
        style: TextStyle(
          color: cell.isError ? Colors.red.shade700 : null,
          fontWeight: cell.isError ? FontWeight.bold : null,
        ),
      ),
    );
  }
}
