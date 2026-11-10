import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/services/frame_stats_monitor.dart';
import 'package:ngy_app/widgets/frame_stats_badge.dart';

FrameTiming _timing({required int buildMs, required int rasterMs}) {
  const int start = 1000000;
  final int buildFinish = start + buildMs * 1000;
  final int rasterFinish = buildFinish + rasterMs * 1000;
  return FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: buildFinish,
    rasterStart: buildFinish,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(FrameStatsOverlay.hide);

  test('kare bütçesi tazeleme hızından', () {
    expect(FrameStats.budgetFor(60), const Duration(microseconds: 16667));
    expect(FrameStats.budgetFor(120), const Duration(microseconds: 8333));
    expect(FrameStats.budgetFor(double.nan), const Duration(microseconds: 16667));
    expect(FrameStats.budgetFor(0), const Duration(microseconds: 16667));
  });

  test('takılan ve ağır kareler sayılır', () {
    final FrameStats stats = const FrameStats(budget: Duration(milliseconds: 16))
        .add(const Duration(milliseconds: 5), const Duration(milliseconds: 8))
        .add(const Duration(milliseconds: 20), const Duration(milliseconds: 4))
        .add(const Duration(milliseconds: 3), const Duration(milliseconds: 70));
    expect(stats.frames, 3);
    expect(stats.jankyFrames, 2);
    expect(stats.severeFrames, 1);
    expect(stats.worstBuild, const Duration(milliseconds: 20));
    expect(stats.worstRaster, const Duration(milliseconds: 70));
    expect(stats.jankyPercent, closeTo(66.67, 0.01));
    expect(const FrameStats(budget: Duration(milliseconds: 16)).jankyPercent,
        0);
  });

  test('ölçer motorun kare sürelerini toplar, sıfırlanır ve kapanır', () {
    final FrameStatsMonitor monitor = FrameStatsMonitor.instance;
    expect(monitor.isRunning, isFalse);
    monitor.start();
    expect(monitor.stats.value!.frames, 0);

    SchedulerBinding.instance.platformDispatcher.onReportTimings!([
      _timing(buildMs: 4, rasterMs: 6),
      _timing(buildMs: 40, rasterMs: 6),
    ]);
    expect(monitor.stats.value!.frames, 2);
    expect(monitor.stats.value!.jankyFrames, 1);

    monitor.reset();
    expect(monitor.stats.value!.frames, 0);

    monitor.stop();
    expect(monitor.isRunning, isFalse);
    expect(monitor.stats.value, isNull);
  });

  testWidgets('gösterge sayfalar değişse de en üstte kalır, dokununca sıfırlanır',
      (tester) async {
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('Ana sayfa')),
    ));

    FrameStatsOverlay.show(navigator.currentState!.overlay!);
    await tester.pump();
    expect(FrameStatsOverlay.isShown, isTrue);
    expect(find.textContaining('Kare 0'), findsOneWidget);

    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('İkinci sayfa')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('İkinci sayfa'), findsOneWidget);
    expect(find.textContaining('Kare 0'), findsOneWidget);
    expect(find.byType(FrameStatsBadge).hitTestable(), findsOneWidget);

    SchedulerBinding.instance.platformDispatcher.onReportTimings!([
      _timing(buildMs: 30, rasterMs: 5),
    ]);
    await tester.pump();
    expect(find.textContaining('Kare 1'), findsOneWidget);

    await tester.tap(find.byType(FrameStatsBadge));
    await tester.pump();
    expect(find.textContaining('Kare 0'), findsOneWidget);

    FrameStatsOverlay.hide();
    await tester.pump();
    expect(FrameStatsOverlay.isShown, isFalse);
    expect(find.byType(FrameStatsBadge), findsNothing);
    expect(FrameStatsMonitor.instance.isRunning, isFalse);
  });
}
