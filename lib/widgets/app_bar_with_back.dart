import 'package:flutter/material.dart';

/// A reusable AppBar with back navigation button
class AppBarWithBack extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final PreferredSizeWidget? bottom;
  final String? backButtonTooltip;
  final VoidCallback? onBackPressed;
  final double elevation;
  final bool centerTitle;

  const AppBarWithBack({
    super.key,
    required this.title,
    this.actions,
    this.backgroundColor,
    this.foregroundColor,
    this.bottom,
    this.backButtonTooltip = 'Geri',
    this.onBackPressed,
    this.elevation = 4.0,
    this.centerTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    // Cap how much horizontal space actions can take; rest belongs to the title.
    final double maxActionsWidth = MediaQuery.of(context).size.width * 0.46;

    // Wrap all actions into a single scrollable slot to avoid overflow.
    final List<Widget>? resolvedActions = (actions == null || actions!.isEmpty)
        ? actions
        : <Widget>[
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxActionsWidth),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true, // keep the rightmost actions visible first
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: actions!,
          ),
        ),
      ),
    ];

    return AppBar(
      // Tighter spacing gives the title a bit more room
      titleSpacing: 0,
      leadingWidth: 48,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: backButtonTooltip,
        onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
      ),
      actions: resolvedActions,
      backgroundColor: Color(0xFF6642E5), //backgroundColor
      foregroundColor: Colors.white, //foregroundColor
      bottom: bottom,
      elevation: elevation,
      centerTitle: centerTitle,
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}
