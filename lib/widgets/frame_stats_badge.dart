import 'package:flutter/material.dart';

import '../services/frame_stats_monitor.dart';

class FrameStatsOverlay {
  FrameStatsOverlay._();

  static const double _margin = 8;

  static OverlayEntry? _entry;

  static bool get isShown => _entry != null;

  static void show(OverlayState overlay) {
    if (_entry != null) return;
    FrameStatsMonitor.instance.start();
    final OverlayEntry entry = OverlayEntry(
      builder: (context) => const Positioned(
        left: _margin,
        bottom: _margin,
        child: SafeArea(child: FrameStatsBadge()),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
    FrameStatsMonitor.instance.stop();
  }
}

class FrameStatsBadge extends StatelessWidget {
  const FrameStatsBadge({super.key});

  static const String _resetHint = 'Sıfırlamak için dokunun';
  static const double _fontSize = 11;
  static const double _radius = 8;
  static const double _maxWidthRatio = 0.9;

  static String _ms(Duration duration) =>
      (duration.inMicroseconds / Duration.microsecondsPerMillisecond)
          .toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FrameStats?>(
      valueListenable: FrameStatsMonitor.instance.stats,
      builder: (context, stats, _) {
        if (stats == null) return const SizedBox.shrink();
        final Color headline = stats.severeFrames > 0
            ? Colors.redAccent.shade100
            : stats.jankyFrames > 0
                ? Colors.amberAccent
                : Colors.lightGreenAccent;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * _maxWidthRatio,
          ),
          child: Material(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(_radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(_radius),
              onTap: FrameStatsMonitor.instance.reset,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: _fontSize,
                    height: 1.35,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kare ${stats.frames} · takılan ${stats.jankyFrames} '
                        '(%${stats.jankyPercent.toStringAsFixed(1)}) · '
                        'ağır ${stats.severeFrames}',
                        style: TextStyle(
                          color: headline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'En uzun: çizim ${_ms(stats.worstBuild)} ms · '
                        'raster ${_ms(stats.worstRaster)} ms · '
                        'bütçe ${_ms(stats.budget)} ms',
                      ),
                      const Text(
                        _resetHint,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
