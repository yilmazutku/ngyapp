import 'package:flutter/material.dart';

class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.child});

  static const int maxCount = 99;

  final int count;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > maxCount ? '$maxCount+' : '$count'),
      backgroundColor: Colors.red.shade600,
      textColor: Colors.white,
      child: child,
    );
  }
}
