import 'package:flutter/material.dart';

/// A reusable card widget for displaying data items in lists
class DataCard extends StatelessWidget {
  /// The child widget(s) to display inside the card
  final Widget child;

  /// Margin around the card
  final EdgeInsets margin;

  /// Padding inside the card
  final EdgeInsets padding;

  /// Card elevation
  final double elevation;

  /// Card border radius
  final double borderRadius;

  /// Whether the card is interactable (adds ripple effect)
  final bool interactable;

  /// Callback when the card is tapped (if interactable)
  final VoidCallback? onTap;

  /// Optional background color (defaults to card theme)
  final Color? backgroundColor;

  /// Optional border color
  final Color? borderColor;

  /// Optional border width
  final double borderWidth;

  /// Creates a styled card with consistent appearance
  const DataCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.padding = const EdgeInsets.all(16),
    this.elevation = 2,
    this.borderRadius = 12,
    this.interactable = true,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: margin,
      elevation: elevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: borderColor != null
            ? BorderSide(color: borderColor!, width: borderWidth)
            : BorderSide.none,
      ),
      color: backgroundColor,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (!interactable) {
      return card;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius),
      child: card,
    );
  }
}

/// A card with standardized sections for displaying items with title, subtitle and actions
class InfoCard extends StatelessWidget {
  /// The title text or widget
  final Widget title;

  /// Optional subtitle text or widget
  final Widget? subtitle;

  /// Optional content to display below the title/subtitle
  final Widget? content;

  /// Optional leading widget (like an icon or avatar)
  final Widget? leading;

  /// Optional trailing widget (like action buttons)
  final Widget? trailing;

  /// Optional additional widgets to display at the bottom of the card
  final List<Widget>? actions;

  /// Space between sections
  final double sectionSpacing;

  /// Other card properties
  final EdgeInsets margin;
  final EdgeInsets padding;
  final double elevation;
  final double borderRadius;
  final bool interactable;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;

  /// Creates a styled info card with title, subtitle, and optional sections
  const InfoCard({
    super.key,
    required this.title,
    this.subtitle,
    this.content,
    this.leading,
    this.trailing,
    this.actions,
    this.sectionSpacing = 8.0,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.padding = const EdgeInsets.all(16),
    this.elevation = 2,
    this.borderRadius = 12,
    this.interactable = true,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return DataCard(
      margin: margin,
      padding: padding,
      elevation: elevation,
      borderRadius: borderRadius,
      interactable: interactable,
      onTap: onTap,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with title and optional trailing widget
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                SizedBox(width: sectionSpacing),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      SizedBox(height: sectionSpacing / 2),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),

          // Optional content
          if (content != null) ...[
            SizedBox(height: sectionSpacing),
            content!,
          ],

          // Optional actions
          if (actions != null && actions!.isNotEmpty) ...[
            SizedBox(height: sectionSpacing),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions!.map((action) {
                final index = actions!.indexOf(action);
                return Padding(
                  padding: EdgeInsets.only(
                    left: index > 0 ? sectionSpacing : 0,
                  ),
                  child: action,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
