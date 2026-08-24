import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:ngy_app/tabs/appointments_tab.dart';
import '../dialogs/edit_sub_dialog.dart';
import '../dialogs/add_sub_dialog.dart';
import '../models/logger.dart';
import '../models/subs_model.dart';
import '../models/appointment_model.dart';
import '../models/filter_params.dart';
import '../pages/bulk_add_page.dart';
import '../providers/sub_provider.dart';
import '../providers/appointment_manager.dart';
import '../utils/dialog_utils.dart';
import 'basetab.dart';
import 'filterable_tab.dart';
import '../widgets/labeled_action_button.dart';
final Logger logger = Logger.forClass(SubscriptionsTab);
class SubscriptionsTab extends BaseTab<SubProvider> {
  const SubscriptionsTab({super.key, required super.userId})
      : super(allDataLabel: 'Tüm Paketler', subscriptionDataLabel: 'Aktif Paketler');

  @override
  SubProvider getProvider(BuildContext context) => Provider.of<SubProvider>(context, listen: false);

  @override
  Future<List<dynamic>> getDataList(SubProvider provider, bool showAllData, {FilterParams? filterParams}) =>
      provider.fetchSubscriptions(userId: userId, showAllSubscriptions: showAllData, filterParams: filterParams as SubscriptionFilterParams?);

  @override
  BaseTabState<SubProvider, BaseTab<SubProvider>> createState() => _SubscriptionsTabState();
}

class _SubscriptionsTabState extends FilterableTabState<SubProvider, SubscriptionsTab> {
  // Persisted (applied) filter
  SubActiveStatus? _selectedStatus;

  // Temp (UI) filter — reactive but localized
  late final ValueNotifier<SubActiveStatus?> _tempStatusVN;

  // Provider + scroll
  // Both are resolved from a post-frame callback, so they stay nullable: the
  // tab can be disposed (or a fetch can start) before that callback runs, and
  // neither dispose() nor a fetch may trip over an unassigned late field.
  SubProvider? _subProvider;
  AppointmentManager? _appointmentManager;
  final ScrollController _listCtrl = ScrollController();
  
  // Cache for subscription appointments
  final Map<String, List<AppointmentModel>> _subscriptionAppointments = {};
  
  // Toggle for appointment status coloring (true = use status colors, false = use neutral teal)
  final bool _isApptStatusColorful = true;

  // Cache formatters & static maps
  static final DateFormat _df = DateFormat('d MMMM y', 'tr_TR');
  static const Map<SubsMeetingType, String> _meetingTypeText = {
    SubsMeetingType.online: 'Online',
    SubsMeetingType.faceToFace: 'Yüz Yüze',
    SubsMeetingType.hybrid: 'Online + Yüz Yüze',
  };

  @override
  void initState() {
    super.initState();
    _tempStatusVN = ValueNotifier<SubActiveStatus?>(_selectedStatus);

    // Hook provider after first frame so context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<SubProvider>();
      _subProvider = provider;
      _appointmentManager = context.read<AppointmentManager>();
      provider.addListener(_onSubChanged);
    });
  }

  void _onSubChanged() {
    final provider = _subProvider;
    if (provider == null || !provider.subChanged) return;
    provider.resetSubChanged();
    // Clear appointment cache before refreshing to prevent duplicates
    _subscriptionAppointments.clear();
    // Deferred: this runs inside notifyListeners(), which a write can fire
    // while a build is in progress.
    scheduleRefresh();
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    _subscriptionAppointments.clear();
    _subProvider?.removeListener(_onSubChanged);
    _tempStatusVN.dispose();
    super.dispose();
  }
  
  @override
  void refreshData() {
    // Clear appointment cache when refreshing data
    _subscriptionAppointments.clear();
    super.refreshData();
  }
  
  /// Pre-fetches appointments for all subscriptions in parallel
  /// Call this after subscriptions are loaded to populate the cache
  Future<void> _prefetchAppointmentsForSubscriptions(List<SubscriptionModel> subscriptions) async {
    if (subscriptions.isEmpty) return;
    
    // Fetch all appointments in parallel
    final futures = subscriptions.map((sub) async {
      final cacheKey = sub.subscriptionId;
      
      // Skip if already cached
      if (_subscriptionAppointments.containsKey(cacheKey)) return;
      
      try {
        final manager =
            _appointmentManager ?? context.read<AppointmentManager>();
        final appointments = await manager.fetchAppointments(
          sub.subscriptionId,
          userId: sub.userId,
          showAllAppointments: false,
        );
        
        // Sort appointments by date
        appointments.sort((a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime));
        
        if (mounted) {
          _subscriptionAppointments[cacheKey] = appointments;
        }
      } catch (e) {
        debugPrint('Error fetching appointments for subscription ${sub.subscriptionId}: $e');
        if (mounted) {
          _subscriptionAppointments[cacheKey] = [];
        }
      }
    });
    
    await Future.wait(futures);
    
    // Trigger rebuild after all appointments are fetched
    if (mounted) {
      setState(() {});
    }
  }
  
  /// Gets cached appointments for a subscription (returns empty list if not cached yet)
  List<AppointmentModel> _getCachedAppointments(String subscriptionId) {
    return _subscriptionAppointments[subscriptionId] ?? [];
  }

  // ---------- FilterableTabState hooks ----------

  @override
  void resetAdditionalTempFilters() {
    _tempStatusVN.value = _selectedStatus;
  }

  @override
  void applyAdditionalTempFilters() {
    _selectedStatus = _tempStatusVN.value;
  }

  @override
  void resetAdditionalFilters() {
    _selectedStatus = null;
    resetTempFiltersToDefaults();
  }

  @override
  void resetTempFiltersToDefaults() {
    _tempStatusVN.value = null;
  }

  @override
  bool hasAdditionalActiveFilters() => _selectedStatus != null;

  @override
  FilterParams? buildFilterParams() {
    return SubscriptionFilterParams(
      searchQuery: searchQuery.isNotEmpty ? searchQuery : null,
      dateRange: selectedDateRange,
      status: _selectedStatus?.label,
    );
  }

  // ---------- Filter UI ----------

  @override
  Widget buildList(BuildContext context, List<dynamic> dataList) {
    final filteredItems = getFilteredItems(dataList);

    // Business rule: a customer may only have one active package at a time.
    // Detect (from the full fetched set, not the client-filtered view) whether
    // this customer has more than one active package and warn the admin.
    final activeSubs = dataList
        .cast<SubscriptionModel>()
        .where((s) => s.status.isActive)
        .toList();

    return Column(
      children: [
        if (activeSubs.length > 1) _buildMultipleActiveWarning(activeSubs),
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: toggleFilters,
                icon: const Icon(Icons.filter_alt),
                label: const Text('Filtrele'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showAddSubscriptionDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Yeni paket ekle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: buildActiveFiltersSummary(filteredItems.length, dataList.length)),
            ],
          ),
        ),
        Expanded(
          child: filteredItems.isEmpty ? buildEmptyState() : buildFilteredContent(context, filteredItems),
        ),
      ],
    );
  }

  /// Impossible-to-miss banner shown at the very top of the subscriptions list
  /// when a customer has more than one active package, violating the
  /// "one active package at a time" rule.
  Widget _buildMultipleActiveWarning(List<SubscriptionModel> activeSubs) {
    final packageNames = activeSubs
        .map((s) => s.packageName.trim().isNotEmpty
            ? s.packageName.trim()
            : '(İsimsiz paket)')
        .join(', ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade900, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DİKKAT: Birden fazla aktif paket bulundu!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Bir danışanın aynı anda yalnızca bir aktif paketi olabilir. '
                  'Lütfen adı şu olan paketleri inceleyiniz: $packageNames',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSubscriptionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AddSubscriptionDialog(
          userId: widget.userId,
          onSubscriptionAdded: () {
            // Note: refreshData is triggered automatically via _onSubChanged listener
            // when provider calls notifyListeners() - no need to call it here
          },
        );
      },
    );
  }

  @override
  Widget buildFilterContent(BuildContext context, List<dynamic> allItems, List<dynamic> filteredItems) {
    final statusOptions = {
      for (var st in SubActiveStatus.values) st: st.displayName,
    };

    return buildFilterSection(
      title: 'Paket Yönetimi',
      filterWidgets: [
        buildSearchField(hintText: 'Paket adına göre ara...'),
        const SizedBox(height: 16),

        // Localized rebuilds: only this chip group rebuilds when status changes
        ValueListenableBuilder<SubActiveStatus?>(
          valueListenable: _tempStatusVN,
          builder: (context, value, _) {
            return buildFilterWidget<SubActiveStatus>(
              title: 'Durum:',
              selectedValue: value,
              options: statusOptions,
              onSelected: (st) => _tempStatusVN.value = st,
            );
          },
        ),

        const SizedBox(height: 16),
        buildDateRangeFilter(
          placeholderText: 'Başlangıç Tarihi Aralığı',
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        ),
        buildFilterActionButtons(),
      ],
    );
  }

  // ---------- List ----------

  @override
  Widget buildFilteredContent(BuildContext context, List<dynamic> filteredItems) {
    final subs = filteredItems.cast<SubscriptionModel>()..sort((a, b) => b.startDate.compareTo(a.startDate));

    if (subs.isEmpty) {
      return buildEmptyState(
        icon: Icons.calendar_today,
        message: 'Paket bulunamadı',
        submessage: 'Filtreleri değiştirerek tekrar deneyin',
      );
    }

    // Pre-fetch appointments for all subscriptions (runs once, caches results)
    // Only fetch if not all are already cached
    final needsFetch = subs.any((s) => !_subscriptionAppointments.containsKey(s.subscriptionId));
    if (needsFetch) {
      // Trigger async fetch - will call setState when complete
      _prefetchAppointmentsForSubscriptions(subs);
    }

    return Scrollbar(
      controller: _listCtrl,
      child: ListView.separated(
        controller: _listCtrl,
        itemCount: subs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemBuilder: (context, index) => _buildSubscriptionCard(context, subs[index]),
      ),
    );
  }

  // ---------- Card ----------

  Widget _buildSubscriptionCard(BuildContext context, SubscriptionModel s) {
    // Get appointments from cache synchronously (no FutureBuilder rebuild)
    final appointments = _getCachedAppointments(s.subscriptionId);
    return _buildSubscriptionCardContent(context, s, appointments);
  }

  Widget _buildStatusBadge(SubActiveStatus status) {
    final Color bgColor = switch (status) {
      SubActiveStatus.activeWeekly => Colors.green.shade100,
      SubActiveStatus.activeWeightTracking => Colors.teal.shade100,
      SubActiveStatus.frozen => Colors.blue.shade100,
      SubActiveStatus.completed => Colors.grey.shade200,
    };
    final Color fgColor = switch (status) {
      SubActiveStatus.activeWeekly => Colors.green.shade800,
      SubActiveStatus.activeWeightTracking => Colors.teal.shade800,
      SubActiveStatus.frozen => Colors.blue.shade800,
      SubActiveStatus.completed => Colors.grey.shade700,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(color: fgColor, fontWeight: FontWeight.bold),
      ),
    );
  }
  
  Widget _buildSubscriptionCardContent(BuildContext context, SubscriptionModel s, List<AppointmentModel> appointments) {
    final remainingPostponements = s.remainingPostponements;
    final noPostponeLeft = remainingPostponements <= 0;
    // Weight-tracking packages are free: don't show any payment info.
    final bool showPayment = s.status != SubActiveStatus.activeWeightTracking;
    return Card(
      key: ValueKey(s.subscriptionId),
      margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade400, width: 2.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEditSubscriptionDialog(context, s),
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Quick summary banner
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 8, // Flexible spacing between elements
              runSpacing: 4, // Spacing between rows if it wraps
              children: [
                Text(
                  'Özet: ${s.totalMeetings} görüşme, ${s.meetingsCompleted + s.meetingsBurned} tamamlandı',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                if (showPayment)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    decoration: BoxDecoration(
                      color: s.amountPaid < s.totalAmount ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      s.amountPaid < s.totalAmount 
                          ? 'Eksik Ödeme' 
                          : 'Ödeme Tamam',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: s.amountPaid < s.totalAmount ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Row(children: [
                Flexible(
                  child: Text(
                    s.packageName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(s.status),
              ]),
            ),
            // Wrap, not Row: on a narrow phone three labelled buttons drop
            // onto a second line instead of overflowing.
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                LabeledActionButton(
                  dense: true,
                  icon: Icons.playlist_add,
                  label: 'Toplu Ekle',
                  tooltip: 'Toplu Ödeme/Randevu Ekle',
                  foregroundColor: Colors.green,
                  onPressed: () => _openBulkAdd(context, s),
                ),
                LabeledActionButton(
                  dense: true,
                  icon: Icons.edit,
                  label: 'Düzenle',
                  foregroundColor: Colors.blue,
                  onPressed: () => _showEditSubscriptionDialog(context, s),
                ),
                LabeledActionButton(
                  dense: true,
                  icon: Icons.delete,
                  label: 'Sil',
                  foregroundColor: Colors.red,
                  onPressed: () => _showDeleteConfirmationDialog(context, s),
                ),
              ],
            ),
          ]),

          if (noPostponeLeft && s.allowedPostponements > 0)
            Row(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Erteleme hakkı kalmadı',
                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ]),
                ),
              ],
            ),

          const SizedBox(height: 8),
          Row(children: [
            const Text('Paket Tipi: ', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(s.packageType?.label ?? 'Belirtilmemiş'),
          ]),
          const SizedBox(height: 8),
          Text('Başlangıç: ${_df.format(s.startDate)}', style: const TextStyle(fontSize: 14)),

          // Freeze date shown for frozen packages.
          if (s.status == SubActiveStatus.frozen) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.ac_unit, size: 16, color: Colors.blue.shade800),
              const SizedBox(width: 4),
              Text(
                'Dondurulma Tarihi: ${s.freezeDate != null ? _df.format(s.freezeDate!) : 'Belirtilmemiş'}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ]),
          ],
          const SizedBox(height: 8),

          Row(children: [
            const Text('Görüşme Türü: ', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(_meetingTypeText[s.meetingType] ?? ''),
          ]),

          if (s.meetingType == SubsMeetingType.hybrid)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Text('Online: ${s.onlineMeetings ?? 0}'),
                const SizedBox(width: 16),
                Text('Yüz Yüze: ${s.faceToFaceMeetings ?? 0}'),
              ]),
            ),

          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Kalan: ${s.remainingMeetings}/${s.totalMeetings} görüşme',style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              'Erteleme: ${s.postponementsUsed}/${s.allowedPostponements}',
              style: noPostponeLeft && s.allowedPostponements > 0
                  ? TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)
                  : null,
            ),
          ]),
          
          // Payment information (hidden for free weight-tracking packages)
          if (showPayment) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            
            // Payment summary
            Row(
              children: [
                const Text('Ödeme Bilgisi: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '${NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2).format(s.amountPaid)} / ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: s.amountPaid < s.totalAmount ? Colors.red : Colors.green,
                  ),
                ),
                Text(
                  NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2).format(s.totalAmount),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            
            // Payment status indicator
            if (s.amountPaid < s.totalAmount)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Eksik Ödeme: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2).format(s.totalAmount - s.amountPaid)}',
                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
            
          // Appointment dates section
          if (appointments.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            
            // Filter to only show completed, scheduled (planned), and burned appointments
            ...() {
              final visibleAppointments = appointments
                  .where((a) => a.status == AppointmentStatus.completed || a.status == AppointmentStatus.scheduled || a.status == AppointmentStatus.burned)
                  .toList();
              final hasOtherStatuses = appointments.any(
                (a) => a.status != AppointmentStatus.completed && a.status != AppointmentStatus.scheduled && a.status != AppointmentStatus.burned,
              );
              final showMoreButton = visibleAppointments.length > 5 || hasOtherStatuses;
              
              return [
                // Appointment dates header
                const Text('Randevu Tarihleri:', style: TextStyle(fontWeight: FontWeight.bold)),
                
                const SizedBox(height: 4),
                
                // Appointment dates list - show only first 5 of completed/scheduled
                if (visibleAppointments.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: visibleAppointments.take(7).map((appointment) {
                      // Use status color if _isApptStatusColorful is true, otherwise use teal
                      final Color statusColor = _isApptStatusColorful 
                          ? appointment.status.getColor() 
                          : Colors.teal.shade700;
                      final IconData chipIcon = appointment.status.getIcon();
                      // Use meeting type for background/border color
                      final Color bgColor = appointment.meetingType.getBgColor();
                      final Color borderColor = appointment.meetingType.getBorderColor();
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(chipIcon, size: 14, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              _df.format(appointment.appointmentDateTime),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                
                // Show more button if >5 visible appointments OR has other statuses (burned/postponed)
                if (showMoreButton) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => _showAllAppointments(context, s, appointments),
                    child: const Text('Tümünü Göster'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ];
            }(),
          ],

        ]),
        ),
      ),
    );
  }

  // ---------- Dialogs / Actions ----------

  /// Opens the bulk add page for this package. Every appointment/payment created
  /// there is linked to [s]. Data is refreshed on return so the card reflects
  /// the newly added appointments and updated paid total.
  void _openBulkAdd(BuildContext context, SubscriptionModel s) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => BulkAddPage(subscription: s)))
        .then((_) {
      if (mounted) refreshData();
    });
  }

  Future<void> _showEditSubscriptionDialog(BuildContext context, SubscriptionModel s) async {
    try {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => EditSubscriptionDialog(
          subscription: s,
          onSubscriptionUpdated: () {
            // Note: refreshData is triggered automatically via _onSubChanged listener
            // when provider calls notifyListeners() - no need to call it here
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Paket düzenleme açılamadı: $e');
    }
  }

  Future<void> _showDeleteConfirmationDialog(BuildContext context, SubscriptionModel s) async {
    try {
      final confirmed = await DialogUtils.openConfirm(
        context,
        title: 'Paket Silme Onayı',
        message: 'Bu paketi silmek istediğinizden emin misiniz?\n\n${s.packageName}\n\n'
            'Bu paket silindiğinde, pakete bağlı TÜM randevular ve ödemeler de silinecektir.\n\n'
            'Bu işlem geri alınamaz.',
        confirmText: 'Sil',
        cancelText: 'İptal',
      );
      if (confirmed) {
        await _deleteSubscription(s);
      }
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'İşlem sırasında bir hata oluştu: $e');
    }
  }

  Future<void> _deleteSubscription(SubscriptionModel s) async {
    try {
      // Show loading dialog
      bool loadingOpen = false;
      if (mounted) {
        DialogUtils.openLoading(context, message: 'Paket siliniyor...');
        loadingOpen = true;
      }
      
      final subProvider = context.read<SubProvider>();
      final success = await subProvider.deleteSubscription(userId: s.userId, subscriptionId: s.subscriptionId);

      // Close loading dialog
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      
      if (success && mounted) {
        await DialogUtils.openInfo(context, title: 'Başarılı', message: 'Paket silindi.');
        // Note: refreshData is triggered automatically via _onSubChanged listener
        // when provider calls notifyListeners() - no need to call it here
      }
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Paket silinirken bir hata oluştu: $e');
    }
  }
  
  void _showAllAppointments(BuildContext context, SubscriptionModel subscription, List<AppointmentModel> appointments) {
    if (appointments.isEmpty || !mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${subscription.packageName} - Randevular'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Toplam ${appointments.length} randevu'),
                const SizedBox(height: 16),
                ...appointments.map((appointment) {
                  // Use status color if _isApptStatusColorful is true, otherwise use teal
                  final Color statusColor = _isApptStatusColorful 
                      ? appointment.status.getColor() 
                      : Colors.teal.shade700;
                  final IconData statusIcon = appointment.status.getIcon();
                  // Use meeting type for background color
                  final Color bgColor = appointment.meetingType.getBgColor();
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            statusIcon,
                            color: statusColor,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_df.format(appointment.appointmentDateTime)} - ${DateFormat('HH:mm').format(appointment.appointmentDateTime)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            appointment.status.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}
