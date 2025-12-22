// measurements_tab.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../dialogs/add_meas_dialog.dart';
import '../dialogs/edit_meas_dialog.dart';
import '../models/meas_model.dart';
import '../models/filter_params.dart';
import '../pages/tanita_explorer_page.dart';
import '../providers/meas_provider.dart';
import 'basetab.dart';
import 'filterable_tab.dart';
import '../models/logger.dart';
import '../utils/dialog_utils.dart';

class MeasTab extends BaseTab<MeasProvider> {
  const MeasTab({super.key, required super.userId})
      : super(allDataLabel: 'Tüm Ölçümler', subscriptionDataLabel: 'Tüm Ölçümler');

  @override
  MeasProvider getProvider(BuildContext context) =>
      Provider.of<MeasProvider>(context, listen: false);

  @override
  Future<List<dynamic>> getDataList(MeasProvider provider, bool showAllData, {FilterParams? filterParams}) =>
      provider.fetchMeasurements(userId, filterParams: filterParams as MeasurementFilterParams?);

  @override
  BaseTabState<MeasProvider, BaseTab<MeasProvider>> createState() => _MeasurementsTabState();
}

class _MeasurementsTabState extends FilterableTabState<MeasProvider, BaseTab<MeasProvider>> {
  final Logger logger = Logger.forClass(_MeasurementsTabState);

  bool _isSaving = false;
  late final MeasProvider _measProvider;

  // Single vertical scroller (like AppointmentsTab)
  final ScrollController _listCtrl = ScrollController();
  // Horizontal scroller for when columns overflow
  final ScrollController _hCtrl = ScrollController();

  // ---- Column widths (px) to keep header & rows aligned ----
  static const double _wDate = 120;
  static const double _wNum = 80; // chest/back/waist/hips/leg/arm/weight/fat
  static const double _wHunger = 140;
  static const double _wConstip = 140;
  static const double _wOther = 260;
  static const double _wCal = 80;
  static const double _wActions = 120;

  // Row horizontal padding (must match header/data row padding)
  static const double _rowHPad = 12;

  double get _tableWidth =>
      _wDate +
          (8 * _wNum) +
          _wHunger +
          _wConstip +
          _wOther +
          _wCal +
          _wActions; // = 1500

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupMeasurementListener());
  }

  void _setupMeasurementListener() {
    _measProvider = Provider.of<MeasProvider>(context, listen: false);
    _measProvider.addListener(_onMeasurementProviderChanged);
  }

  void _onMeasurementProviderChanged() {
    if (_measProvider.measurementChanged) {
      _measProvider.resetMeasurementChanged();
      refreshData();
    }
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    _hCtrl.dispose();
    _measProvider.removeListener(_onMeasurementProviderChanged);
    super.dispose();
  }

  @override
  FilterParams? buildFilterParams() {
    return MeasurementFilterParams(
      searchQuery: searchQuery.isNotEmpty ? searchQuery : null,
      dateRange: selectedDateRange,
    );
  }

  Future<void> _addRow() async {
    logger.info('AddMeasurementDialog opening...');
    await showDialog(
      context: context,
      builder: (ctx) => AddMeasurementDialog(
        userId: widget.userId,
        onMeasurementAdded: () => refreshData(),
      ),
    );
  }

  Future<void> _pickAndParseExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null) return;

      setState(() => _isSaving = true);
      try {
        final fileBytes = await File(result.files.single.path!).readAsBytes();
        final excel = Excel.decodeBytes(fileBytes);

        final measurements = <MeasurementModel>[];
        final sheet = excel.tables.keys.first;
        var rowIndex = 2;
        // Generate a base timestamp once, then append row index for unique IDs
        final baseTimestamp = DateTime.now().millisecondsSinceEpoch;

        while (rowIndex < excel.tables[sheet]!.maxRows) {
          try {
            final row = excel.tables[sheet]!.rows[rowIndex];
            if (row.isEmpty || row[0]?.value == null) {
              rowIndex++;
              continue;
            }

            // date parsing
            DateTime date;
            final dateCell = row[0]?.value;
            if (dateCell is DateTime) {
              date = dateCell;
            } else if (dateCell is num) {
              final excelEpoch = DateTime(1899, 12, 30);
              date = excelEpoch.add(Duration(days: dateCell.toInt()));
            } else {
              try {
                date = DateFormat('yyyy-MM-dd').parse(dateCell.toString());
              } catch (_) {
                rowIndex++;
                continue;
              }
            }

            double? _numCell(int i) =>
                (row.length > i && row[i] != null) ? double.tryParse(row[i]!.value.toString()) : null;
            String? _strCell(int i) {
              if (row.length <= i || row[i] == null) return null;
              final s = row[i]!.value?.toString().trim();
              return (s == null || s.isEmpty) ? null : s;
            }

            // columns mapped
            final chest = _numCell(1);
            final back = _numCell(2);
            final waist = _numCell(3);
            final hips = _numCell(4);
            final leg = _numCell(5);
            final arm = _numCell(6);
            final weight = _numCell(7);

            // robust fat cell
            double? fatKg;
            final fatRaw = row.length > 8 ? row[8]?.value : null;
            if (fatRaw != null) {
              final s = fatRaw.toString();
              fatKg = double.tryParse(s);
              if (fatKg == null || fatKg > 500) {
                final dMatch = RegExp(r'(\d{1,2})\.(\d{1,2})').firstMatch(s);
                if (dMatch != null) {
                 fatKg = double.tryParse('${dMatch.group(1)}.${int.parse(dMatch.group(2)!)}');
                } else if (fatRaw is num) {
                  final excelEpoch = DateTime(1899, 12, 30);
                  final d = excelEpoch.add(Duration(days: fatRaw.toInt()));
                  fatKg = double.tryParse('${d.day}.${d.month}');
                }
                logger.info('fatRaw={},fatKg={}',[fatRaw,fatKg]);
              }
            }

            final hunger = _strCell(9);
            final constip = _strCell(10);
            final other = _strCell(11);

            final calorie = () {
              if (row.length < 13 || row[12] == null) return null;
              return int.tryParse(row[12]!.value.toString());
            }();



            measurements.add(MeasurementModel(
              measDate: date,
              measurementId: '${baseTimestamp}_$rowIndex',
              weight: weight,
              chest: chest,
              back: back,
              waist: waist,
              hips: hips,
              leg: leg,
              arm: arm,
              fatKg: fatKg,
              calorie: calorie,
              hungerStatus: hunger,
              constipation: constip,
              other: other,
            ));
          } catch (e) {
            logger.warn('Error parsing row $rowIndex: $e');
          }
          rowIndex++;
        }

        setState(() => _isSaving = false);

        if (measurements.isEmpty) {
          await DialogUtils.openError(context, title: 'Hata', message: 'Excel dosyasında geçerli ölçüm verisi yok.');
          return;
        }

        final dateRange =
            '${DateFormat('d MMMM y', 'tr_TR').format(measurements.first.measDate)} - ${DateFormat('d MMMM y', 'tr_TR').format(measurements.last.measDate)}';

        int countOf(bool Function(MeasurementModel m) p) => measurements.where(p).length;

        final confirmed = await DialogUtils.openConfirm(
          context,
          title: 'Ölçümler Bulundu',
          message: '${measurements.length} ölçüm bulundu ($dateRange).\n\n'
              '- Göğüs: ${countOf((m) => m.chest != null)}\n'
              '- Sırt: ${countOf((m) => m.back != null)}\n'
              '- Bel: ${countOf((m) => m.waist != null)}\n'
              '- Kalça: ${countOf((m) => m.hips != null)}\n'
              '- Bacak: ${countOf((m) => m.leg != null)}\n'
              '- Kol: ${countOf((m) => m.arm != null)}\n'
              '- Ağırlık: ${countOf((m) => m.weight != null)}\n'
              '- Yağ: ${countOf((m) => m.fatKg != null)}\n'
              '- Kalori: ${countOf((m) => m.calorie != null)}\n\n'
              'İçe aktarılsın mı?',
        );

        if (confirmed && mounted) {
          setState(() => _isSaving = true);
          try {
            final provider = Provider.of<MeasProvider>(context, listen: false);
            await provider.addBatchMeasurement(widget.userId, measurements);
            await DialogUtils.openInfo(context, title: 'Başarılı', message: '${measurements.length} ölçüm içe aktarıldı.');
            refreshData();
          } catch (e) {
            await DialogUtils.openError(context, title: 'Hata', message: 'Ölçümler kaydedilemedi: $e');
          } finally {
            if (mounted) setState(() => _isSaving = false);
          }
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        await DialogUtils.openError(context, title: 'Hata', message: 'Excel işleme hatası: $e');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      await DialogUtils.openError(context, title: 'Hata', message: 'Excel içe aktarma hatası: $e');
    }
  }

  Future<void> _deleteMeasurement(MeasurementModel measurement) async {
    logger.info('Preparing to delete measurement: {}', [measurement]);
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Ölçümü Sil',
      message: '${DateFormat('d MMMM y', 'tr_TR').format(measurement.measDate)} tarihli ölçüm silinsin mi?',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final provider = Provider.of<MeasProvider>(context, listen: false);
      final success = await provider.deleteMeasurement(widget.userId, measurement.measurementId);
      if (!success) throw Exception('Ölçüm silinemedi');
      if (mounted) {
        await DialogUtils.openInfo(context, title: 'Başarılı', message: 'Ölçüm silindi.');
        refreshData();
      }
    } catch (e) {
      await DialogUtils.openError(context, title: 'Hata', message: 'Ölçüm silinirken hata oluştu: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget buildList(BuildContext context, List<dynamic> dataList) {
    final filteredItems = getFilteredItems(dataList);

    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    return Column(
      children: [
        // Non-scrolling header (actions + filters)
        Container(
          padding: const EdgeInsets.all(16),
          child: isNarrow
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: toggleFilters,
                    icon: const Icon(Icons.filter_alt),
                    label: const Text('Filtrele'),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: buildActiveFiltersSummary(filteredItems.length, dataList.length)),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _addRow,
                    icon: _isSaving
                        ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add),
                    label: const Text('Yeni Ölçüm'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _pickAndParseExcel,
                    icon: _isSaving
                        ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.table_chart),
                    label: const Text('Excel İçe Aktar'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TanitaExplorerPage(userId: widget.userId)),
                    ),
                    icon: const Icon(Icons.fitness_center),
                    label: const Text('Tanita'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ]),
              ),
            ],
          )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: toggleFilters,
                    icon: const Icon(Icons.filter_alt),
                    label: const Text('Filtrele'),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: buildActiveFiltersSummary(filteredItems.length, dataList.length)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _addRow,
                    icon: _isSaving
                        ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add),
                    label: const Text('Yeni Ölçüm'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _pickAndParseExcel,
                    icon: _isSaving
                        ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.table_chart),
                    label: const Text('Excel İçe Aktar'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TanitaExplorerPage(userId: widget.userId)),
                    ),
                    icon: const Icon(Icons.fitness_center),
                    label: const Text('Tanita'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Single scroll area (vertical ListView) wrapped by horizontal scroll container
        Expanded(
          child: filteredItems.isEmpty
              ? buildEmptyState()
              : buildFilteredContent(context, filteredItems),
        ),
      ],
    );
  }

  @override
  Widget buildFilterContent(BuildContext context, List<dynamic> allItems, List<dynamic> filteredItems) {
    return buildFilterSection(
      title: 'Ölçüm Filtreleri',
      filterWidgets: [
        buildSearchField(hintText: 'Tarihe göre ara...'),
        const SizedBox(height: 16),
        buildDateRangeFilter(),
        const SizedBox(height: 16),
        Text(
          '${filteredItems.length} ölçüm listeleniyor',
          style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey[700]),
        ),
        buildFilterActionButtons(),
      ],
    );
  }

  @override
  Widget buildFilteredContent(BuildContext context, List<dynamic> filteredItems) {
    final items = List<MeasurementModel>.from(filteredItems.cast<MeasurementModel>());

    return LayoutBuilder(
      builder: (context, viewport) {
        // include left+right row padding so children never exceed constraints
        final double contentWidth = math.max(_tableWidth + _rowHPad * 2, viewport.maxWidth);

        return Scrollbar(
          controller: _hCtrl,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _hCtrl,
            scrollDirection: Axis.horizontal,
            primary: false,
            child: _buildTableList(items, contentWidth), // <-- pass width down
          ),
        );
      },
    );
  }

  // ---------- Table-like list with one vertical scroll ----------
  Widget _buildTableList(List<MeasurementModel> measurements, double contentWidth) {
    final listKey = ValueKey<String>(measurements.map((m) => m.measurementId).join('|'));

    return SizedBox(
      width: contentWidth, // <-- ListView now truly wider than the viewport when needed
      child: Scrollbar(
        controller: _listCtrl,
        thumbVisibility: true,
        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
        child: ListView.separated(
          key: listKey,
          controller: _listCtrl,
          primary: false,
          // IMPORTANT: no horizontal padding here; we already accounted for row padding in contentWidth
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: measurements.length + 1, // +1 header
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == 0) return _buildHeaderRow();
            final m = measurements[index - 1];
            return _buildDataRow(context, m);
          },
        ),
      ),
    );
  }

  // ---- Header & cell builders (fixed widths keep alignment) ----
  Widget _hCell(String text, double width, {TextAlign align = TextAlign.center}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          text,
          textAlign: align,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _dCell(String text, double width, {TextAlign align = TextAlign.center}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _vNum(num? n) => n == null ? '-' : n.toString();

  Widget _buildHeaderRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _rowHPad, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _hCell('Tarih', _wDate, align: TextAlign.left),

          // two-line headers
          _hCell('Göğüs\n(cm)', _wNum),   // if you already had Göğüs two-line, this keeps it
          _hCell('Sırt\n(cm)',  _wNum),   // <- changed
          _hCell('Bel\n(cm)',   _wNum),   // <- changed

          // keep these single-line (as before), or switch to two-line if you want consistency
          _hCell('Kalça (cm)',  _wNum),
          _hCell('Bacak (cm)',  _wNum),

          // two-line
          _hCell('Kol\n(cm)',    _wNum),  // <- changed

          // keep single-line for weight, unless you want to split it too
          _hCell('Ağırlık (kg)', _wNum),

          // two-line
          _hCell('Yağ\n(kg)',    _wNum),  // <- changed

          // unchanged
          _hCell('Açlık',        _wHunger),
          _hCell('Kabızlık',     _wConstip),
          _hCell('Diğer',        _wOther, align: TextAlign.left),
          _hCell('Kalori',       _wCal),
          _hCell('İşlemler',     _wActions),
        ],
      ),
    );
  }

  Widget _buildDataRow(BuildContext context, MeasurementModel m) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _rowHPad, vertical: 10),
      child: Row(
        children: [
          _dCell(DateFormat('d MMMM y', 'tr_TR').format(m.measDate), _wDate, align: TextAlign.left),
          _dCell(_vNum(m.chest), _wNum),
          _dCell(_vNum(m.back), _wNum),
          _dCell(_vNum(m.waist), _wNum),
          _dCell(_vNum(m.hips), _wNum),
          _dCell(_vNum(m.leg), _wNum),
          _dCell(_vNum(m.arm), _wNum),
          _dCell(_vNum(m.weight), _wNum),
          _dCell(_vNum(m.fatKg), _wNum),
          _dCell(m.hungerStatus ?? '-', _wHunger),
          _dCell(m.constipation ?? '-', _wConstip),
          _dCell(m.other ?? '-', _wOther, align: TextAlign.left),
          _dCell(_vNum(m.calorie), _wCal),
          SizedBox(
            width: _wActions,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showEditMeasurementDialog(context, m)),
                IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => _deleteMeasurement(m)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditMeasurementDialog(BuildContext context, MeasurementModel m) {
    showDialog(
      context: context,
      builder: (_) => EditMeasurementDialog(
        userId: widget.userId,
        measurement: m,
        onMeasurementUpdated: () => refreshData(),
      ),
    );
  }
}
