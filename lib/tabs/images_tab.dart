// tabs/images_tab.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/logger.dart';
import '../models/meal_model.dart';
import '../models/filter_params.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../providers/daily_data_provider.dart';

import '../widgets/chat_image_preview.dart';
import 'basetab.dart';
import 'filterable_tab.dart';

final Logger logger = Logger.forClass(ImagesTab);

/// Tab for displaying and managing meal images
/// Shows uploaded meal photos with filtering options
class ImagesTab extends BaseTab<MealManager> {
  const ImagesTab({super.key, required super.userId})
      : super(
    allDataLabel: 'Tüm Görseller',
    subscriptionDataLabel: 'Paket Görselleri',
  );

  @override
  MealManager getProvider(BuildContext context) {
    final provider = Provider.of<MealManager>(context, listen: false);
    return provider;
  }

  @override
  Future<List<dynamic>> getDataList(
      MealManager provider,
      bool showAllData, {
        FilterParams? filterParams,
      }) {
    return provider.fetchMeals(
      null,
      userId: userId,
      showAllImages: showAllData,
      date: null,
      filterParams: filterParams as MealFilterParams?,
    );
  }

  @override
  createState() => _ImagesTabState();
}

class _ImagesTabState extends FilterableTabState<MealManager, ImagesTab> {
  // === CONFIGURABLE CONSTANTS (tweak here) ===
  // Size reduction multiplier (0.7 = 30% smaller)
  static const double kSizeReductionMultiplier = 1;

  // Meal widget sizes
  static const double kThumbBase = 96.0 * kSizeReductionMultiplier; // base thumbnail size (logical px)
  static const double kThumbPhoneMultiplier = 1.00; // phone multiplier
  static const double kThumbTabletMultiplier = 1.20; // tablet multiplier
  static const double kDialogMultiplier =
  2.8; // dialog image height = thumb * multiplier
  static const double kGridGap = 8.0; // grid spacing
  static const int kGridMinCols = 3;
  static const int kGridMaxCols = 6;

  // Meal card text and icon sizes (30% smaller)
  static const double kMealCardIconSize = 14.0 * kSizeReductionMultiplier;
  static const double kMealCardTimeIconSize = 12.0 * kSizeReductionMultiplier;
  static const double kMealCardLabelFontSize = 12.0 * kSizeReductionMultiplier;
  static const double kMealCardTimeFontSize = 11.0 * kSizeReductionMultiplier;
  static const double kMealCardPadding = 6.0 * kSizeReductionMultiplier;
  static const double kMealCardTopPadding = 8.0 * kSizeReductionMultiplier;
  static const double kMealCardSpacing = 4.0 * kSizeReductionMultiplier;
  static const double kMealCardMargin = 4.0 * kSizeReductionMultiplier;

  // Meal card height ratio (higher = shorter cards, lower = taller cards)
  // 0.78 = original, 1.0 = square, 1.2 = 20% wider than tall
  static const double kMealCardAspectRatio = 1.2;

  // Date header sizes (30% smaller)
  static const double kDateHeaderFontSize = 18.0 * kSizeReductionMultiplier;
  static const double kDateHeaderPadding = 4.0 * kSizeReductionMultiplier;
  static const double kDateHeaderVerticalMargin = 3.0 * kSizeReductionMultiplier;
  static const double kDateHeaderSpacing = 3.0 * kSizeReductionMultiplier;

  Meals? _selectedMealType;
  bool _showOnlyThisWeek = true; // Show last 7 days by default
  Map<DateTime, DailyData> _dailyDataMap = {};
  Map<DateTime, Map<Meals, bool>> _mealStatesMap = {};

  final ScrollController _scrollController = ScrollController();

  // Temporary filter values for reactive UI
  Meals? _tempMealType;
  bool _tempShowOnlyThisWeek = true;

  // Statistics
  Map<Meals, int> _mealTypeCounts = {};

  // NEW: error flag – if true, page shows only the error message
  // bool _hasDataError = false;

  @override
  void initState() {
    super.initState();
    _tempMealType = _selectedMealType;
    _tempShowOnlyThisWeek = _showOnlyThisWeek;

    // Initialize date range to last 7 days by default
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastWeek = today.subtract(const Duration(days: 6));
    selectedDateRange = DateTimeRange(start: lastWeek, end: today);

    _fetchDateRangeDailyData();
    _fetchDateRangeMealStates();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Future<void> _fetchDailyData(DateTime date) async {
  //   try {
  //     final provider = Provider.of<MealManager>(context, listen: false);
  //     final dailyData =
  //     await provider.fetchDailyData(widget.userId, date: date);
  //     if (!mounted) return;
  //     setState(() {
  //       _dailyDataMap[date] = dailyData;
  //     });
  //     logger.debug('Fetched daily data for {}: water={}L, steps={}',
  //         [DateFormat('yyyy-MM-dd').format(date), dailyData.waterIntake, dailyData.steps]);
  //   } catch (e) {
  //     logger.err('Error fetching daily data for {}: {}', [DateFormat('yyyy-MM-dd').format(date), e]);
  //   }
  // }

  Future<void> _fetchDateRangeDailyData() async {
    if (selectedDateRange == null) return;

    try {
      // Clear previous data to avoid showing stale values
      setState(() {
        _dailyDataMap.clear();
        //_hasDataError = false; // reset error on new fetch cycle
      });

      final dailyDataProvider =
      Provider.of<DailyDataProvider>(context, listen: false);
      final tempMap = await dailyDataProvider.fetchDailyDataForDateRange(
        widget.userId,
        selectedDateRange!,
      );

      // Update UI only once with all data
      if (!mounted) return;
      setState(() {
        _dailyDataMap = tempMap;
      });

      logger.debug('Fetched daily data for {} days', [tempMap.length]);
    } catch (e) {
      logger.err('Error fetching date range daily data: {}', [e]);
      if (!mounted) return;
      setState(() {
        //_hasDataError = true; // mark error so page shows only error message
      });
    }
  }
  Future<void> _fetchDateRangeMealStates() async {
    if (selectedDateRange == null) return;

    try {
      // Clear previous data
      setState(() {
        _mealStatesMap.clear();
        //_hasDataError = false; // also reset error when starting this fetch
      });

      final mealManager = Provider.of<MealManager>(context, listen: false);
      final tempMap = <DateTime, Map<Meals, bool>>{};

      // Fetch meal states for each day in the range
      DateTime currentDate = selectedDateRange!.start;
      while (currentDate.isBefore(selectedDateRange!.end) ||
          currentDate.isAtSameMomentAs(selectedDateRange!.end)) {
        final mealStates = await mealManager.fetchMealStates(
          widget.userId,
          date: currentDate,
        );
        tempMap[currentDate] = mealStates;
        currentDate = currentDate.add(const Duration(days: 1));
      }

      // Update UI only once with all data
      if (!mounted) return;
      setState(() {
        _mealStatesMap = tempMap;
      });

      logger.debug('Fetched meal states for {} days', [tempMap.length]);
    } catch (e) {
      logger.err('Error fetching date range meal states: {}', [e]);
      if (!mounted) return;
      setState(() {
        //_hasDataError = true; // same flag used here
      });
    }
  }


  @override
  void resetAdditionalTempFilters() {
    _tempMealType = _selectedMealType;
    _tempShowOnlyThisWeek = _showOnlyThisWeek;
  }

  @override
  void applyAdditionalTempFilters() {
    _selectedMealType = _tempMealType;

    final oldDateRange = selectedDateRange;
    final oldShowOnlyThisWeek = _showOnlyThisWeek;
    _showOnlyThisWeek = _tempShowOnlyThisWeek;

    // If "Son 7 günü göster" is enabled, set date range to last 7 days
    // Only override if the toggle is enabled AND no custom date range was selected
    if (_showOnlyThisWeek) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastWeek = today.subtract(const Duration(days: 6));
      selectedDateRange = DateTimeRange(start: lastWeek, end: today);
    } else {
      // Use the manually selected date range from tempDateRange
      selectedDateRange = tempDateRange;
    }

    // Refetch daily data if date range changed or toggle changed
    final dateRangeChanged = oldDateRange?.start != selectedDateRange?.start ||
        oldDateRange?.end != selectedDateRange?.end;
    if (dateRangeChanged || oldShowOnlyThisWeek != _showOnlyThisWeek) {
      _fetchDateRangeDailyData();
      _fetchDateRangeMealStates();
    }

    setState(() {});
  }

  @override
  void resetAdditionalFilters() {
    // Reset applied values to defaults
    _selectedMealType = null;
    _showOnlyThisWeek = true;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastWeek = today.subtract(const Duration(days: 6));
    selectedDateRange = DateTimeRange(start: lastWeek, end: today);

    // Also reset temp values
    resetTempFiltersToDefaults();
  }

  @override
  void resetTempFiltersToDefaults() {
    // Reset temp filters to defaults: last 7 days, no meal type
    _tempMealType = null;
    _tempShowOnlyThisWeek = true;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastWeek = today.subtract(const Duration(days: 6));
    tempDateRange = DateTimeRange(start: lastWeek, end: today);
  }

  @override
  FilterParams? buildFilterParams() {
    return MealFilterParams(
      searchQuery: searchQuery.isNotEmpty ? searchQuery : null,
      dateRange: selectedDateRange,
      mealType: _selectedMealType?.name,
      showOnlyThisWeek: _showOnlyThisWeek,
      specificDate: null,
    );
  }

  @override
  bool hasAdditionalActiveFilters() {
    return _selectedMealType != null || _showOnlyThisWeek;
  }

  @override
  void onFilterApplied(List<dynamic> filteredItems) {
    final meals = filteredItems.cast<MealModel>();

    Map<Meals, int> typeCounts = {};
    for (var meal in meals) {
      typeCounts[meal.mealType] = (typeCounts[meal.mealType] ?? 0) + 1;
    }

    setState(() {
      _mealTypeCounts = typeCounts;
    });
  }

  /// Calculates average water intake and steps based on selected date range
  (double waterAvg, int stepsAvg) _calculateAverages() {
    if (selectedDateRange == null || _dailyDataMap.isEmpty) {
      return (0.0, 0);
    }

    // Calculate total days in the selected date range
    final start = selectedDateRange!.start;
    final end = selectedDateRange!.end;
    final totalDays = end.difference(start).inDays + 1;

    double totalWater = 0.0;
    int totalSteps = 0;

    for (final data in _dailyDataMap.values) {
      totalWater += data.waterIntake;
      totalSteps += data.steps;
    }

    if (totalDays == 0) {
      return (0.0, 0);
    }

    // Average based on the total days in range, not just days with data
    return (totalWater / totalDays, (totalSteps / totalDays).round());
  }

  Widget _buildDateRangeSummary() {
    // Only show if data is loaded
    if (_dailyDataMap.isEmpty) {
      return const SizedBox.shrink();
    }

    final (waterAvg, stepsAvg) = _calculateAverages();

    // Calculate days in range for display
    String periodLabel = 'Günlük Ortalama';
    if (selectedDateRange != null) {
      final days = selectedDateRange!.end.difference(selectedDateRange!.start).inDays + 1;
      periodLabel = '$days Günlük Ortalama';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.water_drop, color: Colors.blue, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${waterAvg.toStringAsFixed(1)} L',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.directions_walk, color: Colors.green, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$stepsAvg adım',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget buildList(BuildContext context, List<dynamic> dataList) {
    // If there was an error in any of the date-range fetches,
    // show ONLY the error message in the whole tab.
    // if (_hasDataError) {
    //   return Center(
    //     child: Padding(
    //       padding: const EdgeInsets.all(16),
    //       child: Container(
    //         padding: const EdgeInsets.all(12),
    //         decoration: BoxDecoration(
    //           color: Colors.red.shade50,
    //           borderRadius: BorderRadius.circular(8),
    //           border: Border.all(color: Colors.red.shade200),
    //         ),
    //         child: const Text(
    //           'Veri yüklenirken bir hata oluştu. Bağlantınızı kontrol ediniz.',
    //           style: TextStyle(
    //             color: Colors.red,
    //             fontSize: 14,
    //             fontWeight: FontWeight.bold,
    //           ),
    //           textAlign: TextAlign.center,
    //         ),
    //       ),
    //     ),
    //   );
    // }

    final filteredItems = getFilteredItems(dataList);

    // Use a microtask to avoid blocking the UI thread
    Future.microtask(() {
      if (mounted) onFilterApplied(filteredItems);
    });

    final filterButton = ElevatedButton.icon(
      onPressed: toggleFilters,
      icon: const Icon(Icons.filter_alt),
      label: const Text('Filtrele'),
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    final filterSummary =
    buildActiveFiltersSummary(filteredItems.length, dataList.length);

    const sizedBox = SizedBox(width: 12);

    // Always show buildFilteredContent when we have a date range selected,
    // even if there are no meals - this ensures daily data cards are displayed
    final content = (filteredItems.isEmpty && selectedDateRange == null)
        ? buildEmptyState()
        : buildFilteredContent(context, filteredItems);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  filterButton,
                  sizedBox,
                  Expanded(child: filterSummary),
                ],
              ),
              const SizedBox(height: 12),
              _buildDateRangeSummary(),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }


  @override
  Widget buildFilterContent(
      BuildContext context,
      List<dynamic> allItems,
      List<dynamic> filteredItems,
      ) {
    final mealTypeOptions = {for (var type in Meals.values) type: type.label};

    // Use filterResetKey to force rebuild when "Filtreleri Sıfırla" is clicked
    final resetKey = ValueKey('images_filter_$filterResetKey');

    return buildFilterSection(
      title: 'Görsel Yönetimi',
      filterWidgets: [
        // Date filtering card - use key to rebuild on reset
        StatefulBuilder(
          key: resetKey,
          builder: (context, setDateFilterState) {
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tarih Filtresi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text(
                        'Son 7 günü göster',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle:
                      const Text('Otomatik olarak son 7 günü seç'),
                      value: _tempShowOnlyThisWeek,
                      onChanged: (value) {
                        _tempShowOnlyThisWeek = value;
                        filtersModified = true;

                        // When enabled, update tempDateRange to show last 7 days in UI
                        if (value) {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final lastWeek = today.subtract(const Duration(days: 6));
                          tempDateRange = DateTimeRange(start: lastWeek, end: today);
                        }

                        setDateFilterState(() {}); // Update local UI including date range filter
                        setState(() {}); // Update parent state
                      },
                      activeColor: Theme.of(context).primaryColor,
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 0),
                    ),
                    const SizedBox(height: 16),
                    // Inline date range filter so it can use setDateFilterState
                    DateRangeFilter.withDefaultFormat(
                      selectedRange: tempDateRange,
                      onRangeSelected: (range) {
                        tempDateRange = range;
                        filtersModified = true;

                        // Automatically disable "Son 7 günü göster" when custom date is selected
                        if (range != null) {
                          _tempShowOnlyThisWeek = false;
                        }

                        setDateFilterState(() {}); // Update local UI including toggle
                        setState(() {}); // Update parent state
                      },
                      placeholderText: 'Tarih Aralığı Seçin',
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        if (filteredItems.isNotEmpty && _mealTypeCounts.isNotEmpty) ...[
          _buildStatisticsBar(),
          const SizedBox(height: 16),
        ],

        buildSearchField(hintText: 'Açıklamaya göre ara...'),
        const SizedBox(height: 16),

        // Use key to rebuild meal type filter on reset
        KeyedSubtree(
          key: ValueKey('meal_filter_$filterResetKey'),
          child: buildReactiveFilterWidget<Meals>(
            title: 'Öğün Tipi:',
            initialValue: _tempMealType,
            options: mealTypeOptions,
            onSelected: (type) {
              _tempMealType = type;
            },
          ),
        ),

        const SizedBox(height: 16),
        buildFilterActionButtons(),
      ],
    );
  }

  Widget _buildDailyDataItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool smallSize = false,
  }) {
    final double iconSize = (smallSize ? 18.0 : 24.0) * kSizeReductionMultiplier;
    final double labelFontSize = (smallSize ? 12.0 : 14.0) * kSizeReductionMultiplier;
    final double valueFontSize = (smallSize ? 14.0 : 18.0) * kSizeReductionMultiplier;
    final double paddingSize = (smallSize ? 8.0 : 12.0) * kSizeReductionMultiplier;

    return Container(
      padding: EdgeInsets.all(paddingSize),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: iconSize),
          SizedBox(width: 8 * kSizeReductionMultiplier),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.bold,
                  color: color.withOpacity(0.8),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget buildFilteredContent(
      BuildContext context,
      List<dynamic> filteredItems,
      ) {
    List<MealModel> meals = filteredItems.cast<MealModel>();

    // Compute responsive sizes once
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.shortestSide >= 600;
    final double thumbSize =
        kThumbBase * (isTablet ? kThumbTabletMultiplier : kThumbPhoneMultiplier);
    final double dialogImageHeight = thumbSize * kDialogMultiplier;

    // Sort by date (newest first)
    meals.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Group by date label
    Map<String, List<MealModel>> groupedMeals = {};
    var dateFormat = DateFormat('d MMMM y');
    for (var meal in meals) {
      final dateKey = dateFormat.format(meal.timestamp);
      groupedMeals.putIfAbsent(dateKey, () => []).add(meal);
    }

    // Collect ALL dates in the selected date range to always show daily data
    Set<String> allDates = {};

    // Add all dates from the selected date range
    if (selectedDateRange != null) {
      DateTime currentDate = selectedDateRange!.start;
      while (currentDate.isBefore(selectedDateRange!.end) ||
          currentDate.isAtSameMomentAs(selectedDateRange!.end)) {
        final dateKey = dateFormat.format(currentDate);
        allDates.add(dateKey);
        currentDate = currentDate.add(const Duration(days: 1));
      }
    }

    // Also add dates from meals (in case they're outside the current range)
    allDates.addAll(groupedMeals.keys);

    // Add dates from dailyDataMap
    for (var date in _dailyDataMap.keys) {
      final dateKey = dateFormat.format(date);
      allDates.add(dateKey);
    }

    // Add dates from mealStatesMap (only if they have at least one checked meal)
    for (var entry in _mealStatesMap.entries) {
      if (entry.value.values.any((checked) => checked)) {
        final dateKey = dateFormat.format(entry.key);
        allDates.add(dateKey);
      }
    }

    final sortedDates = allDates.toList()
      ..sort((a, b) {
        final aDate = dateFormat.parse(a);
        final bDate = dateFormat.parse(b);
        return bDate.compareTo(aDate);
      });

    if (sortedDates.isEmpty) {
      String message = 'Görsel bulunamadı';
      String submessage = 'Filtreleri değiştirerek tekrar deneyin';

      if (selectedDateRange != null) {
        final start = dateFormat.format(selectedDateRange!.start);
        final end = dateFormat.format(selectedDateRange!.end);
        message = '$start - $end arasında görsel bulunamadı';
        submessage = 'Bu tarih aralığında hiç görsel yüklenmemiş';
      } else if (_showOnlyThisWeek) {
        message = 'Son 7 günde görsel bulunamadı';
        submessage = 'Bu hafta hiç görsel yüklenmemiş';
      }

      return buildEmptyState(
        icon: Icons.image_not_supported,
        message: message,
        submessage: submessage,
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: sortedDates.length,
        itemBuilder: (context, index) {
          final dateKey = sortedDates[index];
          final dateMeals = groupedMeals[dateKey] ?? [];
          final parsedDateKey = _parseDateKey(dateKey);
          final mealStates = _mealStatesMap[parsedDateKey] ?? {};

          // Build a combined list: actual meals + placeholders for checked meals without images
          final List<dynamic> displayItems = [];

          // Add all actual meals
          displayItems.addAll(dateMeals);

          // For each checked meal, if there's no image for it, add a placeholder
          for (var mealType in Meals.values) {
            final isChecked = mealStates[mealType] ?? false;
            if (isChecked) {
              // Check if this meal type already has an image
              final hasImage = dateMeals.any((m) => m.mealType == mealType);
              if (!hasImage) {
                // Add a placeholder object
                displayItems.add({'type': 'placeholder', 'mealType': mealType});
              }
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date header with daily data
              Card(
                elevation: 1,
                margin: EdgeInsets.symmetric(vertical: kDateHeaderVerticalMargin),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: EdgeInsets.all(kDateHeaderPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateKey,
                        style: TextStyle(
                          fontSize: kDateHeaderFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: kDateHeaderSpacing),
                      Builder(
                        builder: (context) {
                          final dailyData = _dailyDataMap[parsedDateKey] ?? DailyData();
                          return Row(
                            children: [
                              Expanded(
                                child: _buildDailyDataItem(
                                  icon: Icons.water_drop,
                                  color: Colors.blue,
                                  label: 'Su Tüketimi',
                                  value: '${dailyData.waterIntake.toStringAsFixed(1)} L',
                                  smallSize: true,
                                ),
                              ),
                              SizedBox(width: 16 * kSizeReductionMultiplier),
                              Expanded(
                                child: _buildDailyDataItem(
                                  icon: Icons.directions_walk,
                                  color: Colors.green,
                                  label: 'Adım Sayısı',
                                  value: dailyData.steps.toString(),
                                  smallSize: true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Responsive grid with small thumbnails
              LayoutBuilder(
                builder: (context, constraints) {
                  // approximate tile width = image + paddings
                  final estTile = thumbSize + (kGridGap * 2) + 16;
                  final rawCols = (constraints.maxWidth / estTile).floor();
                  final cols =
                  rawCols.clamp(kGridMinCols, kGridMaxCols).toInt();

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      childAspectRatio: kMealCardAspectRatio, // room for labels under image
                      crossAxisSpacing: kGridGap,
                      mainAxisSpacing: kGridGap,
                    ),
                    itemCount: displayItems.length,
                    itemBuilder: (context, itemIndex) {
                      final item = displayItems[itemIndex];

                      // Check if it's a placeholder or actual meal
                      if (item is Map && item['type'] == 'placeholder') {
                        return _buildMealPlaceholder(
                          context,
                          item['mealType'] as Meals,
                          thumbSize,
                        );
                      } else {
                        final meal = item as MealModel;
                        return _buildMealCard(
                          context,
                          meal,
                          thumbSize,
                          dialogImageHeight,
                        );
                      }
                    },
                  );
                },
              ),

              if (index < sortedDates.length - 1) const Divider(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatisticsBar() {
    // Combine ara öğün counts (firstmid, secondmid, thirdmid) into single "Ara" category
    final Map<String, int> displayCounts = {};
    int araCount = 0;

    for (final entry in _mealTypeCounts.entries) {
      if (entry.key == Meals.firstmid ||
          entry.key == Meals.secondmid ||
          entry.key == Meals.thirdmid) {
        araCount += entry.value;
      } else {
        displayCounts[entry.key.label] = entry.value;
      }
    }

    // Add combined ara count if any
    if (araCount > 0) {
      displayCounts['Ara'] = araCount;
    }

    // Define display order
    const displayOrder = ['Sabah', 'Öğle', 'Akşam', 'Ara'];
    final sortedEntries = displayCounts.entries.toList()
      ..sort((a, b) {
        final aIndex = displayOrder.indexOf(a.key);
        final bIndex = displayOrder.indexOf(b.key);
        return aIndex.compareTo(bIndex);
      });

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Öğün İstatistikleri',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: sortedEntries.map((entry) {
              return _buildMealTypeStatChip(
                label: entry.key,
                count: entry.value,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMealTypeStatChip({
    required String label,
    required int count,
  }) {
    final Color chipColor = _getMealTypeColorByLabel(label);

    return Flexible(
      fit: FlexFit.tight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: chipColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: chipColor.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: chipColor,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: chipColor,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Color _getMealTypeColorByLabel(String label) {
    switch (label) {
      case 'Sabah':
        return Colors.orange;
      case 'Öğle':
        return Colors.green;
      case 'Akşam':
        return Colors.indigo;
      case 'Ara':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Color _getMealTypeColor(Meals type) {
    switch (type) {
      case Meals.br:
        return Colors.orange;
      case Meals.lunch:
        return Colors.green;
      case Meals.dinner:
        return Colors.indigo;
      case Meals.firstmid:
      case Meals.secondmid:
      case Meals.thirdmid:
        return Colors.purple;
    }
  }

  // Small square thumbnail, downsampled, Hero to dialog
  Widget _buildMealPlaceholder(
      BuildContext context,
      Meals mealType,
      double thumbSize,
      ) {
    final Color typeColor = _getMealTypeColor(mealType);

    return Card(
      elevation: 2,
      margin: EdgeInsets.all(kMealCardMargin),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: typeColor.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Placeholder image area - flexible to fill available space
          Expanded(
            child: Container(
              margin: EdgeInsets.all(kMealCardPadding),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_not_supported,
                    size: 24 * kSizeReductionMultiplier,
                    color: Colors.grey.shade400,
                  ),
                  SizedBox(height: 4 * kSizeReductionMultiplier),
                  Text(
                    'Görsel Yok',
                    style: TextStyle(
                      fontSize: 10 * kSizeReductionMultiplier,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Compact info section with meal type
          Padding(
            padding: EdgeInsets.all(kMealCardPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getMealTypeIcon(mealType),
                  size: kMealCardIconSize,
                  color: typeColor,
                ),
                SizedBox(width: kMealCardSpacing),
                Flexible(
                  child: Text(
                    mealType.label,
                    style: TextStyle(
                      fontSize: 11 * kSizeReductionMultiplier,
                      fontWeight: FontWeight.w600,
                      color: typeColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealCard(
      BuildContext context,
      MealModel meal,
      double thumbSize,
      double dialogImageHeight,
      ) {

    final Color typeColor = _getMealTypeColor(meal.mealType);
    final String timeStr = DateFormat('HH:mm').format(meal.timestamp);
    final String heroTag =
        '${meal.imageUrl ?? ''}_${meal.timestamp.millisecondsSinceEpoch}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final int cache = (thumbSize * dpr).round();

        return Card(
          elevation: 2,
          margin: EdgeInsets.all(kMealCardMargin),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: typeColor.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: () =>
                _showMealDetails(context, meal, dialogImageHeight, heroTag),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Thumbnail - flexible to fill available space
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(kMealCardPadding),
                    child: Hero(
                      tag: heroTag,
                      child: ChatImagePreview(
                        imageUrl: meal.imageUrl,
                        borderRadius: 8,
                        cacheWidth: cache,
                        cacheHeight: cache,
                        fit: BoxFit.cover,
                        onTap: () => _showMealDetails(
                          context,
                          meal,
                          dialogImageHeight,
                          heroTag,
                        ),
                      ),
                    ),
                  ),
                ),

                // Compact info section with meal type and time
                Padding(
                  padding: EdgeInsets.all(kMealCardPadding),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Meal type with icon
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getMealTypeIcon(meal.mealType),
                              size: kMealCardIconSize,
                              color: typeColor,
                            ),
                            SizedBox(width: kMealCardSpacing),
                            Flexible(
                              child: Text(
                                meal.mealType.label,
                                style: TextStyle(
                                  fontSize: kMealCardLabelFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: typeColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Time in 24h format
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: kMealCardTimeIconSize,
                            color: Colors.grey[600],
                          ),
                          SizedBox(width: 2 * kSizeReductionMultiplier),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: kMealCardTimeFontSize,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getMealTypeIcon(Meals type) {
    switch (type) {
      case Meals.br:
        return Icons.breakfast_dining;
      case Meals.lunch:
        return Icons.lunch_dining;
      case Meals.dinner:
        return Icons.dinner_dining;
      case Meals.firstmid:
      case Meals.secondmid:
      case Meals.thirdmid:
        return Icons.restaurant;
    }
  }

  DateTime _parseDateKey(String dateStr) {
    try {
      // Parse format "d MMMM y" (e.g., "2 Ocak 2026")
      final parts = dateStr.split(' ');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = _getMonthNumber(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (e) {
      logger.err('Error parsing date string: {}', [e]);
    }
    // Return today as fallback
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  int _getMonthNumber(String monthName) {
    const months = {
      'Ocak': 1,
      'Şubat': 2,
      'Mart': 3,
      'Nisan': 4,
      'Mayıs': 5,
      'Haziran': 6,
      'Temmuz': 7,
      'Ağustos': 8,
      'Eylül': 9,
      'Ekim': 10,
      'Kasım': 11,
      'Aralık': 12
    };
    return months[monthName] ?? 1;
  }

  void _showMealDetails(
      BuildContext context,
      MealModel meal,
      double dialogImageHeight,
      String heroTag,
      ) {
    showDialog(
      context: context,
      builder: (context) {
        const double kDialogMaxWidth = 520;
        final screen = MediaQuery.of(context).size;
        final double approxBodyWidth =
        (screen.width - 64).clamp(280.0, kDialogMaxWidth);

        return AlertDialog(
          insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text(
            '${meal.mealType.label} - ${DateFormat('d MMMM y, HH:mm', 'tr_TR').format(meal.timestamp)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: heroTag,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: approxBodyWidth,
                        height: dialogImageHeight,
                        child: InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: ChatImagePreview(
                            imageUrl: meal.imageUrl,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (meal.description != null &&
                      meal.description!.isNotEmpty) ...[
                    const Text(
                      'Açıklama:',
                      style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(meal.description!),
                    const SizedBox(height: 16),
                  ],

                  // const Text(
                  //   'Yüklenme Zamanı:',
                  //   style:
                  //   TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  // ),
                  // const SizedBox(height: 4),
                  // Text(
                  //   DateFormat('dd-MM-yyyy, HH:mm').format(meal.timestamp),
                  // ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
  }

}
