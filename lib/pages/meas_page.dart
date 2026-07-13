import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/meas_model.dart';
import '../providers/meas_provider.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/measurement_line_chart.dart';

/// How the measurement data is presented to the user.
enum _MeasView { table, chart }

/// User-facing measurement page (read-only view)
class MeasurementPage extends StatefulWidget {
  final String userId;
  const MeasurementPage({super.key, required this.userId});

  @override
  State<MeasurementPage> createState() => _MeasurementPageState();
}

class _MeasurementPageState extends State<MeasurementPage> {
  List<MeasurementModel> _measurements = [];
  bool _isLoading = true;

  _MeasView _view = _MeasView.table;

  // Scroll controllers
  final ScrollController _verticalCtrl = ScrollController();
  final ScrollController _horizontalCtrl = ScrollController();
  final ScrollController _chartsCtrl = ScrollController();

  // Column widths for table alignment
  static const double _wDate = 110;
  static const double _wNum = 70;
  static const double _rowHPad = 12;

  // Formatters
  static final DateFormat _dateFormat = DateFormat('d MMM yyyy', 'tr_TR');

  double get _tableWidth => _wDate + (8 * _wNum);

  @override
  void initState() {
    super.initState();
    _loadMeasurements();
  }

  @override
  void dispose() {
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    _chartsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMeasurements() async {
    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<MeasProvider>(context, listen: false);
      final data = await provider.fetchMeasurements(widget.userId);
      if (mounted) {
        setState(() {
          _measurements = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Ölçümler yüklenemedi: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWithBack(title: 'Ölçümlerim'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _measurements.isEmpty
                      ? _buildEmptyState()
                      : (_view == _MeasView.table
                          ? _buildMeasurementsTable()
                          : _buildChartsView()),
                ),
              ],
            ),
    );
  }

  /// Header with summary and Tanita button
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(bottom: BorderSide(color: Colors.blue.shade100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Latest measurement summary (if exists)
          if (_measurements.isNotEmpty) _buildLatestSummaryCard(),
          // Table / chart view switch (only meaningful when data exists)
          if (_measurements.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildViewToggle(),
          ],
          const SizedBox(height: 12),
          // Tanita button
          _buildTanitaButton(),
        ],
      ),
    );
  }

  /// Segmented control to switch between the table and the charts view.
  Widget _buildViewToggle() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_MeasView>(
        segments: const [
          ButtonSegment(
            value: _MeasView.table,
            icon: Icon(Icons.table_rows, size: 18),
            label: Text('Tablo'),
          ),
          ButtonSegment(
            value: _MeasView.chart,
            icon: Icon(Icons.show_chart, size: 18),
            label: Text('Grafik'),
          ),
        ],
        selected: {_view},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          setState(() => _view = selection.first);
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.blue.shade600;
            }
            return Colors.white;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.blue.shade700;
          }),
        ),
      ),
    );
  }

  /// Summary card showing latest measurement (compact version)
  Widget _buildLatestSummaryCard() {
    final latest = _measurements.first;
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today, color: Colors.white70, size: 12),
              const SizedBox(width: 4),
              Text(
                'Son Ölçüm: ${_dateFormat.format(latest.measDate)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildSummaryItem('Ağırlık', latest.weight, 'kg', Icons.monitor_weight),
              const SizedBox(width: 8),
              _buildSummaryItem('Yağ', latest.fatKg, 'kg', Icons.water_drop),
              const SizedBox(width: 8),
              _buildSummaryItem('Bel', latest.waist, 'cm', Icons.straighten),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, double? value, String unit, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(height: 2),
            Text(
              value != null ? '${value.toStringAsFixed(1)} $unit' : '-',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tanita PDF viewer button
  Widget _buildTanitaButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showTanitaPdfs,
        icon: const Icon(Icons.fitness_center),
        label: const Text('Tanita Raporlarını Görüntüle'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  /// Show Tanita PDFs in a bottom sheet
  Future<void> _showTanitaPdfs() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Colors.purple.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Tanita Raporları',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // PDF list
              Expanded(
                child: FutureBuilder<List<_TanitaPdf>>(
                  future: _fetchTanitaPdfs(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Hata: ${snapshot.error}',
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      );
                    }
                    final pdfs = snapshot.data ?? [];
                    if (pdfs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'Henüz Tanita raporu yüklenmemiş',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: pdfs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final pdf = pdfs[index];
                        return _buildPdfListItem(pdf);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPdfListItem(_TanitaPdf pdf) {
    return Material(
      color: Colors.purple.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openPdf(pdf.pdfUrl),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.picture_as_pdf, color: Colors.purple.shade700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pdf.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (pdf.uploadTime != null)
                      Text(
                        DateFormat('d MMMM yyyy, HH:mm', 'tr_TR').format(pdf.uploadTime!),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new, color: Colors.purple.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<_TanitaPdf>> _fetchTanitaPdfs() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('measurements')
        .doc('tanita')
        .collection('pdfFiles')
        .orderBy('uploadTime', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return _TanitaPdf(
        pdfUrl: data['pdfUrl'] ?? '',
        fileName: data['fileName'] ?? 'Tanita Raporu',
        uploadTime: (data['uploadTime'] as Timestamp?)?.toDate(),
      );
    }).toList();
  }

  Future<void> _openPdf(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'PDF açılamadı.',
        );
      }
    }
  }

  /// Empty state when no measurements
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.straighten,
              size: 48,
              color: Colors.blue.shade300,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Henüz ölçüm bulunmuyor',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'İlk ölçümünüz eklendiğinde\nburada görüntülenecek.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  /// Metrics that can be charted over time (y = value, x = date).
  List<_ChartMetric> get _chartMetrics => const [
        _ChartMetric('Ağırlık', 'kg', Color(0xFF2563EB), _MetricField.weight),
        _ChartMetric('Yağ', 'kg', Color(0xFFDB2777), _MetricField.fatKg),
        _ChartMetric('Bel', 'cm', Color(0xFF059669), _MetricField.waist),
        _ChartMetric('Göğüs', 'cm', Color(0xFF7C3AED), _MetricField.chest),
        _ChartMetric('Sırt', 'cm', Color(0xFF0891B2), _MetricField.back),
        _ChartMetric('Kalça', 'cm', Color(0xFFEA580C), _MetricField.hips),
        _ChartMetric('Bacak', 'cm', Color(0xFF16A34A), _MetricField.leg),
        _ChartMetric('Kol', 'cm', Color(0xFFCA8A04), _MetricField.arm),
        _ChartMetric('Kalori', 'kcal', Color(0xFFDC2626), _MetricField.calorie),
      ];

  /// Charts view: one line chart per metric that has data.
  Widget _buildChartsView() {
    // Chart the oldest -> newest, independent of the table's ordering.
    final ascending = [..._measurements]
      ..sort((a, b) => a.measDate.compareTo(b.measDate));

    // Keep only metrics that actually have at least one value.
    final series = <_MetricSeries>[];
    for (final metric in _chartMetrics) {
      final points = <ChartPoint>[];
      for (final m in ascending) {
        final value = metric.valueOf(m);
        if (value != null) points.add(ChartPoint(m.measDate, value));
      }
      if (points.isNotEmpty) series.add(_MetricSeries(metric, points));
    }

    if (series.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Grafik oluşturmak için sayısal ölçüm verisi bulunmuyor.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _chartsCtrl,
      thumbVisibility: true,
      child: ListView.separated(
        controller: _chartsCtrl,
        primary: false,
        padding: const EdgeInsets.all(16),
        itemCount: series.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) => _buildMetricCard(series[i]),
      ),
    );
  }

  Widget _buildMetricCard(_MetricSeries series) {
    final metric = series.metric;
    final points = series.points;

    final values = points.map((p) => p.value).toList();
    final last = values.last;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final double? prev = points.length >= 2 ? values[values.length - 2] : null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + latest value + delta
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: metric.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${metric.label} (${metric.unit})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_formatMetric(last)} ${metric.unit}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: metric.color,
                      ),
                    ),
                    if (prev != null) _buildDeltaChip(last - prev, metric.unit),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            MeasurementLineChart(
              points: points,
              color: metric.color,
              unit: metric.unit,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStat('En düşük', '${_formatMetric(minV)} ${metric.unit}'),
                _buildStat('En yüksek', '${_formatMetric(maxV)} ${metric.unit}'),
                _buildStat('Kayıt', '${points.length}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeltaChip(double delta, String unit) {
    final isFlat = delta.abs() < 1e-6;
    final isUp = delta > 0;
    final color = isFlat
        ? Colors.grey.shade600
        : (isUp ? const Color(0xFFEA580C) : const Color(0xFF16A34A));
    final icon = isFlat
        ? Icons.remove
        : (isUp ? Icons.arrow_upward : Icons.arrow_downward);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          '${_formatMetric(delta.abs())} $unit',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _formatMetric(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-6) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  /// Measurements table (matching admin style)
  Widget _buildMeasurementsTable() {
    return LayoutBuilder(
      builder: (context, viewport) {
        // Calculate width to accommodate table + row padding
        final contentWidth = math.max(_tableWidth + (_rowHPad * 2), viewport.maxWidth);

        return Scrollbar(
          controller: _horizontalCtrl,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalCtrl,
            scrollDirection: Axis.horizontal,
            primary: false,
            child: SizedBox(
              width: contentWidth,
              child: Column(
                children: [
                  // Sticky header - always visible
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildHeaderRow(),
                  ),
                  const Divider(height: 1),
                  // Scrollable data rows
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalCtrl,
                      thumbVisibility: true,
                      notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                      child: ListView.separated(
                        controller: _verticalCtrl,
                        primary: false,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _measurements.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          return _buildDataRow(_measurements[index]);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hCell(String text, double width, {TextAlign align = TextAlign.center}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          textAlign: align,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          text,
          textAlign: align,
          style: const TextStyle(fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _formatNum(num? n) => n == null ? '-' : n.toString();

  Widget _buildHeaderRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _rowHPad, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _hCell('Tarih', _wDate, align: TextAlign.left),
          _hCell('Göğüs\n(cm)', _wNum),
          _hCell('Sırt\n(cm)', _wNum),
          _hCell('Bel\n(cm)', _wNum),
          _hCell('Kalça\n(cm)', _wNum),
          _hCell('Bacak\n(cm)', _wNum),
          _hCell('Kol\n(cm)', _wNum),
          _hCell('Ağırlık\n(kg)', _wNum),
          _hCell('Yağ\n(kg)', _wNum),
        ],
      ),
    );
  }

  Widget _buildDataRow(MeasurementModel m) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _rowHPad, vertical: 12),
      child: Row(
        children: [
          _dCell(_dateFormat.format(m.measDate), _wDate, align: TextAlign.left),
          _dCell(_formatNum(m.chest), _wNum),
          _dCell(_formatNum(m.back), _wNum),
          _dCell(_formatNum(m.waist), _wNum),
          _dCell(_formatNum(m.hips), _wNum),
          _dCell(_formatNum(m.leg), _wNum),
          _dCell(_formatNum(m.arm), _wNum),
          _dCell(_formatNum(m.weight), _wNum),
          _dCell(_formatNum(m.fatKg), _wNum),
        ],
      ),
    );
  }
}

/// Simple model for Tanita PDF
class _TanitaPdf {
  final String pdfUrl;
  final String fileName;
  final DateTime? uploadTime;

  _TanitaPdf({
    required this.pdfUrl,
    required this.fileName,
    this.uploadTime,
  });
}

/// Numeric fields of [MeasurementModel] that can be plotted.
enum _MetricField { chest, back, waist, hips, leg, arm, weight, fatKg, calorie }

/// Describes a single chartable metric (label, unit, colour and source field).
class _ChartMetric {
  final String label;
  final String unit;
  final Color color;
  final _MetricField field;

  const _ChartMetric(this.label, this.unit, this.color, this.field);

  double? valueOf(MeasurementModel m) {
    switch (field) {
      case _MetricField.chest:
        return m.chest;
      case _MetricField.back:
        return m.back;
      case _MetricField.waist:
        return m.waist;
      case _MetricField.hips:
        return m.hips;
      case _MetricField.leg:
        return m.leg;
      case _MetricField.arm:
        return m.arm;
      case _MetricField.weight:
        return m.weight;
      case _MetricField.fatKg:
        return m.fatKg;
      case _MetricField.calorie:
        return m.calorie?.toDouble();
    }
  }
}

/// A metric paired with its non-null data points, ready to chart.
class _MetricSeries {
  final _ChartMetric metric;
  final List<ChartPoint> points;

  const _MetricSeries(this.metric, this.points);
}
