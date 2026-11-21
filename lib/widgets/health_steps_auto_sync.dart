import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/daily_data_provider.dart';
import '../services/health_steps_sync.dart';

class HealthStepsAutoSync extends StatefulWidget {
  const HealthStepsAutoSync({
    super.key,
    required this.userId,
    required this.child,
    this.sync,
  });

  final String userId;
  final Widget child;
  final HealthStepsSync? sync;

  @override
  State<HealthStepsAutoSync> createState() => _HealthStepsAutoSyncState();
}

class _HealthStepsAutoSyncState extends State<HealthStepsAutoSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  @override
  void didUpdateWidget(HealthStepsAutoSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void _sync() {
    (widget.sync ?? HealthStepsSync.shared).syncIfDue(
      widget.userId,
      Provider.of<DailyDataProvider>(context, listen: false),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
