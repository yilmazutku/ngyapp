import 'package:flutter/material.dart';

/// A widget that displays a group of filter chips with a consistent style and appearance
class FilterChipGroup<T> extends StatelessWidget {
  /// Title text to display above the chips
  final String title;

  /// The currently selected value
  final T? selectedValue;

  /// Callback when a chip is selected
  final Function(T?) onSelected;

  /// Map of values to their display labels
  final Map<T, String> options;

  /// Label for the "all" option
  final String allLabel;

  /// Whether to show the "All" option chip
  final bool showAllOption;

  /// Icon to show before the title (optional)
  final IconData? titleIcon;

  /// Whether to use a horizontal scrolling layout
  final bool horizontalScroll;

  /// Background color for unselected chips
  final Color? backgroundColor;

  /// Color for selected chips
  final Color? selectedColor;

  /// Creates a group of filter chips with a title
  const FilterChipGroup({
    super.key,
    required this.title,
    required this.selectedValue,
    required this.onSelected,
    required this.options,
    this.allLabel = 'Tümü',
    this.showAllOption = true,
    this.titleIcon,
    this.horizontalScroll = true,
    this.backgroundColor,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? Colors.grey[200];
    final selColor = selectedColor ?? theme.primaryColor.withOpacity(0.15);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row
        Row(
          children: [
            if (titleIcon != null) ...[
              Icon(titleIcon, size: 16, color: Colors.grey[700]),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Filter chips
        if (horizontalScroll)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _buildChips(bgColor, selColor),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buildChips(bgColor, selColor),
          ),
      ],
    );
  }

  List<Widget> _buildChips(Color? bgColor, Color? selColor) {
    final result = <Widget>[];

    // "All" option
    if (showAllOption) {
      result.add(
        FilterChip(
          label: Text(allLabel),
          selected: selectedValue == null,
          onSelected: (selected) {
            if (selected) {
              onSelected(null);
            }
          },
          backgroundColor: bgColor,
          selectedColor: selColor,
        ),
      );

      // Add spacing after the "All" chip
      result.add(const SizedBox(width: 8));
    }

    // Add all option chips
    for (final entry in options.entries) {
      result.add(
        FilterChip(
          label: Text(entry.value),
          selected: selectedValue == entry.key,
          onSelected: (selected) {
            onSelected(selected ? entry.key : null);
          },
          backgroundColor: bgColor,
          selectedColor: selColor,
        ),
      );

      // Add spacing between chips
      result.add(const SizedBox(width: 8));
    }

    return result;
  }
}
