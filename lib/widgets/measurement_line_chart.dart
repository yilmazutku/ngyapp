import 'dart:math' as math;

import 'package:flutter/material.dart';
// intl also exports a `TextDirection`; hide it so the dart:ui one (used by
// TextPainter) is unambiguous.
import 'package:intl/intl.dart' hide TextDirection;

import 'app_bar_with_back.dart';

part 'measurement_chart_full_screen.dart';

/// A single data point on a [MeasurementLineChart].
class ChartPoint {
  final DateTime date;
  final double value;

  const ChartPoint(this.date, this.value);
}

/// Tunable layout values for the measurement charts.
///
/// Kept in one place so the chart density can be tried out without hunting
/// through the painting code.
class MeasurementChartConfig {
  MeasurementChartConfig._();

  /// How many data points the compact (in-card) chart may draw at once.
  ///
  /// Only the most recent [maxCompactPoints] measurements are plotted there;
  /// beyond that the line and the date labels get too crowded to read on a
  /// phone. The full-screen chart ignores this limit and shows every point.
  static const int maxCompactPoints = 8;

  /// Height of the compact (in-card) chart's drawing area.
  static const double compactHeight = 180;

  /// Horizontal space reserved per data point in the full-screen chart.
  ///
  /// The content is as wide as it needs to be to give every point this much
  /// room, which is what makes the full-screen chart scrollable in time.
  static const double fullScreenPointSpacing = 76;

  /// Minimum horizontal gap kept between two neighbouring x-axis date labels.
  /// Labels that would come closer than this are skipped instead of drawn on
  /// top of each other.
  static const double minDateLabelGap = 10;

  /// Width of the fixed value-axis strip of the full-screen chart.
  static const double fullScreenAxisWidth = 46;
}

/// How x (date) positions are mapped to pixels.
enum _XAxisMode {
  /// Positions are proportional to the actual dates: gaps in time show up as
  /// gaps in the chart. Used by the compact chart, whose width is fixed.
  time,

  /// Every point gets the same slot width. Used by the scrollable full-screen
  /// chart so points never pile up, no matter how close their dates are.
  evenlySpaced,
}

/// A lightweight, dependency-free line chart used to visualise a single
/// measurement metric over time (y = value, x = date).
///
/// Only the most recent [maxPoints] points are drawn so the date labels stay
/// readable; a "Büyüt" button opens [MeasurementChartFullScreenPage], which
/// shows the whole history and can be scrolled along the date axis.
class MeasurementLineChart extends StatelessWidget {
  /// Points to plot. Should be sorted ascending by [ChartPoint.date].
  final List<ChartPoint> points;

  /// Accent colour for the line, fill and highlighted point.
  final Color color;

  /// Unit label shown in the inspection tooltip (e.g. "kg", "cm").
  final String unit;

  /// Metric name, shown as the title of the full-screen chart.
  final String title;

  /// Fixed drawing height of the chart area.
  final double height;

  /// Maximum number of (most recent) points drawn here.
  final int maxPoints;

  const MeasurementLineChart({
    super.key,
    required this.points,
    required this.color,
    required this.unit,
    required this.title,
    this.height = MeasurementChartConfig.compactHeight,
    this.maxPoints = MeasurementChartConfig.maxCompactPoints,
  });

  static const String _expandLabel = 'Büyüt';
  static const EdgeInsets _padding =
      EdgeInsets.fromLTRB(46, 16, 14, 30);

  /// The tail of [points] that actually fits into the compact chart.
  List<ChartPoint> get _visiblePoints => points.length > maxPoints
      ? points.sublist(points.length - maxPoints)
      : points;

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MeasurementChartFullScreenPage(
          points: points,
          color: color,
          unit: unit,
          title: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePoints;
    final isTruncated = visible.length < points.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: isTruncated
                  ? Text(
                      'Son ${visible.length} ölçüm',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
            TextButton.icon(
              onPressed: () => _openFullScreen(context),
              icon: const Icon(Icons.open_in_full, size: 16),
              label: const Text(_expandLabel),
              style: TextButton.styleFrom(
                foregroundColor: color,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            return _ChartSurface(
              points: visible,
              color: color,
              unit: unit,
              size: Size(constraints.maxWidth, height),
              xMode: _XAxisMode.time,
              padding: _padding,
            );
          },
        ),
      ],
    );
  }
}

/// Paints a chart of [points] and lets the user inspect a single value by
/// tapping (and, when [enableDragInspect] is set, dragging) across it.
///
/// Shared by the compact and the full-screen chart; the caller decides the
/// canvas size, the x mapping and the paddings.
class _ChartSurface extends StatefulWidget {
  final List<ChartPoint> points;
  final Color color;
  final String unit;
  final Size size;
  final _XAxisMode xMode;
  final EdgeInsets padding;

  /// Whether the value labels are drawn here. The full-screen chart draws them
  /// in a fixed strip instead, so they stay visible while scrolling.
  final bool showValueLabels;

  /// Horizontal dragging inspects points. Must stay off inside a horizontal
  /// scroll view, where dragging means scrolling.
  final bool enableDragInspect;

  const _ChartSurface({
    required this.points,
    required this.color,
    required this.unit,
    required this.size,
    required this.xMode,
    required this.padding,
    this.showValueLabels = true,
    this.enableDragInspect = true,
  });

  @override
  State<_ChartSurface> createState() => _ChartSurfaceState();
}

class _ChartSurfaceState extends State<_ChartSurface> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant _ChartSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the selection inside the (possibly shorter) new series.
    final index = _selectedIndex;
    if (index != null && index >= widget.points.length) {
      _selectedIndex = null;
    }
  }

  void _handlePointer(Offset localPosition) {
    if (widget.points.isEmpty) return;
    final geometry = _ChartGeometry.compute(
      widget.size,
      widget.points,
      xMode: widget.xMode,
      padding: widget.padding,
    );
    if (geometry.offsets.isEmpty) return;

    // Find the point whose x is closest to the pointer's x.
    int nearest = 0;
    double bestDx = double.infinity;
    for (int i = 0; i < geometry.offsets.length; i++) {
      final dx = (geometry.offsets[i].dx - localPosition.dx).abs();
      if (dx < bestDx) {
        bestDx = dx;
        nearest = i;
      }
    }
    if (nearest != _selectedIndex) {
      setState(() => _selectedIndex = nearest);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _handlePointer(d.localPosition),
      onHorizontalDragStart: widget.enableDragInspect
          ? (d) => _handlePointer(d.localPosition)
          : null,
      onHorizontalDragUpdate: widget.enableDragInspect
          ? (d) => _handlePointer(d.localPosition)
          : null,
      child: CustomPaint(
        size: widget.size,
        painter: _LineChartPainter(
          points: widget.points,
          color: widget.color,
          unit: widget.unit,
          selectedIndex: _selectedIndex,
          xMode: widget.xMode,
          padding: widget.padding,
          showValueLabels: widget.showValueLabels,
        ),
      ),
    );
  }
}

/// The value (y) axis: a "nice" range plus the pixel mapping for it.
///
/// Split out so the full-screen chart's fixed axis strip and its scrolling
/// plot can share one scale and line their ticks up.
class _VerticalScale {
  final double top;
  final double bottom;
  final double min;
  final double max;
  final List<double> ticks;

  const _VerticalScale({
    required this.top,
    required this.bottom,
    required this.min,
    required this.max,
    required this.ticks,
  });

  factory _VerticalScale.forPoints(
    List<ChartPoint> points, {
    required double top,
    required double bottom,
  }) {
    double rawMin = points.isEmpty ? 0 : points.first.value;
    double rawMax = rawMin;
    for (final p in points) {
      rawMin = math.min(rawMin, p.value);
      rawMax = math.max(rawMax, p.value);
    }
    final nice = _niceRange(rawMin, rawMax, 4);
    return _VerticalScale(
      top: top,
      bottom: bottom,
      min: nice.min,
      max: nice.max,
      ticks: nice.ticks,
    );
  }

  double yFor(double value) {
    if (max == min) return (top + bottom) / 2;
    return bottom - (value - min) / (max - min) * (bottom - top);
  }
}

/// Pre-computed pixel geometry for the chart, shared by the painter (drawing)
/// and the widget (hit-testing) so both agree on point positions.
class _ChartGeometry {
  final Rect plot;
  final List<Offset> offsets;
  final _VerticalScale scale;
  final DateTime minDate;
  final DateTime maxDate;

  const _ChartGeometry({
    required this.plot,
    required this.offsets,
    required this.scale,
    required this.minDate,
    required this.maxDate,
  });

  static _ChartGeometry compute(
    Size size,
    List<ChartPoint> points, {
    required _XAxisMode xMode,
    required EdgeInsets padding,
  }) {
    final plot = Rect.fromLTRB(
      padding.left,
      padding.top,
      math.max(padding.left + 1, size.width - padding.right),
      math.max(padding.top + 1, size.height - padding.bottom),
    );

    final scale = _VerticalScale.forPoints(
      points,
      top: plot.top,
      bottom: plot.bottom,
    );

    DateTime minDate = points.first.date;
    DateTime maxDate = points.first.date;
    for (final p in points) {
      if (p.date.isBefore(minDate)) minDate = p.date;
      if (p.date.isAfter(maxDate)) maxDate = p.date;
    }

    final minMs = minDate.millisecondsSinceEpoch;
    final maxMs = maxDate.millisecondsSinceEpoch;

    double xForIndex(int i) {
      if (points.length == 1) return plot.center.dx;
      switch (xMode) {
        case _XAxisMode.time:
          if (maxMs == minMs) return plot.center.dx;
          final t =
              (points[i].date.millisecondsSinceEpoch - minMs) / (maxMs - minMs);
          return plot.left + t * plot.width;
        case _XAxisMode.evenlySpaced:
          return plot.left + i * plot.width / (points.length - 1);
      }
    }

    final offsets = [
      for (int i = 0; i < points.length; i++)
        Offset(xForIndex(i), scale.yFor(points[i].value)),
    ];

    return _ChartGeometry(
      plot: plot,
      offsets: offsets,
      scale: scale,
      minDate: minDate,
      maxDate: maxDate,
    );
  }
}

/// Result of computing a "nice" (human-friendly) axis range.
class _NiceRange {
  final double min;
  final double max;
  final List<double> ticks;

  const _NiceRange(this.min, this.max, this.ticks);
}

_NiceRange _niceRange(double rawMin, double rawMax, int targetSteps) {
  double min = rawMin;
  double max = rawMax;

  if (min == max) {
    final pad = min.abs() < 1e-9 ? 1.0 : min.abs() * 0.1;
    min -= pad;
    max += pad;
  }

  final range = max - min;
  final rawStep = range / targetSteps;
  final magnitude =
      math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final normalized = rawStep / magnitude;

  double niceNormalized;
  if (normalized <= 1) {
    niceNormalized = 1;
  } else if (normalized <= 2) {
    niceNormalized = 2;
  } else if (normalized <= 5) {
    niceNormalized = 5;
  } else {
    niceNormalized = 10;
  }

  final step = niceNormalized * magnitude;
  final niceMin = (min / step).floor() * step;
  final niceMax = (max / step).ceil() * step;

  final ticks = <double>[];
  for (double v = niceMin; v <= niceMax + step * 0.5; v += step) {
    ticks.add(v);
  }

  return _NiceRange(niceMin, niceMax, ticks);
}

const Color _gridColor = Color(0xFFE2E8F0);
const Color _labelColor = Color(0xFF64748B);
const Color _tooltipColor = Color(0xFF1E293B);
const TextStyle _axisLabelStyle = TextStyle(color: _labelColor, fontSize: 10);

class _LineChartPainter extends CustomPainter {
  final List<ChartPoint> points;
  final Color color;
  final String unit;
  final int? selectedIndex;
  final _XAxisMode xMode;
  final EdgeInsets padding;
  final bool showValueLabels;

  _LineChartPainter({
    required this.points,
    required this.color,
    required this.unit,
    required this.selectedIndex,
    required this.xMode,
    required this.padding,
    required this.showValueLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final geo = _ChartGeometry.compute(
      size,
      points,
      xMode: xMode,
      padding: padding,
    );
    _drawGridAndValueLabels(canvas, geo);
    _drawDateLabels(canvas, geo, size);
    if (points.length > 1) {
      _drawAreaAndLine(canvas, geo);
    }
    _drawPoints(canvas, geo);
    _drawSelection(canvas, geo, size);
  }

  void _drawGridAndValueLabels(Canvas canvas, _ChartGeometry geo) {
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;

    for (final tick in geo.scale.ticks) {
      final y = geo.scale.yFor(tick);
      if (y < geo.plot.top - 0.5 || y > geo.plot.bottom + 0.5) continue;

      canvas.drawLine(
        Offset(geo.plot.left, y),
        Offset(geo.plot.right, y),
        gridPaint,
      );

      if (!showValueLabels) continue;
      final label = _layoutText(_formatValue(tick), _axisLabelStyle);
      label.paint(
        canvas,
        Offset(geo.plot.left - 6 - label.width, y - label.height / 2),
      );
    }
  }

  /// Draws the date labels under the plot, newest first, skipping any label
  /// that would collide with an already drawn one. That keeps the axis
  /// readable at any point density instead of overlapping the dates.
  void _drawDateLabels(Canvas canvas, _ChartGeometry geo, Size size) {
    final spansYears = geo.minDate.year != geo.maxDate.year;
    final format = DateFormat(spansYears ? 'd MMM yy' : 'd MMM', 'tr_TR');
    final dy = geo.plot.bottom + 6;

    double? leftmostDrawnEdge;
    for (int i = points.length - 1; i >= 0; i--) {
      final label = _layoutText(format.format(points[i].date), _axisLabelStyle);
      // Centre on the point, but keep the label inside the canvas.
      final maxDx = math.max(0.0, size.width - label.width);
      final dx = (geo.offsets[i].dx - label.width / 2).clamp(0.0, maxDx);
      final right = dx + label.width;

      if (leftmostDrawnEdge != null &&
          right + MeasurementChartConfig.minDateLabelGap > leftmostDrawnEdge) {
        continue;
      }
      label.paint(canvas, Offset(dx, dy));
      leftmostDrawnEdge = dx;
    }
  }

  void _drawAreaAndLine(Canvas canvas, _ChartGeometry geo) {
    final linePath = Path();
    for (int i = 0; i < geo.offsets.length; i++) {
      final o = geo.offsets[i];
      if (i == 0) {
        linePath.moveTo(o.dx, o.dy);
      } else {
        linePath.lineTo(o.dx, o.dy);
      }
    }

    final areaPath = Path.from(linePath)
      ..lineTo(geo.offsets.last.dx, geo.plot.bottom)
      ..lineTo(geo.offsets.first.dx, geo.plot.bottom)
      ..close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(geo.plot);
    canvas.drawPath(areaPath, areaPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);
  }

  void _drawPoints(Canvas canvas, _ChartGeometry geo) {
    final fill = Paint()..color = color;
    final border = Paint()..color = Colors.white;
    // Keep individual dots subtle when there are many points.
    final radius = geo.offsets.length > 20 ? 2.0 : 3.0;
    for (final o in geo.offsets) {
      canvas.drawCircle(o, radius + 1.2, border);
      canvas.drawCircle(o, radius, fill);
    }
  }

  void _drawSelection(Canvas canvas, _ChartGeometry geo, Size size) {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= geo.offsets.length) return;

    final target = geo.offsets[index];

    // Dashed vertical guide line.
    final guidePaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    _drawDashedLine(
      canvas,
      Offset(target.dx, geo.plot.top),
      Offset(target.dx, geo.plot.bottom),
      guidePaint,
    );

    // Highlighted point.
    canvas.drawCircle(target, 6, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(target, 4.5, Paint()..color = Colors.white);
    canvas.drawCircle(target, 3, Paint()..color = color);

    _drawTooltip(canvas, size, target, points[index]);
  }

  void _drawTooltip(
    Canvas canvas,
    Size size,
    Offset target,
    ChartPoint point,
  ) {
    final valueText = '${_formatValue(point.value)} $unit';
    final dateText = DateFormat('d MMM y', 'tr_TR').format(point.date);

    final valuePainter = _layoutText(
      valueText,
      const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
    final datePainter = _layoutText(
      dateText,
      const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10),
    );

    const padH = 8.0;
    const padV = 6.0;
    const gap = 2.0;
    final boxWidth =
        math.max(valuePainter.width, datePainter.width) + padH * 2;
    final boxHeight =
        valuePainter.height + datePainter.height + gap + padV * 2;

    double left = target.dx - boxWidth / 2;
    left = left.clamp(2.0, math.max(2.0, size.width - boxWidth - 2));
    double top = target.dy - boxHeight - 12;
    if (top < 0) top = target.dy + 12;

    final rect = Rect.fromLTWH(left, top, boxWidth, boxHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rrect, Paint()..color = _tooltipColor.withValues(alpha: 0.95));

    valuePainter.paint(canvas, Offset(left + padH, top + padV));
    datePainter.paint(
      canvas,
      Offset(left + padH, top + padV + valuePainter.height + gap),
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 4.0;
    const gapLength = 3.0;
    final totalLength = (end - start).distance;
    if (totalLength == 0) return;
    final direction = (end - start) / totalLength;
    double drawn = 0;
    while (drawn < totalLength) {
      final segmentEnd = math.min(drawn + dashLength, totalLength);
      canvas.drawLine(
        start + direction * drawn,
        start + direction * segmentEnd,
        paint,
      );
      drawn += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) {
    return old.points != points ||
        old.color != color ||
        old.unit != unit ||
        old.selectedIndex != selectedIndex ||
        old.xMode != xMode ||
        old.padding != padding ||
        old.showValueLabels != showValueLabels;
  }
}

TextPainter _layoutText(String text, TextStyle style) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
}

String _formatValue(double v) {
  if ((v - v.roundToDouble()).abs() < 1e-6) return v.round().toString();
  return v.toStringAsFixed(1);
}
