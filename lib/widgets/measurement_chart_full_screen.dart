part of 'measurement_line_chart.dart';

/// Full-screen version of [MeasurementLineChart].
///
/// Unlike the compact chart it draws the *whole* history: every point gets a
/// fixed slot ([MeasurementChartConfig.fullScreenPointSpacing]) and the plot is
/// scrolled horizontally, so the user can walk back and forth in time without
/// the points or the date labels ever piling up. The value axis stays pinned on
/// the left while the plot scrolls.
class MeasurementChartFullScreenPage extends StatefulWidget {
  /// Points to plot, sorted ascending by [ChartPoint.date].
  final List<ChartPoint> points;

  /// Accent colour for the line, fill and highlighted point.
  final Color color;

  /// Unit label (e.g. "kg", "cm").
  final String unit;

  /// Metric name, shown in the app bar.
  final String title;

  const MeasurementChartFullScreenPage({
    super.key,
    required this.points,
    required this.color,
    required this.unit,
    required this.title,
  });

  @override
  State<MeasurementChartFullScreenPage> createState() =>
      _MeasurementChartFullScreenPageState();
}

class _MeasurementChartFullScreenPageState
    extends State<MeasurementChartFullScreenPage> {
  static const String _hint =
      'Grafiği yana kaydırarak geçmiş ölçümleri inceleyebilirsiniz. '
      'Bir noktaya dokunarak değerini görebilirsiniz.';
  static const String _emptyMessage = 'Gösterilecek ölçüm verisi bulunmuyor.';

  /// Paddings of the scrolling plot area. The bottom band holds the date
  /// labels; the fixed value axis uses the same top/bottom values so the two
  /// halves line their ticks up.
  static const EdgeInsets _plotPadding = EdgeInsets.fromLTRB(28, 16, 28, 32);

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Start at the most recent measurement, like the compact chart's right
    // edge, and let the user scroll back into the past from there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  double _contentWidth(double viewportWidth) {
    final slots = math.max(0, widget.points.length - 1);
    final needed = _plotPadding.horizontal +
        slots * MeasurementChartConfig.fullScreenPointSpacing;
    return math.max(viewportWidth, needed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWithBack(title: '${widget.title} (${widget.unit})'),
      body: widget.points.isEmpty ? _buildEmptyState() : _buildChart(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _emptyMessage,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _buildChart() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 12, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxHeight;
                final viewportWidth = math.max(
                  1.0,
                  constraints.maxWidth - MeasurementChartConfig.fullScreenAxisWidth,
                );
                final contentWidth = _contentWidth(viewportWidth);

                return Row(
                  children: [
                    // Pinned value axis: stays put while the plot scrolls.
                    CustomPaint(
                      size: Size(
                        MeasurementChartConfig.fullScreenAxisWidth,
                        height,
                      ),
                      painter: _ValueAxisPainter(
                        points: widget.points,
                        top: _plotPadding.top,
                        bottom: height - _plotPadding.bottom,
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollCtrl,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _scrollCtrl,
                          scrollDirection: Axis.horizontal,
                          primary: false,
                          child: _ChartSurface(
                            points: widget.points,
                            color: widget.color,
                            unit: widget.unit,
                            size: Size(contentWidth, height),
                            xMode: _XAxisMode.evenlySpaced,
                            padding: _plotPadding,
                            // Drawn by the pinned axis above.
                            showValueLabels: false,
                            // Horizontal drags scroll the chart here.
                            enableDragInspect: false,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildFooter() {
    final first = widget.points.first.date;
    final last = widget.points.last.date;
    final format = DateFormat('d MMM y', 'tr_TR');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.points.length} kayıt • '
            '${format.format(first)} - ${format.format(last)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _hint,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// Paints the pinned value-axis strip of [MeasurementChartFullScreenPage].
///
/// Uses the same [_VerticalScale] as the scrolling plot, so its labels sit
/// exactly on the plot's grid lines.
class _ValueAxisPainter extends CustomPainter {
  final List<ChartPoint> points;
  final double top;
  final double bottom;

  _ValueAxisPainter({
    required this.points,
    required this.top,
    required this.bottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final scale = _VerticalScale.forPoints(points, top: top, bottom: bottom);
    final tickPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;

    for (final tick in scale.ticks) {
      final y = scale.yFor(tick);
      if (y < top - 0.5 || y > bottom + 0.5) continue;

      final label = _layoutText(_formatValue(tick), _axisLabelStyle);
      label.paint(
        canvas,
        Offset(size.width - 6 - label.width, y - label.height / 2),
      );
      canvas.drawLine(
        Offset(size.width - 3, y),
        Offset(size.width, y),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ValueAxisPainter old) {
    return old.points != points || old.top != top || old.bottom != bottom;
  }
}
