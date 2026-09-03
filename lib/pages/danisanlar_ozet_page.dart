import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer_summary_row.dart';
import '../models/logger.dart';
import '../models/subs_model.dart';
import '../models/summary_color_config.dart';
import '../providers/customer_summary_provider.dart';
import '../providers/summary_colors_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import 'customer_sum.dart';
import '../widgets/labeled_action_button.dart';

final Logger logger = Logger.forClass(DanisanlarOzetPage);

/// Tahsil edilmemiş ödemelerde tutarın solunda gösterilen işaret. Sayfanın en
/// üstündeki not da bu işareti açıklar.
const String _plannedMark = '(P)';

/// Pakette karşılığı olmayan seans kutusunun genişliğini tarih hücreleriyle
/// eşitleyen görünmez yer tutucu.
const String _disabledSeansPlaceholder = '00.00.0000';

/// Admin overview: customers grouped by subscription status. The first tab
/// lists everyone with an *active* subscription; the second lists everyone
/// with a *frozen* (Donduruldu) subscription. Each row shows that
/// subscription's latest payment (date / amount / type), the package, and up
/// to [CustomerSummaryRow.maxSeans] session (seans) dates.
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
      body: Column(
        children: [
          _buildLegend(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CustomerSummaryTab(
                  key: _weeklyKey,
                  status: SubActiveStatus.activeWeekly,
                  emptyMessage:
                      'Aktif/Haftalık paketi olan danışan bulunamadı.',
                ),
                _CustomerSummaryTab(
                  key: _weightTrackingKey,
                  status: SubActiveStatus.activeWeightTracking,
                  emptyMessage:
                      'Aktif/Kilo Takip paketi olan danışan bulunamadı.',
                  // Weight-tracking packages have no payment; hide payment
                  // columns.
                  showPayment: false,
                ),
                _CustomerSummaryTab(
                  key: _frozenKey,
                  status: SubActiveStatus.frozen,
                  emptyMessage: 'Dondurulmuş paketi olan danışan bulunamadı.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Explains the markers used inside the tables: the "(P)" planned-payment
  /// mark and the black seans box. Sits at the very top of the page so it is
  /// visible on every tab; wraps instead of overflowing on narrow screens.
  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 16,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _legendEntry(
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade700),
              '$_plannedMark = Planlandı',
            ),
            _legendEntry(
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              '= Paketin görüşme sayısı dışındaki seans',
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendEntry(Widget marker, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        marker,
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
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
      // Cached after the first tab loads it; the table reads the resolved
      // color synchronously through SummaryColorsRegistry while building.
      await Provider.of<SummaryColorsProvider>(context, listen: false)
          .fetchColors();
      if (!mounted) return;
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
      const DataColumn(label: Text('Paket Süresi / Görüşme Türü')),
      if (widget.status == SubActiveStatus.frozen)
        const DataColumn(label: Text('Dondurulma Tarihi')),
      for (int i = 1; i <= CustomerSummaryRow.maxSeans; i++)
        DataColumn(label: Text('$i.Seans')),
      for (int i = 1; i <= postponedColumns; i++)
        DataColumn(label: Text('$i. Ertelenen Randevu')),
      const DataColumn(label: Text('Kalan Erteleme Hakkı'), numeric: true),
      for (int i = 1; i <= CustomerSummaryRow.maxPostponementUses; i++)
        DataColumn(label: Text('$i. Erteleme Hakkı Kullanımı')),
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
          _amountCell(row.paymentAmount, isPlanned: row.paymentIsPlanned),
          _cell(row.paymentType),
        ],
        _cell(row.packageType),
        if (widget.status == SubActiveStatus.frozen) _cell(row.freezeDate),
        for (int i = 0; i < row.seans.length; i++)
          _seansCell(row.seans[i], isBeyondPackage: i >= row.totalMeetings),
        for (int i = 0; i < postponedColumns; i++)
          _cell(i < row.postponedDates.length
              ? row.postponedDates[i]
              : const SummaryCell.empty()),
        _cell(row.remainingPostponements),
        for (int i = 0; i < CustomerSummaryRow.maxPostponementUses; i++)
          _cell(i < row.postponementUseDates.length
              ? row.postponementUseDates[i]
              : const SummaryCell.empty()),
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

  DataCell _cell(SummaryCell cell) =>
      DataCell(Text(cell.text, style: _cellStyle(cell)));

  /// Seans hücresi: yapılmış randevunun tarihi, admin'in Ayarlar'dan seçtiği
  /// arkaplan rengiyle vurgulanır. Yazı rengi arkaplanın parlaklığına göre
  /// belirlendiği için tarih her renkte okunabilir kalır.
  ///
  /// Boş (randevusu olmayan) ve "Hata" hücreleri vurgulanmaz: ilki gösterecek
  /// bir randevu taşımaz, ikincisi kendi kırmızı hata biçimini korur.
  ///
  /// [isBeyondPackage] ise kutu paketin görüşme sayısının dışındadır ve
  /// [_beyondPackageSeansCell] ile pasif (siyah) gösterilir.
  DataCell _seansCell(SummaryCell cell, {required bool isBeyondPackage}) {
    if (isBeyondPackage) return _beyondPackageSeansCell(cell);
    if (cell.isEmpty || cell.isError) return _cell(cell);

    final background = SummaryColorsRegistry.completedAppointmentColor;
    return DataCell(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          cell.text,
          style: TextStyle(
            color: SummaryColorsRegistry.readableTextColor(background),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// Paketin görüşme sayısını aşan seans kutusu: bu paket için hiç
  /// doldurulmayacağından siyah zeminle pasif gösterilir. Kutunun eni, boşken
  /// de komşu tarih hücreleriyle aynı kalsın diye görünmez bir tarih
  /// yer tutucusuyla verilir.
  DataCell _beyondPackageSeansCell(SummaryCell cell) {
    const Color background = Colors.black87;
    final Color foreground = SummaryColorsRegistry.readableTextColor(background);
    return DataCell(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: cell.isEmpty
            ? const Text(
                _disabledSeansPlaceholder,
                style: TextStyle(color: Colors.transparent),
              )
            : Text(
                cell.text,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  TextStyle _cellStyle(SummaryCell cell) => TextStyle(
        color: cell.isError ? Colors.red.shade700 : null,
        fontWeight: cell.isError ? FontWeight.bold : null,
      );

  /// Ödeme tutarı hücresi. Gösterilen ödeme henüz tahsil edilmemişse tutarın
  /// solunda kalın "(P)" işareti gösterilir. Hücre tek satır kalır; sütun
  /// numeric olduğu için içerik sağa yaslıdır.
  DataCell _amountCell(SummaryCell cell, {required bool isPlanned}) {
    if (!isPlanned) return _cell(cell);
    return DataCell(
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$_plannedMark ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: cell.text),
          ],
        ),
        style: _cellStyle(cell),
      ),
    );
  }
}
