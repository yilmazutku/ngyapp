import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/appointment_model.dart';
import '../models/filter_params.dart';
import '../providers/appointment_colors_provider.dart';
import '../providers/appointment_manager.dart';
import '../providers/sub_provider.dart';
import '../dialogs/edit_appointment_dialog.dart';
import '../dialogs/add_appointment_dialog.dart';
import '../utils/dialog_utils.dart';
import 'basetab.dart';
import 'filterable_tab.dart';

/// Extension to add color and icon getters to AppointmentStatus
extension AppointmentStatusExtension on AppointmentStatus {
  Color getColor() {
    switch (this) {
      case AppointmentStatus.completed:
        return Colors.green;
      case AppointmentStatus.scheduled:
        return Colors.blue;
      case AppointmentStatus.burned:
        return Colors.orange;
      case AppointmentStatus.canceled:
        return Colors.red;
      case AppointmentStatus.postponed:
        return Colors.purple;
    }
  }

  IconData getIcon() {
    switch (this) {
      case AppointmentStatus.completed:
        return Icons.check;
      case AppointmentStatus.scheduled:
        return Icons.event;
      case AppointmentStatus.burned:
        return Icons.local_fire_department;
      case AppointmentStatus.canceled:
        return Icons.cancel;
      case AppointmentStatus.postponed:
        return Icons.update;
    }
  }
}

/// Extension to add icon getter to MeetingType
extension MeetingTypeExtension on MeetingType {
  IconData getIcon() {
    switch (this) {
      case MeetingType.online:
        return Icons.video_call;
      case MeetingType.f2f:
        return Icons.person;

    }
  }
}

enum AppointmentSortOption { closestToToday, dateAscending, dateDescending }

extension AppointmentSortOptionExtension on AppointmentSortOption {
  String get label {
    switch (this) {
      case AppointmentSortOption.closestToToday:
        return 'En Yakın Randevu';
      case AppointmentSortOption.dateAscending:
        return 'Tarih Artan';
      case AppointmentSortOption.dateDescending:
        return 'Tarih Azalan';
    }
  }
}

class AppointmentsTab extends BaseTab<AppointmentManager> {
  const AppointmentsTab({super.key, required super.userId})
      : super(
    allDataLabel: 'Tüm Randevular',
    subscriptionDataLabel: 'Paket Randevuları',
  );

  @override
  AppointmentManager getProvider(BuildContext context) =>
      Provider.of<AppointmentManager>(context, listen: false);

  @override
  Future<List<dynamic>> getDataList(
      AppointmentManager provider,
      bool showAllData,
      {FilterParams? filterParams}
      ) {
    return provider.fetchAppointments(
      null,
      showAllAppointments: showAllData,
      userId: userId,
      filterParams: filterParams as AppointmentFilterParams?,
    );
  }

  @override
  createState() => _AppointmentsTabState();
}

class _AppointmentsTabState
    extends FilterableTabState<AppointmentManager, AppointmentsTab> {
  AppointmentStatus? _selectedStatus;
  MeetingType? _selectedType;
  AppointmentSortOption _sortOption = AppointmentSortOption.dateAscending;

  // temp filters (for the modal)
  AppointmentStatus? _tempStatus;
  MeetingType? _tempType;
  AppointmentSortOption _tempSortOption = AppointmentSortOption.dateAscending;

  // final DateFormat _longDateFormat = DateFormat('dd MMMM yyyy, HH:mm');
  // final DateFormat _shortDateFormat = DateFormat('dd.MM.yyyy');
  final DateFormat _shortDf = DateFormat('HH:mm', 'tr_TR');
// if you still want the short one:
  final DateFormat _longDf = DateFormat('d MMMM yyyy', 'tr_TR');

  // ---- SCROLL IMPROVEMENTS ----
  // Explicit controller for the main list to avoid PrimaryScrollController mismatches
  final ScrollController _listCtrl = ScrollController();
  
  // Cache for subscription names
  final Map<String, String> _subscriptionCache = {};
  
  // Toggle for appointment status coloring (true = use status colors, false = use neutral teal)
  final bool _isApptStatusColorful = true;

  @override
  void initState() {
    super.initState();
    _tempStatus = _selectedStatus;
    _tempType = _selectedType;
    _tempSortOption = _sortOption;

    // Make sure admin-configured background colors are loaded before we
    // render appointment cards (no-op after the first call per session).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await Provider.of<AppointmentColorsProvider>(context, listen: false)
            .fetchColors();
        if (mounted) setState(() {});
      } catch (_) {
        // Failures fall back to built-in default colors; nothing to do.
      }
    });
  }

  @override
  void dispose() {
    _listCtrl.dispose(); // <-- important
    super.dispose();
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
    // If subscription was deleted, show "Silinmiş Paket" instead of hiding
    final displayName = name ?? 'Silinmiş Paket';
    _subscriptionCache[subscriptionId] = displayName;
    return displayName;
  }

  @override
  void resetAdditionalTempFilters() {
    _tempStatus = _selectedStatus;
    _tempType = _selectedType;
    _tempSortOption = _sortOption;
  }

  @override
  void applyAdditionalTempFilters() {
    _selectedStatus = _tempStatus;
    _selectedType = _tempType;
    _sortOption = _tempSortOption;
  }

  @override
  void resetAdditionalFilters() {
    _selectedStatus = null;
    _selectedType = null;
    _sortOption = AppointmentSortOption.dateDescending;
    resetTempFiltersToDefaults();
  }

  @override
  void resetTempFiltersToDefaults() {
    _tempStatus = null;
    _tempType = null;
    _tempSortOption = AppointmentSortOption.dateDescending;
  }

  @override
  bool hasAdditionalActiveFilters() {
    return _selectedStatus != null ||
        _selectedType != null ||
        _sortOption != AppointmentSortOption.dateDescending;
  }

  @override
  FilterParams? buildFilterParams() {
    return AppointmentFilterParams(
      searchQuery: searchQuery.isNotEmpty ? searchQuery : null,
      dateRange: selectedDateRange,
      status: _selectedStatus?.label,
      meetingType: _selectedType?.label,
      sortOption: _sortOption.label,
    );
  }


  @override
  void onFilterApplied(List<dynamic> filteredItems) {
    // no-op: compute stats inline in buildFilterContent
  }

  @override
  Widget buildFilterContent(
      BuildContext context,
      List<dynamic> allItems,
      List<dynamic> filteredItems,
      ) {
    // Inline stats (no setState)
    final appts = filteredItems.cast<AppointmentModel>();
    int upcoming = 0, completed = 0, cancelled = 0;
    for (final a in appts) {
      if (a.status == AppointmentStatus.scheduled) upcoming++;
      else if (a.status == AppointmentStatus.completed) completed++;
      else if (a.status == AppointmentStatus.canceled) cancelled++;
    }

    final statusOptions = {for (var s in AppointmentStatus.values) s: s.label};
    final meetingTypeOptions = {for (var t in MeetingType.values) t: t.label};
    final sortOptions = {for (var o in AppointmentSortOption.values) o: o.label};

    return buildFilterSection(
      title: 'Randevu Yönetimi',
      filterWidgets: [
        
        if (appts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Flexible(
                  fit: FlexFit.tight,
                  child: _buildStatCard(
                    context,
                    count: upcoming,
                    label: 'Gelecek Randevular',
                    icon: Icons.event_note,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  fit: FlexFit.tight,
                  child: _buildStatCard(
                    context,
                    count: completed,
                    label: 'Tamamlanan',
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  fit: FlexFit.tight,
                  child: _buildStatCard(
                    context,
                    count: cancelled,
                    label: 'İptal Edilen',
                    icon: Icons.cancel_outlined,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),

        buildSearchField(hintText: 'Notlara göre ara...'),
        const SizedBox(height: 16),

        buildReactiveFilterWidget<AppointmentSortOption>(
          title: 'Randevu Tarihi Sıralama:',
          initialValue: _tempSortOption,
          options: sortOptions,
          showAllOption: false,
          onSelected: (opt) { if (opt != null) _tempSortOption = opt; },
        ),
        const SizedBox(height: 16),

        buildReactiveFilterWidget<AppointmentStatus>(
          title: 'Durum Filtresi:',
          initialValue: _tempStatus,
          options: statusOptions,
          onSelected: (s) => _tempStatus = s,
        ),
        const SizedBox(height: 16),

        buildReactiveFilterWidget<MeetingType>(
          title: 'Görüşme Tipi:',
          initialValue: _tempType,
          options: meetingTypeOptions,
          onSelected: (t) => _tempType = t,
        ),
        const SizedBox(height: 16),

        buildDateRangeFilter(
          placeholderText: 'Randevu Tarih Aralığı',
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        ),

        buildFilterActionButtons(),
      ],
    );
  }

  @override
  Widget buildList(BuildContext context, List<dynamic> dataList) {
    // Apply filters only once and store result
    final filteredItems = getFilteredItems(dataList);
    
    // Use a microtask to avoid blocking the UI thread
    Future.microtask(() {
      if (mounted) onFilterApplied(filteredItems);
    });

    // Memoize the filter button to avoid rebuilding
    final filterButton = ElevatedButton.icon(
      onPressed: toggleFilters,
      icon: const Icon(Icons.filter_alt),
      label: const Text('Filtrele'),
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );
    
    // Add button for appointments
    final addButton = ElevatedButton.icon(
      onPressed: () => _showAddAppointmentDialog(context),
      icon: const Icon(Icons.add),
      label: const Text('Randevu Ekle'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

    // Memoize the filter summary
    final filterSummary = buildActiveFiltersSummary(
        filteredItems.length, dataList.length);

    // Use const widgets where possible
    const sizedBox = SizedBox(width: 12);

    // Optimize content based on empty state
    final content = filteredItems.isEmpty
        ? buildEmptyState()
        : buildFilteredContent(context, filteredItems);

    // Build the layout without unnecessary nesting
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              filterButton,
              sizedBox,
              addButton,
              sizedBox,
              Expanded(child: filterSummary),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  @override
  Widget buildFilteredContent(BuildContext context, List<dynamic> filteredItems) {
    final appointments = filteredItems.cast<AppointmentModel>();
    final now = DateTime.now();

    // Sort appointments once (by option)
    // For postponed appointments, use postponedDate; otherwise use appointmentDateTime
    switch (_sortOption) {
      case AppointmentSortOption.closestToToday:
        appointments.sort((a, b) {
          final aDate = (a.status == AppointmentStatus.postponed && a.postponedDate != null)
              ? a.postponedDate!
              : a.appointmentDateTime;
          final bDate = (b.status == AppointmentStatus.postponed && b.postponedDate != null)
              ? b.postponedDate!
              : b.appointmentDateTime;
          final aDiff = aDate.difference(now).abs();
          final bDiff = bDate.difference(now).abs();
          return aDiff.compareTo(bDiff);
        });
        break;
      case AppointmentSortOption.dateAscending:
        // Tarih Artan: earliest dates first (2020 before 2025 before 2028)
        appointments.sort((a, b) {
          final aDate = (a.status == AppointmentStatus.postponed && a.postponedDate != null)
              ? a.postponedDate!
              : a.appointmentDateTime;
          final bDate = (b.status == AppointmentStatus.postponed && b.postponedDate != null)
              ? b.postponedDate!
              : b.appointmentDateTime;
          return aDate.compareTo(bDate);
        });
        break;
      case AppointmentSortOption.dateDescending:
        // Tarih Azalan: latest dates first (2028 before 2025 before 2020)
        appointments.sort((a, b) {
          final aDate = (a.status == AppointmentStatus.postponed && a.postponedDate != null)
              ? a.postponedDate!
              : a.appointmentDateTime;
          final bDate = (b.status == AppointmentStatus.postponed && b.postponedDate != null)
              ? b.postponedDate!
              : b.appointmentDateTime;
          return bDate.compareTo(aDate);
        });
        break;
    }

    // Group by date (dd.MM.yyyy)
    // Always use appointmentDateTime for grouping (don't separate postponed appointments)
    final Map<String, List<AppointmentModel>> grouped = {};
    for (final a in appointments) {
      final key = _longDf.format(a.appointmentDateTime);
      (grouped[key] ??= []).add(a);
    }

    // Sort group keys by actual date, not string order
    final keys = grouped.keys.toList();
    keys.sort((a, b) {
      final da = _longDf.parse(a);
      final db = _longDf.parse(b);
      switch (_sortOption) {
        case AppointmentSortOption.closestToToday:
          return da.difference(now).abs().compareTo(db.difference(now).abs());
        case AppointmentSortOption.dateAscending:
          return da.compareTo(db);           // ascending date (earliest first)
        case AppointmentSortOption.dateDescending:
          return db.compareTo(da);           // descending date (latest first)
      }
    });

    // Stable identity for the whole visible set
    final listKey = ValueKey<String>(
      appointments.map((a) => a.appointmentId).join('|'),
    );

    return Scrollbar(
      controller: _listCtrl,
      thumbVisibility: true,
      child: ListView.builder(
       // cacheExtent: 10,   // prebuild a bit more offscreen
        key: listKey,
        controller: _listCtrl,
        primary: false,
        padding: const EdgeInsets.all(16),
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final dateKey = keys[index];
          final dayList = grouped[dateKey]!;

          return Column(
            key: ValueKey('day_$dateKey'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  dateKey,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...dayList.map((a) => KeyedSubtree(
                key: ValueKey(a.appointmentId),
                child: _buildAppointmentCard(context, a),
              )),
              if (index < keys.length - 1) const Divider(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
      BuildContext context, {
        required int count,
        required String label,
        required IconData icon,
        required Color color,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(BuildContext context, AppointmentModel appointment) {
    final Color statusColor = appointment.status.getColor();
    final Color appointmentTypeColor = appointment.appointmentType.getBgColor(appointment.meetingType);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isApptStatusColorful 
              ? statusColor.withOpacity(0.5) 
              : Colors.white.withOpacity(0.3), 
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showEditAppointmentDialog(context, appointment),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === FIXED: make left chips wrap; constrain/ellipsis the timestamp ===
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left side: chips can wrap to a new line if tight
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // status chip + time text together
                        // Uses _isApptStatusColorful to toggle between status colors and teal
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isApptStatusColorful 
                                    ? statusColor.withOpacity(0.1) 
                                    : Colors.teal.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _isApptStatusColorful 
                                    ? statusColor.withOpacity(0.5) 
                                    : Colors.teal.withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(appointment.status.getIcon(), size: 16, 
                                      color: _isApptStatusColorful ? statusColor : Colors.teal.shade700),
                                  const SizedBox(width: 4),
                                  // prevent chip text from growing unbounded
                                  Flexible(
                                    child: Text(
                                      appointment.status.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _isApptStatusColorful ? statusColor : Colors.teal.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _shortDf.format(appointment.appointmentDateTime),
                              style: TextStyle(fontWeight: FontWeight.bold,fontSize: 16, color: Colors.grey[700]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),

                        // meeting type chip - pink for f2f, blue for online
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: appointmentTypeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: appointmentTypeColor.withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(appointment.meetingType.getIcon(), size: 16, color: appointmentTypeColor),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  appointment.meetingType.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: appointmentTypeColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Subscription package name (all appointments must have subscriptionId)
              if (appointment.subscriptionId != null)
                FutureBuilder<String>(
                  future: _getSubscriptionName(appointment.subscriptionId!),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }
                    final subName = snapshot.data!;
                    if (subName.isEmpty) return const SizedBox.shrink();
                    
                    final isDeleted = subName == 'Silinmiş Paket';
                    
                    return Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              isDeleted ? Icons.warning_amber_rounded : Icons.card_membership, 
                              size: 14, 
                              color: isDeleted ? Colors.red[400] : Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Paket: $subName',
                                style: TextStyle(
                                  color: isDeleted ? Colors.red[400] : Colors.grey[700],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
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

              if (appointment.notes != null && appointment.notes!.isNotEmpty) ...[
                Text(
                  appointment.notes!,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Left side: Postponement info
                  if (appointment.status == AppointmentStatus.postponed)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Orijinal: ${_longDf.format(appointment.appointmentDateTime)} ${DateFormat('HH:mm').format(appointment.appointmentDateTime)}',
                            style: TextStyle(fontWeight: FontWeight.bold,fontSize: 14, color: Colors.grey[700]),
                          ),
                          Text(
                            'Ertelenen: ${_longDf.format(appointment.postponedDate!)} ${DateFormat('HH:mm').format(appointment.postponedDate!)}',
                            style: TextStyle(fontWeight: FontWeight.bold,fontSize: 14, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  
                  // Right side: Action buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showEditAppointmentDialog(context, appointment),
                        tooltip: 'Düzenle',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                        onPressed: () => _confirmDeleteAppointment(context, appointment),
                        tooltip: 'Sil',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _showAppointmentDetails(
      BuildContext context, AppointmentModel appointment) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '${_shortDf.format(appointment.appointmentDateTime)} Randevusu',
            style: const TextStyle(fontSize: 18,fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            primary: false, // no need to use PrimaryScrollController in a dialog
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Durum:', appointment.status.label),
                _buildDetailRow('Görüşme Tipi:', appointment.meetingType.label),
                if (appointment.notes != null && appointment.notes!.isNotEmpty)
                  _buildDetailRow('Notlar:', appointment.notes!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showEditAppointmentDialog(context, appointment);
              },
              child: const Text('Düzenle'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }

  void _showEditAppointmentDialog(BuildContext context, AppointmentModel appointment) {
    showDialog(
      context: context,
      builder: (context) {
        return EditAppointmentDialog(
          appointment: appointment,
          onAppointmentUpdated: () => refreshData(), // instead of setState(fetchData())
        );
      },
    );
  }

  void _showAddAppointmentDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AddAppointmentDialog(
          userId: widget.userId,
          onAppointmentAdded: () {
            if (mounted) {
              refreshData();
            }
          },
        );
      },
    );
  }

  void _confirmDeleteAppointment(
      BuildContext context, AppointmentModel appointment) {
    DialogUtils.openConfirm(
      context,
      title: 'Randevu Silme',
      message: '${_shortDf.format(appointment.appointmentDateTime)} '
          'tarihli randevuyu silmek istediğinizden emin misiniz?',
      confirmText: 'Evet, Sil',
      cancelText: 'İptal',
    ).then((confirmed) {
      if (confirmed == true) {
        _deleteAppointment(appointment);
      }
    });
  }

  Future<void> _deleteAppointment(AppointmentModel appointment) async {
    try {
      final provider = Provider.of<AppointmentManager>(context, listen: false);
      await provider.deleteAppointment(
        appointment.appointmentId,
        appointment.userId,
        deletedBy: 'admin',
      );

      if (!mounted) return;
      refreshData(); // instead of setState(fetchData())

      DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Randevu başarıyla silindi.',
      );
    } catch (e) {
      if (!mounted) return;
      DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu silinirken bir hata oluştu: $e',
      );
    }
  }

  void _showAppointmentOptions(
      BuildContext context, AppointmentModel appointment) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _shortDf.format(appointment.appointmentDateTime),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('Detayları Görüntüle'),
                onTap: () {
                  Navigator.pop(context);
                  _showAppointmentDetails(context, appointment);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Düzenle'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditAppointmentDialog(context, appointment);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Sil', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteAppointment(context, appointment);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
