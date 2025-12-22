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
import '../providers/sub_provider.dart';
import '../providers/appointment_manager.dart';
import '../utils/dialog_utils.dart';
import 'basetab.dart';
import 'filterable_tab.dart';
final Logger logger = Logger.forClass(SubscriptionsTab);
class SubscriptionsTab extends BaseTab<SubProvider> {
  const SubscriptionsTab({super.key, required super.userId})
      : super(allDataLabel: 'Tüm Abonelikler', subscriptionDataLabel: 'Aktif Abonelikler');

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
  late final SubProvider _subProvider;
  late final AppointmentManager _appointmentManager;
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
      _subProvider = context.read<SubProvider>();
      _appointmentManager = context.read<AppointmentManager>();
      _subProvider.addListener(_onSubChanged);
    });
  }

  void _onSubChanged() {
    if (_subProvider.subChanged) {
      _subProvider.resetSubChanged();
      // Clear appointment cache before refreshing to prevent duplicates
      _subscriptionAppointments.clear();
      refreshData(); // triggers one rebuild for the list only
    }
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    _subscriptionAppointments.clear();
    // _subProvider is set in a post-frame callback; guard it
    try {
      _subProvider.removeListener(_onSubChanged);
    } catch (_) {
      // no-op if not attached yet
    }
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
        final appointments = await _appointmentManager.fetchAppointments(
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

    return Column(
      children: [
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
                label: const Text('Yeni abonelik ekle'),
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
      for (var st in SubActiveStatus.values) st: st == SubActiveStatus.active ? 'Aktif' : 'Tamamlandı',
    };

    return buildFilterSection(
      title: 'Abonelik Yönetimi',
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
        message: 'Abonelik bulunamadı',
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
  
  Widget _buildSubscriptionCardContent(BuildContext context, SubscriptionModel s, List<AppointmentModel> appointments) {
    final remainingPostponements = s.allowedPostponements - s.postponementsUsed;
    final noPostponeLeft = remainingPostponements <= 0;
    return Card(
      key: ValueKey(s.subscriptionId),
      margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
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
              child: Text(
                s.packageName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Row(children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue),
                tooltip: 'Düzenle',
                onPressed: () => _showEditSubscriptionDialog(context, s),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Sil',
                onPressed: () => _showDeleteConfirmationDialog(context, s),
              ),
            ]),
          ]),

          if (noPostponeLeft)
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
          Text('Başlangıç: ${_df.format(s.startDate)}', style: const TextStyle(fontSize: 14)),
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
            Text('Kalan: ${s.totalMeetings > 0 ? (s.totalMeetings - s.meetingsCompleted - s.meetingsBurned)
              .clamp(0, s.totalMeetings) : 0}/${s.totalMeetings} görüşme',style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              'Erteleme: ${s.postponementsUsed}/${s.allowedPostponements}',
              style: noPostponeLeft
                  ? TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)
                  : null,
            ),
          ]),
          
          // Payment information
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
                
                // Show more button if >5 visible appointments OR has other statuses (burned/canceled/postponed)
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

          const SizedBox(height: 8),
          Row(children: [
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: s.status == SubActiveStatus.active ? Colors.green.shade100 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                s.status == SubActiveStatus.active ? 'Aktif' : 'Tamamlandı',
                style: TextStyle(
                  color: s.status == SubActiveStatus.active ? Colors.green.shade800 : Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ---------- Dialogs / Actions ----------

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
      await DialogUtils.openError(context, title: 'Hata', message: 'Abonelik düzenleme açılamadı: $e');
    }
  }

  Future<void> _showDeleteConfirmationDialog(BuildContext context, SubscriptionModel s) async {
    try {
      final confirmed = await DialogUtils.openConfirm(
        context,
        title: 'Abonelik Silme Onayı',
        message: 'Bu aboneliği silmek istediğinizden emin misiniz?\n\n${s.packageName}\n\nBu işlem geri alınamaz.',
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
        DialogUtils.openLoading(context, message: 'Abonelik siliniyor...');
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
        await DialogUtils.openInfo(context, title: 'Başarılı', message: 'Abonelik silindi.');
        // Note: refreshData is triggered automatically via _onSubChanged listener
        // when provider calls notifyListeners() - no need to call it here
      }
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(context, title: 'Hata', message: 'Abonelik silinirken bir hata oluştu: $e');
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
