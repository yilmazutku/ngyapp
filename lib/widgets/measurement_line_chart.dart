import 'dart:math' as math;

import 'package:flutter/material.dart';
// intl also exports a `TextDirection`; hide it so the dart:ui one (used by
// TextPainter) is unambiguous.
import 'package:intl/intl.dart' hide TextDirection;

/// A single data point on a [MeasurementLineChart].
class ChartPoint {
  final DateTime date;
  final double value;

  const ChartPoint(this.date, this.value);
}

/// A lightweight, dependency-free line chart used to visualise a single
/// measurement metric over time (y = value, x = date).
///
/// The widget is self-contained: it computes a "nice" value range, draws
/// grid lines, axis labels and the value line, and lets the user tap/drag
/// across the chart to inspect the value at a given date.
class MeasurementLineChart extends StatefulWidget {
  /// Points to plot. Should be sorted ascending by [ChartPoint.date].
  final List<ChartPoint> points;

  /// Accent colour for the line, fill and highlighted point.
  final Color color;

  /// Unit label shown in the inspection tooltip (e.g. "kg", "cm").
  final String unit;

  /// Fixed drawing height of the chart area.
  final double height;

  const MeasurementLineChart({
    super.key,
    required this.points,
    required this.color,
    required this.unit,
    this.height = 180,
  });

  @override
  State<MeasurementLineChart> createState() => _MeasurementLineChartState();
}

class _MeasurementLineChartState extends State<MeasurementLineChart> {
  int? _selectedIndex;

  void _handlePointer(Offset localPosition, Size size) {
    if (widget.points.isEmpty) return;
    final geometry = _ChartGeometry.compute(size, widget.points);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _handlePointer(d.localPosition, size),
          onHorizontalDragStart: (d) => _handlePointer(d.localPosition, size),
          onHorizontalDragUpdate: (d) => _handlePointer(d.localPosition, size),
          child: CustomPaint(
            size: size,
            painter: _LineChartPainter(
              points: widget.points,
              color: widget.color,
              unit: widget.unit,
              selectedIndex: _selectedIndex,
            ),
          ),
        );
      },
    );
  }
}

/// Pre-computed pixel geometry for the chart, shared by the painter (drawing)
/// and the widget (hit-testing) so both agree on point positions.
class _ChartGeometry {
  final Rect plot;
  final List<Offset> offsets;
  final double minValue;
  final double maxValue;
  final List<double> yTicks;
  final DateTime minDate;
  final DateTime maxDate;

  const _ChartGeometry({
    required this.plot,
    required this.offsets,
    required this.minValue,
    required this.maxValue,
    required this.yTicks,
    required this.minDate,
    required this.maxDate,
  });

  static const double _leftPad = 46;
  static const double _rightPad = 14;
  static const double _topPad = 16;
  static const double _bottomPad = 30;

  static _ChartGeometry compute(Size size, List<ChartPoint> points) {
    final plot = Rect.fromLTRB(
      _leftPad,
      _topPad,
      math.max(_leftPad + 1, size.width - _rightPad),
      math.max(_topPad + 1, size.height - _bottomPad),
    );

    double rawMin = points.first.value;
    double rawMax = points.first.value;
    DateTime minDate = points.first.date;
    DateTime maxDate = points.first.date;
    for (final p in points) {
      rawMin = math.min(rawMin, p.value);
      rawMax = math.max(rawMax, p.value);
      if (p.date.isBefore(minDate)) minDate = p.date;
      if (p.date.isAfter(maxDate)) maxDate = p.date;
    }

    final nice = _niceRange(rawMin, rawMax, 4);

    final minMs = minDate.millisecondsSinceEpoch;
    final maxMs = maxDate.millisecondsSinceEpoch;

    double xForDate(DateTime d) {
      if (maxMs == minMs) return plot.center.dx;
      final t = (d.millisecondsSinceEpoch - minMs) / (maxMs - minMs);
      return plot.left + t * plot.width;
    }

    double yForValue(double v) {
      if (nice.max == nice.min) return plot.center.dy;
      final t = (v - nice.min) / (nice.max - nice.min);
      return plot.bottom - t * plot.height;
    }

    final offsets = points
        .map((p) => Offset(xForDate(p.date), yForValue(p.value)))
        .toList(growable: false);

    return _ChartGeometry(
      plot: plot,
      offsets: offsets,
      minValue: nice.min,
      maxValue: nice.max,
      yTicks: nice.ticks,
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

class _LineChartPainter extends CustomPainter {
  final List<ChartPoint> points;
  final Color color;
  final String unit;
  final int? selectedIndex;

  _LineChartPainter({
    required this.points,
    required this.color,
    required this.unit,
    required this.selectedIndex,
  });

  static const Color _gridColor = Color(0xFFE2E8F0);
  static const Color _labelColor = Color(0xFF64748B);
  static const Color _tooltipColor = Color(0xFF1E293B);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final geo = _ChartGeometry.compute(size, points);
    _drawGridAndYLabels(canvas, geo);
    _drawXLabels(canvas, geo);
    if (points.length > 1) {
      _drawAreaAndLine(canvas, geo);
    }
    _drawPoints(canvas, geo);
    _drawSelection(canvas, geo, size);
  }

  void _drawGridAndYLabels(Canvas canvas, _ChartGeometry geo) {
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;

    for (final tick in geo.yTicks) {
      final y = geo.plot.bottom -
          (geo.maxValue == geo.minValue
              ? 0
              : (tick - geo.minValue) /
                  (geo.maxValue - geo.minValue) *
                  geo.plot.height);
      if (y < geo.plot.top - 0.5 || y > geo.plot.bottom + 0.5) continue;

      canvas.drawLine(
        Offset(geo.plot.left, y),
        Offset(geo.plot.right, y),
        gridPaint,
      );

      _paintText(
        canvas,
        _formatValue(tick),
        Offset(geo.plot.left - 6, y),
        const TextStyle(color: _labelColor, fontSize: 10),
        anchor: _TextAnchor.centerRight,
      );
    }
  }

  void _drawXLabels(Canvas canvas, _ChartGeometry geo) {
    final n = points.length;
    final spansYears = geo.minDate.year != geo.maxDate.year;
    final format = DateFormat(spansYears ? 'd MMM yy' : 'd MMM', 'tr_TR');

    final List<int> indices;
    if (n == 1) {
      indices = [0];
    } else {
      const desired = 4;
      final count = math.min(desired, n);
      final set = <int>{};
      for (int i = 0; i < count; i++) {
        set.add((i * (n - 1) / (count - 1)).round());
      }
      indices = set.toList()..sort();
    }

    for (final i in indices) {
      final dx = geo.offsets[i].dx;
      _paintText(
        canvas,
        format.format(points[i].date),
        Offset(dx, geo.plot.bottom + 6),
        const TextStyle(color: _labelColor, fontSize: 10),
        anchor: _TextAnchor.topCenter,
        minX: 0,
        maxX: geo.plot.right + _ChartGeometry._rightPad,
      );
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

    _drawTooltip(canvas, geo, size, target, points[index]);
  }

  void _drawTooltip(
    Canvas canvas,
    _ChartGeometry geo,
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

  TextPainter _layoutText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter;
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset anchorPoint,
    TextStyle style, {
    required _TextAnchor anchor,
    double? minX,
    double? maxX,
  }) {
    final painter = _layoutText(text, style);
    double dx;
    double dy;
    switch (anchor) {
      case _TextAnchor.centerRight:
        dx = anchorPoint.dx - painter.width;
        dy = anchorPoint.dy - painter.height / 2;
        break;
      case _TextAnchor.topCenter:
        dx = anchorPoint.dx - painter.width / 2;
        dy = anchorPoint.dy;
        break;
    }
    if (minX != null && maxX != null) {
      dx = dx.clamp(minX, math.max(minX, maxX - painter.width));
    }
    painter.paint(canvas, Offset(dx, dy));
  }

  String _formatValue(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-6) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) {
    return old.points != points ||
        old.color != color ||
        old.unit != unit ||
        old.selectedIndex != selectedIndex;
  }
}

enum _TextAnchor { centerRight, topCenter }
