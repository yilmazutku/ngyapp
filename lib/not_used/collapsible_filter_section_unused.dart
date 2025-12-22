import 'package:flutter/material.dart';

/// A reusable widget that provides a collapsible filter section with a title
/// and toggle button that shows/hides the filter content.
class CollapsibleFilterSection extends StatelessWidget {
  /// Whether the filter section is currently visible
  final bool isVisible;

  /// Callback when the toggle button is pressed
  final VoidCallback onToggle;

  /// The title widget displayed in the header
  final Widget title;

  /// The filter widgets to display when expanded
  final List<Widget> filterWidgets;

  /// Additional action buttons to show in the header (optional)
  final List<Widget>? headerActions;

  /// Padding around the entire section
  final EdgeInsets padding;

  /// Card elevation
  final double elevation;

  /// Card border radius
  final double borderRadius;

  /// Vertical spacing between filter widgets
  final double verticalSpacing;

  /// Creates a collapsible filter section
  const CollapsibleFilterSection({
    super.key,
    required this.isVisible,
    required this.onToggle,
    required this.title,
    required this.filterWidgets,
    this.headerActions,
    this.padding = const EdgeInsets.all(16.0),
    this.elevation = 4.0,
    this.borderRadius = 12.0,
    this.verticalSpacing = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Card(
        elevation: elevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row with title and toggle button
              Row(
                children: [
                  Expanded(child: title), // Allow title to resize if needed
                  // Optional header actions
                  if (headerActions != null)
                    ...headerActions!.map((widget) => Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: widget,
                        )),
                  // Toggle button for filters
                  IconButton(
                    icon: Icon(
                      isVisible
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Theme.of(context).primaryColor,
                    ),
                    onPressed: onToggle,
                    tooltip:
                        isVisible ? 'Filtreleri Gizle' : 'Filtreleri Göster',
                  ),
                ],
              ),

              // Filter content - only shown when expanded
              if (isVisible) ...[
                const SizedBox(height: 16),
                // Always use vertical layout for filter widgets
                LimitedBox(
                  maxHeight: MediaQuery.of(context).size.height * 0.6, // Limit maximum height to 60% of screen
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: _intersperse(
                        filterWidgets.map((widget) => ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: 0,
                            maxWidth: MediaQuery.of(context).size.width - 64, // Account for padding
                          ),
                          child: widget,
                        )).toList(),
                        SizedBox(height: verticalSpacing),
                      ).toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Helper to intersperse a list with separator widgets
  Iterable<Widget> _intersperse(List<Widget> list, Widget separator) {
    final result = <Widget>[];
    for (int i = 0; i < list.length; i++) {
      result.add(list[i]);
      if (i < list.length - 1) {
        result.add(separator);
      }
    }
    return result;
  }
}
