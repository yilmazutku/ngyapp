import 'dart:ui' show Display, FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class FrameStats {
  static const int severeBudgetMultiplier = 4;

  final Duration budget;
  final int frames;
  final int jankyFrames;
  final int severeFrames;
  final Duration worstBuild;
  final Duration worstRaster;

  const FrameStats({
    required this.budget,
    this.frames = 0,
    this.jankyFrames = 0,
    this.severeFrames = 0,
    this.worstBuild = Duration.zero,
    this.worstRaster = Duration.zero,
  });

  double get jankyPercent => frames == 0 ? 0 : jankyFrames * 100 / frames;

  FrameStats add(Duration build, Duration raster) {
    final Duration slowest = build > raster ? build : raster;
    return FrameStats(
      budget: budget,
      frames: frames + 1,
      jankyFrames: jankyFrames + (slowest > budget ? 1 : 0),
      severeFrames: severeFrames +
          (slowest > budget * severeBudgetMultiplier ? 1 : 0),
      worstBuild: build > worstBuild ? build : worstBuild,
      worstRaster: raster > worstRaster ? raster : worstRaster,
    );
  }

  static Duration budgetFor(double refreshRate) {
    final double rate =
        refreshRate.isFinite && refreshRate >= 30 ? refreshRate : 60;
    return Duration(microseconds: (Duration.microsecondsPerSecond / rate)
        .round());
  }
}

class FrameStatsMonitor {
  FrameStatsMonitor._();

  static final FrameStatsMonitor instance = FrameStatsMonitor._();

  final ValueNotifier<FrameStats?> stats = ValueNotifier<FrameStats?>(null);

  bool get isRunning => stats.value != null;

  void start() {
    if (isRunning) return;
    stats.value = FrameStats(budget: _currentBudget());
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!isRunning) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    stats.value = null;
  }

  void reset() {
    if (!isRunning) return;
    stats.value = FrameStats(budget: _currentBudget());
  }

  void _onTimings(List<FrameTiming> timings) {
    final FrameStats? current = stats.value;
    if (current == null) return;
    FrameStats next = current;
    for (final FrameTiming timing in timings) {
      next = next.add(timing.buildDuration, timing.rasterDuration);
    }
    stats.value = next;
  }

  static Duration _currentBudget() {
    final Iterable<Display> displays = PlatformDispatcher.instance.displays;
    return FrameStats.budgetFor(
        displays.isEmpty ? 60 : displays.first.refreshRate);
  }
}
