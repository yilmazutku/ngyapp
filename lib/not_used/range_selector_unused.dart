import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A widget for selecting a range of numeric values with a slider
class RangeSelector extends StatelessWidget {
  /// The currently selected range
  final RangeValues values;

  /// Callback when the range changes
  final Function(RangeValues) onChanged;

  /// Minimum possible value
  final double min;

  /// Maximum possible value
  final double max;

  /// Number of divisions on the slider
  final int? divisions;

  /// Title text to display above the slider
  final String title;

  /// Format to use for displaying the values
  final String Function(double)? valueFormat;

  /// Creates a range selector with a slider
  const RangeSelector({
    super.key,
    required this.values,
    required this.onChanged,
    required this.min,
    required this.max,
    this.divisions,
    this.title = 'Range:',
    this.valueFormat,
  });

  /// Factory constructor with currency formatting
  factory RangeSelector.currency({
    Key? key,
    required RangeValues values,
    required Function(RangeValues) onChanged,
    required double min,
    required double max,
    int? divisions,
    String title = 'Tutar Aralığı:',
    String currencySymbol = '₺',
    String locale = 'tr_TR',
  }) {
    final formatter = NumberFormat.currency(
      locale: locale,
      symbol: currencySymbol,
      decimalDigits: 2,
    );

    return RangeSelector(
      key: key,
      values: values,
      onChanged: onChanged,
      min: min,
      max: max,
      divisions: divisions,
      title: title,
      valueFormat: (value) => formatter.format(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatValue = valueFormat ?? (value) => value.toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and current value display
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              '${formatValue(values.start)} - ${formatValue(values.end)}',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),

        // Range slider
        RangeSlider(
          values: values,
          min: min,
          max: max,
          divisions: divisions,
          labels: RangeLabels(
            formatValue(values.start),
            formatValue(values.end),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
