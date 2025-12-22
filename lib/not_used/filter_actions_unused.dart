import 'package:flutter/material.dart';

/// A widget that provides standard action buttons for filter sections
class FilterActions extends StatelessWidget {
  /// Callback when the reset button is pressed
  final VoidCallback onReset;

  /// Text to display for the reset button
  final String resetLabel;

  /// Icon to show in the reset button
  final IconData resetIcon;

  /// Additional buttons to include
  final List<Widget>? extraActions;

  /// Alignment for the row of buttons
  final MainAxisAlignment alignment;

  /// Whether any filters are currently active
  final bool filtersActive;

  /// Creates a widget with filter action buttons
  const FilterActions({
    super.key,
    required this.onReset,
    this.resetLabel = 'Filtreleri Sıfırla',
    this.resetIcon = Icons.refresh,
    this.extraActions,
    this.alignment = MainAxisAlignment.end,
    this.filtersActive = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!filtersActive && (extraActions == null || extraActions!.isEmpty)) {
      return const SizedBox
          .shrink(); // Don't show if no filters active and no extra actions
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Row(
        mainAxisAlignment: alignment,
        children: [
          if (filtersActive)
            TextButton.icon(
              onPressed: onReset,
              icon: Icon(resetIcon),
              label: Text(resetLabel),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
            ),
          if (extraActions != null && extraActions!.isNotEmpty) ...[
            if (filtersActive) const SizedBox(width: 8),
            ...extraActions!,
          ],
        ],
      ),
    );
  }
}
