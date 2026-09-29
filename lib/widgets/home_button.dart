import 'package:flutter/material.dart';

import 'labeled_action_button.dart';

class HomeButton extends StatelessWidget {
  const HomeButton({super.key});

  static const String label = 'Ana Sayfa';

  @override
  Widget build(BuildContext context) {
    return LabeledActionButton(
      icon: Icons.home,
      label: label,
      onPressed: () => Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst),
    );
  }
}
