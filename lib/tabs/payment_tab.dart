// payments_tab.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../dialogs/edit_payment_dialog.dart';
import '../dialogs/add_payment_dialog.dart';
import '../models/payment_model.dart';
import '../models/filter_params.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/dialog_utils.dart';
import 'basetab.dart';
import 'filterable_tab.dart';
import '../widgets/labeled_action_button.dart';

class PaymentsTab extends BaseTab<PaymentProvider> {
  const PaymentsTab({super.key, required super.userId})
      : super(allDataLabel: 'Tüm ödemeler', subscriptionDataLabel: 'Paket Ödemeleri');

  @override
  PaymentProvider getProvider(BuildContext context) =>
      Provider.of<PaymentProvider>(context, listen: false);

  @override
  Future<List<dynamic>> getDataList(PaymentProvider provider, bool showAllData, {FilterParams? filterParams}) =>
      provider.fetchPayments(null, userId: userId, showAllPayments: showAllData, filterParams: filterParams as PaymentFilterParams?);

  @override
  BaseTabState<PaymentProvider, BaseTab<PaymentProvider>> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends FilterableTabState<PaymentProvider, PaymentsTab> {
  PaymentStatus? _selectedStatus;
  PaymentStatus? _tempStatus;

  // Cache formatters once (reduces jank)
  // Whole lira, no kuruş: payment amounts are never entered with a decimal
  // part, so showing ",00" on every card is noise.
  final NumberFormat _currencyFormat = NumberFormat('#,##0 ₺', 'tr_TR');
  final DateFormat _dateFormat = DateFormat('d MMMM y', 'tr_TR');

  final Map<String, String> _subscriptionCache = {}; // Cache for subscription names
  // Nullable and set from a post-frame callback: the tab can be disposed before
  // that callback runs, and dispose() must not touch a field that was never
  // assigned.
  PaymentProvider? _paymentProvider;
  final ScrollController _listCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _tempStatus = _selectedStatus;
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupPaymentListener());
  }

  void _setupPaymentListener() {
    if (!mounted) return;
    final provider = Provider.of<PaymentProvider>(context, listen: false);
    _paymentProvider = provider;
    provider.addListener(_onPaymentProviderChanged);
  }
  
  Future<String> _getSubscriptionName(String subscriptionId) async {
    if (_subscriptionCache.containsKey(subscriptionId)) {
      return _subscriptionCache[subscriptionId]!;
    }
    
    final subProvider = Provider.of<SubProvider>(context, listen: false);
    final name = await subProvider.getSubscriptionPackageName(
      userId: widget.userId,
      subscriptionId: subscriptionId,
    );
    final displayName = name ?? '';
    _subscriptionCache[subscriptionId] = displayName;
    return displayName;
  }

  void _onPaymentProviderChanged() {
    final provider = _paymentProvider;
    if (provider == null || !provider.paymentChanged) return;
    provider.resetPaymentChanged();
    // Deferred: this runs inside notifyListeners(), which a write can fire
    // while a build is in progress or while its own Firestore work is still
    // settling. Refetching right here refetched twice per write and could
    // setState during build.
    scheduleRefresh();
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    _paymentProvider?.removeListener(_onPaymentProviderChanged);
    super.dispose();
  }

  // ===== Filter plumbing =====

  @override
  void resetAdditionalTempFilters() {
    _tempStatus = _selectedStatus;
  }

  @override
  void applyAdditionalTempFilters() {
    _selectedStatus = _tempStatus;
  }

  @override
  void resetAdditionalFilters() {
    _selectedStatus = null;
    resetTempFiltersToDefaults();
  }

  @override
  void resetTempFiltersToDefaults() {
    _tempStatus = null;
  }

  @override
  bool hasAdditionalActiveFilters() => _selectedStatus != null;

  @override
  FilterParams? buildFilterParams() {
    return PaymentFilterParams(
      searchQuery: searchQuery.isNotEmpty ? searchQuery : null,
      dateRange: selectedDateRange,
      status: _selectedStatus?.label,
    );
  }

  // IMPORTANT: no setState from build — keep it pure
  @override
  void onFilterApplied(List<dynamic> filteredItems) {
    // no-op: summaries are computed inline
  }

  // ===== Rendering =====

  // This renders the panel content the FilterableTabState shows when filters are visible.
  @override
  Widget buildFilterContent(
      BuildContext context,
      List<dynamic> allItems,
      List<dynamic> filteredItems,
      ) {
    final payments = List<PaymentModel>.from(filteredItems.cast<PaymentModel>());

    // Inline summary (no state churn)
    double totalPaid = 0, totalDue = 0;
    int completedCount = 0, plannedCount = 0;
    for (final p in payments) {
      if (p.status == PaymentStatus.completed) {
        totalPaid += p.amount;
        completedCount++;
      } else if (p.status == PaymentStatus.planned) {
        totalDue += p.amount;
        plannedCount++;
      }
    }

    final statusOptions = {for (var s in PaymentStatus.values) s: s.label};

    return buildFilterSection(
      title: 'Ödeme Yönetimi',
      filterWidgets: [
        if (payments.isNotEmpty) ...[
          _buildFinancialSummary(
            totalPaid: totalPaid,
            totalDue: totalDue,
            completedCount: completedCount,
            plannedCount: plannedCount,
          ),
          const SizedBox(height: 16),
        ],
        buildSearchField(hintText: 'Not veya ödeme tutarı ile ara...'),
        const SizedBox(height: 8),
        const Text(
          'Not: Tutar araması için tam değeri girin (örn: 5000)',
          style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 16),
        buildReactiveFilterWidget<PaymentStatus>(
          title: 'Durum Filtresi:',
          initialValue: _tempStatus,
          options: statusOptions,
          onSelected: (status) => _tempStatus = status,
        ),
        const SizedBox(height: 16),
        buildDateRangeFilter(),
        buildFilterActionButtons(),
      ],
    );
  }
// Add this helper inside _PaymentsTabState
  Widget _buildHeaderActions(BuildContext context, int filteredCount, int totalCount) {
    // Reuse your existing summary widget
    final summary = buildActiveFiltersSummary(filteredCount, totalCount);

    // Prebuild buttons (kept identical to yours)
    final filterBtn = ElevatedButton.icon(
      onPressed: toggleFilters,
      icon: const Icon(Icons.filter_alt),
      label: const Text('Filtrele'),
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        visualDensity: VisualDensity.compact, // helps tighter fit
      ),
    );

    final addBtn = ElevatedButton.icon(
      icon: const Icon(Icons.add),
      label: const Text('Yeni ödeme ekle'),
      onPressed: () => _showAddPaymentDialog(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        visualDensity: VisualDensity.compact,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tune threshold if you like
        final bool isNarrow = constraints.maxWidth < 780;

        if (isNarrow) {
          // Narrow: wrap buttons to new lines + summary below -> no overflow
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  filterBtn,
                  addBtn,
                ],
              ),
              const SizedBox(height: 12),
              // Put summary below, let it take full width
              summary,
            ],
          );
        } else {
          // Wide: keep everything in one row with Expanded summary
          return Row(
            children: [
              filterBtn,
              const SizedBox(width: 12),
              addBtn,
              const SizedBox(width: 12),
              Expanded(child: summary),
            ],
          );
        }
      },
    );
  }

  @override
  Widget buildList(BuildContext context, List<dynamic> dataList) {
    final filteredItems = getFilteredItems(dataList);

    return Column(
      children: [
        // Header area made overflow-proof
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildHeaderActions(context, filteredItems.length, dataList.length),
        ),
        Expanded(
          child: filteredItems.isEmpty
              ? buildEmptyState()
              : buildFilteredContent(context, filteredItems),
        ),
      ],
    );
  }

  @override
  Widget buildFilteredContent(BuildContext context, List<dynamic> filteredItems) {
    final payments = List<PaymentModel>.from(filteredItems.cast<PaymentModel>());

    // Sort once per build
    payments.sort((a, b) {
      final aDate = a.paymentDate ?? a.dueDate ?? DateTime(1900);
      final bDate = b.paymentDate ?? b.dueDate ?? DateTime(1900);
      return bDate.compareTo(aDate);
    });

    // Stable identity for reconciliation
    final listKey = ValueKey<String>(payments.map((p) => p.paymentId).join('|'));

    return Scrollbar(
      controller: _listCtrl,
      child: ListView.builder(
        key: listKey,
        controller: _listCtrl,
        padding: const EdgeInsets.all(16),
        itemCount: payments.length,
        itemBuilder: (context, i) => _buildPaymentCard(context, payments[i]),
      ),
    );
  }

  Widget _buildFinancialSummary({
    required double totalPaid,
    required double totalDue,
    required int completedCount,
    required int plannedCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Finansal Özet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatCard(
                icon: Icons.check_circle_outline,
                title: 'Tamamlanan',
                value: '$completedCount',
                subValue: _currencyFormat.format(totalPaid),
                color: Colors.green,
              ),
              const SizedBox(width: 16),
              _buildStatCard(
                icon: Icons.pending_actions,
                title: 'Planlanmış',
                value: '$plannedCount',
                subValue: _currencyFormat.format(totalDue),
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subValue,
    required Color color,
  }) {
    return Flexible(
      fit: FlexFit.tight,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          Text(subValue, style: TextStyle(color: Colors.grey[600], fontSize: 12), overflow: TextOverflow.ellipsis, maxLines: 1),
        ]),
      ),
    );
  }

  Widget _buildPaymentCard(BuildContext context, PaymentModel payment) {
    final Color statusColor = payment.status == PaymentStatus.completed
        ? Colors.green
        : payment.status == PaymentStatus.planned
        ? Colors.orange
        : Colors.red;

    final IconData statusIcon = payment.status == PaymentStatus.completed
        ? Icons.check_circle_outline
        : payment.status == PaymentStatus.planned
        ? Icons.pending_actions
        : Icons.cancel_outlined;

    final String dateText = (payment.paymentDate != null)
        ? 'Ödeme Tarihi: ${_dateFormat.format(payment.paymentDate!)}'
        : (payment.dueDate != null)
        ? 'Vade Tarihi: ${_dateFormat.format(payment.dueDate!)}'
        : 'Tarih belirtilmemiş';

    return Card(
      key: ValueKey(payment.paymentId),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.5), width: 1),
      ),
      child: InkWell(
        onTap: () => _showEditPaymentDialog(context, payment),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_currencyFormat.format(payment.amount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 4),
                  Text(payment.status.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            // Subscription package name (all payments must have subscriptionId)
            if (payment.subscriptionId != null)
              FutureBuilder<String>(
                future: _getSubscriptionName(payment.subscriptionId!),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  final subName = snapshot.data!;
                  if (subName.isEmpty) return const SizedBox.shrink();
                  
                  return Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.card_membership, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Paket: $subName',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            Text(dateText, style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
            if (payment.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(payment.notes!, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.end, children: [
              LabeledActionButton(
                dense: true,
                icon: Icons.edit,
                label: 'Düzenle',
                onPressed: () => _showEditPaymentDialog(context, payment),
              ),
              LabeledActionButton(
                dense: true,
                icon: Icons.delete,
                label: 'Sil',
                foregroundColor: Colors.red,
                onPressed: () => _showDeletePaymentDialog(payment),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showEditPaymentDialog(BuildContext context, PaymentModel payment) {
    showDialog(
      context: context,
      builder: (_) => EditPaymentDialog(
        payment: payment,
         onPaymentUpdated: () {
          // Provider listener will handle refresh via notifyListeners()
          // No need to manually call refreshData() to avoid double-refresh
        },
      ),
    );
  }

  // RESTORED: Delete flow with dialog feedback + refresh
  Future<void> _showDeletePaymentDialog(PaymentModel payment) async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Ödeme Sil',
      message: 'Bu ödemeyi silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );
    if (!confirmed) return;
    if (!mounted) return;

    try {
      final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
      await paymentProvider.deletePayment(payment.paymentId, payment.userId);
      if (!mounted) return;
      await DialogUtils.openInfo(context, title: 'Başarılı', message: 'Ödeme silindi.');
      // Provider listener will handle refresh via notifyListeners()
      // No need to manually call refreshData() to avoid double-refresh
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Silme sırasında hata: $e');
    }
  }

  void _showAddPaymentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AddPaymentDialog(
          userId: widget.userId,
          onPaymentAdded: () {
            // Provider listener will handle refresh via notifyListeners()
            // No need to manually call refreshData() to avoid double-refresh
          },
        );
      },
    );
  }

}
