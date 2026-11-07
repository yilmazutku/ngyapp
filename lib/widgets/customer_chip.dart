import 'package:flutter/material.dart';

class CustomerChip extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const CustomerChip({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(Icons.person_outline_rounded,
          size: 16, color: Colors.deepPurple.shade400),
      label: Text(label),
      labelStyle: const TextStyle(fontSize: 12.5),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.deepPurple.shade100),
      tooltip: 'Danışanı aç',
      onPressed: onPressed,
    );
  }
}
