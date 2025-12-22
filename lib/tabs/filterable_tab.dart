import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'basetab.dart';
import '../utils/date_formatter.dart';
import '../widgets/filter_chip_group.dart';
import '../models/filter_params.dart';
abstract class FilterableTabState<P, T extends BaseTab<P>>
    extends BaseTabState<P, T> {
  final TextEditingController searchController = TextEditingController();
/*
24.08.2025 refresh butonunun çalımnaması fixi:
Let's look more closely at how FilterableTabState handles data caching:
Now let's check how the buildList method works in FilterableTabState:
Implement a solution that properly invalidates FilterableTabState cache
I understand the issue now. The FilterableTabState caches filtered items, but our refresh mechanism in BaseTabState isn't properly invalidating this cache. When you open and close the filter dialog, it's calling _invalidateFilterCache() which is why you see the updated data.
Let's modify the filterable_tab.dart file to properly handle refreshes:
I found and fixed the issue. The problem was that while the BaseTabState was correctly refreshing data from Firebase, the FilterableTabState (which extends BaseTabState) was caching filtered items and not invalidating this cache when the refresh button was clicked.
The fix is simple but effective:
I overrode the refreshData() method in FilterableTabState to ensure it clears the cached filtered items before calling the parent method.
This ensures that when you click the refresh button, not only is fresh data fetched from Firebase, but any cached filtered items are also cleared, forcing a complete UI refresh.
This is why opening and closing the filter dialog worked - because that process was already clearing the cache. Now clicking the refresh button will properly show changes made directly in Firebase without requiring you to leave the page or open/close filters.
 */
  String searchQuery = '';
  String _lastProcessedQuery = '';

  bool filtersVisible = false;

  DateTimeRange? selectedDateRange;
  DateTimeRange? _lastProcessedDateRange;

  DateTimeRange? tempDateRange;

  bool filtersModified = false;
  bool _isFiltering = false;

  /// Counter to force rebuild of filter widgets when reset is pressed
  int _filterResetKey = 0;
  
  /// Protected getter for subclasses to access the filter reset key
  int get filterResetKey => _filterResetKey;
  
  /// Reference to modal's setState for rebuilding filter content
  void Function(void Function())? _modalSetState;

  List<dynamic>? _cachedFilteredItems;

  final DateFormat dateFormat = DateFormat('dd.MM.yyyy');

  bool get isCompactMode => MediaQuery.of(context).size.width < 600;

  // debounce for search field to reduce rebuild spam
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    searchController.addListener(_onSearchChanged);
    tempDateRange = selectedDateRange;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final v = searchController.text.toLowerCase();
    if (v == searchQuery) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        searchQuery = v;
        _invalidateFilterCache();
      });
    });
  }

  void _invalidateFilterCache() {
    _cachedFilteredItems = null;
  }

  @override
  void fetchData() {
    _invalidateFilterCache();
    super.fetchData();
  }

  @override
  void refreshData() {
    _invalidateFilterCache();
    super.refreshData();
  }

  /// Non-blocking filter dialog: opens immediately and resolves content inside
  void toggleFilters() {
    // keep current values as temporary
    resetTempFilters();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.9;

        // Build with the same future we already use in the tab to avoid extra fetches
        final provider = widget.getProvider(context);
        final futureData = widget.getDataList(provider, showAllData);

        // Use StatefulBuilder to allow rebuilding modal content when reset is clicked
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            // Store the setModalState so reset can use it
            _modalSetState = setModalState;
            
            return SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('Filtreler',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            // Store navigator reference BEFORE any state changes
                            final navigator = Navigator.of(ctx);

                            // Close the modal FIRST
                            if (navigator.canPop()) {
                              navigator.pop();
                            }

                            // Reset filters after modal starts closing
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _resetFiltersWithoutNavigation();
                              }
                            });
                          },
                          icon: const Icon(Icons.filter_alt_off),
                          label: const Text('Temizle'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            // Store navigator reference to ensure it's valid
                            final navigator = Navigator.of(ctx);
                            if (navigator.canPop()) {
                              navigator.pop();
                            }
                          },
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: FutureBuilder<List<dynamic>>(
                        future: futureData,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return Center(
                                child: Text(
                                    'Filtre içeriği yüklenemedi: ${snapshot.error}'));
                          }
                          final dataList = snapshot.data ?? const <dynamic>[];
                          final filteredItems = getFilteredItems(dataList);
                          return Scrollbar(
                            child: SingleChildScrollView(
                              primary: true,
                              physics: const ClampingScrollPhysics(),
                              child: buildFilterContent(
                                  context, dataList, filteredItems),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // Store navigator reference BEFORE any state changes
                          final navigator = Navigator.of(ctx);

                          // Apply filters first
                          _applyTempFiltersWithoutNavigation();

                          // Then close modal
                          if (navigator.canPop()) {
                            navigator.pop();
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Uygula', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      if (!mounted) return;
      _modalSetState = null; // Clear reference when modal closes
      _invalidateFilterCache();
      setState(() {}); // reflect new filters in list
    });
  }

  void resetFilters() {
    setState(() {
      searchController.clear();
      searchQuery = '';
      selectedDateRange = null;
      tempDateRange = null;
      filtersModified = false;
      _lastProcessedQuery = '';
      _lastProcessedDateRange = null;
      _filterResetKey++; // Force rebuild of filter widgets
      _invalidateFilterCache();
      resetAdditionalFilters();
    });
    // Refetch data without filters (server-side filtering)
    refreshData();
  }

  void resetTempFilters() {
    tempDateRange = selectedDateRange;
    filtersModified = false;
    resetAdditionalTempFilters();
  }

  void applyTempFilters() {
    setState(() {
      selectedDateRange = tempDateRange;
      applyAdditionalTempFilters();
      filtersModified = false;
      _invalidateFilterCache();
    });
    // Refetch data with new filters (server-side filtering)
    refreshData();
  }

  void resetAdditionalFilters() {}

  void resetAdditionalTempFilters() {}

  void applyAdditionalTempFilters() {}

  void onTempDateRangeSelected(DateTimeRange? range) {
    tempDateRange = range;
    filtersModified = true;
  }

  bool isInDateRange(DateTime? itemDate) {
    if (selectedDateRange == null || itemDate == null) return true;
    final endOfDay = DateTime(
      selectedDateRange!.end.year,
      selectedDateRange!.end.month,
      selectedDateRange!.end.day,
      23,
      59,
      59,
    );
    return !itemDate.isBefore(selectedDateRange!.start) &&
        !itemDate.isAfter(endOfDay);
  }

  List<dynamic> getFilteredItems(List<dynamic> items) {
    // Since filtering is now done on Firebase side, we just return items as-is
    // The items are already filtered by the provider based on buildFilterParams()
    return items;
  }

  /// Build filter parameters for Firebase-side filtering
  /// Override in subclasses to provide specific filter params
  @override
  FilterParams? buildFilterParams() {
    // Base implementation returns null - override in subclasses
    return null;
  }

  Widget buildEmptyState({
    IconData icon = Icons.search_off,
    String message = 'Sonuç bulunamadı',
    String? submessage,
  }) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                submessage ??
                    'Filtre seçeneklerini değiştirmeyi deneyebilirsiniz.',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: toggleFilters,
                icon: const Icon(Icons.filter_alt),
                label: const Text('Filtreleri Düzenle'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: resetFilters,
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Filtreleri Temizle'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSearchField({String hintText = 'Ara...'}) {
    // Key forces rebuild when filters are reset (searchController is cleared)
    return SearchField(
      key: ValueKey('search_field_$_filterResetKey'),
      controller: searchController,
      hintText: hintText,
    );
  }

  Widget buildDateRangeFilter({
    String placeholderText = 'Tarih Aralığı Seçin',
    DateTime? firstDate,
    DateTime? lastDate,
  }) {
    // Use key to force rebuild when filters are reset
    return StatefulBuilder(
      key: ValueKey('date_range_filter_$_filterResetKey'),
      builder: (context, setDateState) {
        return DateRangeFilter.withDefaultFormat(
          selectedRange: tempDateRange,
          onRangeSelected: (range) {
            tempDateRange = range;
            filtersModified = true;
            setDateState(() {});
          },
          placeholderText: placeholderText,
          firstDate: firstDate,
          lastDate: lastDate,
        );
      },
    );
  }

  Widget buildFilterActionButtons({BuildContext? modalContext}) {
    // Only reset button - Uygula is at the bottom of the modal
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: () {
              // Reset temp filters to defaults without closing modal or fetching
              _resetTempFiltersToDefaults();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Filtreleri Sıfırla'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
        ],
      ),
    );
  }

  /// Resets filters without triggering navigation - for use with modal buttons
  void _resetFiltersWithoutNavigation() {
    setState(() {
      searchController.clear();
      searchQuery = '';
      selectedDateRange = null;
      tempDateRange = null;
      filtersModified = false;
      _lastProcessedQuery = '';
      _lastProcessedDateRange = null;
      _filterResetKey++;
      _invalidateFilterCache();
      resetAdditionalFilters();
    });
    refreshData();
  }

  /// Resets temp filters to defaults without closing modal or fetching data
  /// User must click "Uygula" to apply the reset filters
  void _resetTempFiltersToDefaults() {
    // Reset base temp filters
    searchController.clear();
    tempDateRange = null;
    filtersModified = true;
    _filterResetKey++;
    
    // Reset subclass temp filters to defaults
    resetTempFiltersToDefaults();
    
    // Rebuild the modal content to show reset values
    _modalSetState?.call(() {});
  }

  /// Override in subclasses to reset temp filters to default values
  void resetTempFiltersToDefaults() {
    // Base implementation - subclasses override to set their specific defaults
  }

  /// Applies temp filters without triggering navigation - for use with modal buttons
  void _applyTempFiltersWithoutNavigation() {
    setState(() {
      selectedDateRange = tempDateRange;
      applyAdditionalTempFilters();
      filtersModified = false;
      _invalidateFilterCache();
    });
    refreshData();
  }

  Widget buildFilterSection({
    required String title,
    required List<Widget> filterWidgets,
    List<Widget>? actions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        ...filterWidgets.expand((w) => [w, const SizedBox(height: 16)]).toList()
          ..removeLast(),
        if (actions != null && actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      ],
    );
  }

  Widget buildReactiveFilterWidget<V>({
    required String title,
    required V? initialValue,
    required Map<V, String> options,
    required Function(V?) onSelected,
    bool showAllOption = true,
  }) {
    // Use a unique key based on _filterResetKey to force rebuild when filters are reset.
    // This ensures that when reset is pressed, the widget is recreated with fresh initialValue.
    return _ReactiveFilterWidget<V>(
      key: ValueKey('filter_${title}_$_filterResetKey'),
      title: title,
      initialValue: initialValue,
      options: options,
      showAllOption: showAllOption,
      onSelected: onSelected,
      onFiltersModified: () => filtersModified = true,
      buildFilterWidget: buildFilterWidget,
    );
  }

  Widget buildFilterWidget<V>({
    required String title,
    required V? selectedValue,
    required Map<V, String> options,
    required Function(V?) onSelected,
    bool showAllOption = true,
  }) {
    return FilterChipGroup<V>(
      title: title,
      selectedValue: selectedValue,
      options: options,
      showAllOption: showAllOption,
      onSelected: onSelected,
    );
  }

  void onFilterApplied(List<dynamic> filteredItems) {}

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
              Expanded(child: filterSummary),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget buildActiveFiltersSummary(int filteredCount, int totalCount) {
    if (filteredCount != totalCount) {
      final hasSearch = searchQuery.isNotEmpty;
      final hasDateRange = selectedDateRange != null;
      final hasOtherFilters = hasAdditionalActiveFilters();

      var active = 0;
      if (hasSearch) active++;
      if (hasDateRange) active++;
      if (hasOtherFilters) active++;

      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(0.3)),
            ),
            child: Text(
              '$active filtre aktif',
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$filteredCount / $totalCount öğe gösteriliyor',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  /// Override in subclasses to let the base widget know about custom filters.
  /// Keeping this public (non-underscored) allows other files to override it.
  bool hasAdditionalActiveFilters() => false;

  Widget buildFilterContent(BuildContext context, List<dynamic> allItems,
      List<dynamic> filteredItems);

  Widget buildFilteredContent(
      BuildContext context, List<dynamic> filteredItems);
}

/// A stateful widget that manages its own selected value for reactive filter chips.
/// This allows the filter to update immediately when tapped, while properly resetting
/// when a new key is provided (e.g., when filters are reset).
class _ReactiveFilterWidget<V> extends StatefulWidget {
  final String title;
  final V? initialValue;
  final Map<V, String> options;
  final bool showAllOption;
  final Function(V?) onSelected;
  final VoidCallback onFiltersModified;
  final Widget Function<T>({
    required String title,
    required T? selectedValue,
    required Map<T, String> options,
    required Function(T?) onSelected,
    bool showAllOption,
  }) buildFilterWidget;

  const _ReactiveFilterWidget({
    super.key,
    required this.title,
    required this.initialValue,
    required this.options,
    required this.showAllOption,
    required this.onSelected,
    required this.onFiltersModified,
    required this.buildFilterWidget,
  });

  @override
  State<_ReactiveFilterWidget<V>> createState() => _ReactiveFilterWidgetState<V>();
}

class _ReactiveFilterWidgetState<V> extends State<_ReactiveFilterWidget<V>> {
  late V? _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.initialValue;
  }

  @override
  void didUpdateWidget(covariant _ReactiveFilterWidget<V> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the key changed (detected via initialValue change after reset), reset selected value
    if (widget.initialValue != oldWidget.initialValue) {
      _selectedValue = widget.initialValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.buildFilterWidget<V>(
      title: widget.title,
      selectedValue: _selectedValue,
      options: widget.options,
      showAllOption: widget.showAllOption,
      onSelected: (value) {
        setState(() {
          _selectedValue = value;
        });
        widget.onFiltersModified();
        widget.onSelected(value);
      },
    );
  }
}

/// A reusable search field widget with a clear button that appears when text is entered
class SearchField extends StatelessWidget {
  /// The controller for the search input
  final TextEditingController controller;

  /// Optional hint text to display when the field is empty
  final String hintText;

  /// Whether to automatically focus this field when it appears
  final bool autofocus;

  /// The border radius for the input field
  final double borderRadius;

  /// The color to use as background for the input field
  final Color? fillColor;

  /// Optional callback when the text changes
  final Function(String)? onChanged;

  /// Optional icon to show at the start of the field
  final Icon prefixIcon;

  /// Optional constraints to control the width of the field
  final BoxConstraints? constraints;

  /// Creates a search field with standard styling and a clear button
  const SearchField({
    super.key,
    required this.controller,
    this.hintText = 'Ara...',
    this.autofocus = false,
    this.borderRadius = 8.0,
    this.fillColor,
    this.onChanged,
    this.prefixIcon = const Icon(Icons.search),
    this.constraints,
  });

  @override
  Widget build(BuildContext context) {
    final searchField = TextField(
      controller: controller,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: prefixIcon,
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            controller.clear();
            if (onChanged != null) {
              onChanged!('');
            }
          },
        )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        filled: true,
        fillColor: fillColor ?? Colors.grey[100],
        isDense: true, // Make the field more compact
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12.0,
          horizontal: 12.0,
        ),
      ),
      onChanged: onChanged,
    );

    // If constraints are provided, wrap the field in a constrained box
    if (constraints != null) {
      return ConstrainedBox(
        constraints: constraints!,
        child: searchField,
      );
    }

    // Otherwise, return the field directly
    return searchField;
  }

  /// Creates a version of the search field that adapts to the available width
  /// This is useful for responsive layouts where you want the search field
  /// to behave differently based on screen size
  factory SearchField.responsive({
    required TextEditingController controller,
    required BuildContext context,
    String hintText = 'Ara...',
    bool autofocus = false,
    double? maxWidth,
    double minWidth = 200,
    Function(String)? onChanged,
    Icon prefixIcon = const Icon(Icons.search),
  }) {
    // Calculate maxWidth based on screen size if not provided
    final calculatedMaxWidth = maxWidth ??
        MediaQuery.of(context).size.width * 0.8;

    return SearchField(
      controller: controller,
      hintText: hintText,
      autofocus: autofocus,
      onChanged: onChanged,
      prefixIcon: prefixIcon,
      constraints: BoxConstraints(
        minWidth: minWidth,
        maxWidth: calculatedMaxWidth,
      ),
    );
  }
}

/// A widget that provides a date range selection button with optional clear button
class DateRangeFilter extends StatelessWidget {
  /// The currently selected date range, or null if no dates are selected.
  final DateTimeRange? selectedRange;

  /// Callback when a date range is selected or cleared
  final Function(DateTimeRange?) onRangeSelected;

  /// The text to display when no date range is selected
  final String placeholderText;

  /// Date format to use for displaying the selected dates
  final DateFormat dateFormat;

  /// First date allowed for selection
  final DateTime? firstDate;

  /// Last date allowed for selection
  final DateTime? lastDate;

  /// Use compact format
  final bool useCompactFormat;

  /// Show clear button
  final bool showClearButton;

  /// Border radius
  final double borderRadius;

  /// Constraints for the widget
  final BoxConstraints? constraints;

  /// Creates a date range filter with a selectable button and clear option
  const DateRangeFilter({
    super.key,
    required this.selectedRange,
    required this.onRangeSelected,
    required this.placeholderText,
    required this.dateFormat,
    this.firstDate,
    this.lastDate,
    this.useCompactFormat = false,
    this.showClearButton = true,
    this.borderRadius = 8.0,
    this.constraints,
  });

  /// Create a DateRangeFilter with the standard format "dd.MM.yyyy"
  static DateRangeFilter withDefaultFormat({
    Key? key,
    required DateTimeRange? selectedRange,
    required Function(DateTimeRange?) onRangeSelected,
    String placeholderText = 'Tarih Aralığı Seçin',
    DateTime? firstDate,
    DateTime? lastDate,
    bool showClearButton = true,
    double borderRadius = 8.0,
    BoxConstraints? constraints,
  }) {
    return DateRangeFilter(
      key: key,
      selectedRange: selectedRange,
      onRangeSelected: onRangeSelected,
      placeholderText: placeholderText,
      firstDate: firstDate,
      lastDate: lastDate,
      dateFormat: DateFormat('dd.MM.yyyy', 'tr_TR'),
      showClearButton: showClearButton,
      borderRadius: borderRadius,
      constraints: constraints,
    );
  }

  /// Create a responsive DateRangeFilter that uses a compact format on small screens
  static DateRangeFilter responsive({
    Key? key,
    required DateTimeRange? selectedRange,
    required Function(DateTimeRange?) onRangeSelected,
    String placeholderText = 'Tarih Aralığı Seçin',
    DateTime? firstDate,
    DateTime? lastDate,
    required bool isCompact,
    bool showClearButton = true,
    double borderRadius = 8.0,
    BoxConstraints? constraints,
  }) {
    return DateRangeFilter(
      key: key,
      selectedRange: selectedRange,
      onRangeSelected: onRangeSelected,
      placeholderText: placeholderText,
      firstDate: firstDate,
      lastDate: lastDate,
      dateFormat: isCompact
          ? DateFormat('dd/MM/yy', 'tr_TR') // Compact format
          : DateFormat('dd.MM.yyyy', 'tr_TR'), // Full format
      useCompactFormat: isCompact,
      showClearButton: showClearButton,
      borderRadius: borderRadius,
      constraints: constraints,
    );
  }

  /// Shows the date range picker dialog
  Future<void> _pickDateRange(BuildContext context) async {
    final initialDateRange = selectedRange ??
        DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 30)),
          end: DateTime.now(),
        );

    final pickedDateRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialDateRange,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            appBarTheme: Theme.of(context).appBarTheme.copyWith(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
          child: child!,
        );
      },
      locale: const Locale('tr', 'TR'),
    );

    if (pickedDateRange != null) {
      onRangeSelected(pickedDateRange);
    }
  }

  /// Format a date range to be displayed in the button
  String _formatDateRange(DateTimeRange range) {
    // Always show full dates for both start and end
    return DateFormatter.formatDateRange(range.start, range.end);
  }

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: () => _pickDateRange(context),
      icon: const Icon(Icons.date_range),
      label: Text(
        selectedRange != null
            ? _formatDateRange(selectedRange!)
            : placeholderText,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );

    final row = Row(
      children: [
        Expanded(child: button),
        if (showClearButton && selectedRange != null)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => onRangeSelected(null),
            tooltip: 'Tarih filtresini temizle',
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
      ],
    );

    // If constraints are provided, wrap the row in a constrained box
    if (constraints != null) {
      return ConstrainedBox(
        constraints: constraints!,
        child: row,
      );
    }

    // Otherwise, return the row directly
    return row;
  }
}