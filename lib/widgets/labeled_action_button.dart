import 'package:flutter/material.dart';

/// An action button that always carries a visible label.
///
/// Every toolbar / app-bar action in the app goes through this widget so no
/// action is left as a bare icon the user has to guess at ("Yenile", "Ekle",
/// "Filtrele" and friends read as words, not as pictograms). The tooltip
/// repeats the label, which is what stays reachable when a narrow screen
/// scrolls the label out of view.
class LabeledActionButton extends StatelessWidget {
  const LabeledActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.dense = false,
  });

  final IconData icon;

  /// The words on the button. Also the default tooltip.
  final String label;

  /// Null disables the button, exactly as with any Material button.
  final VoidCallback? onPressed;

  /// Only worth setting when the tooltip should say more than the label does.
  final String? tooltip;

  final Color? backgroundColor;
  final Color? foregroundColor;

  /// Flat, tightly-padded variant for the buttons that live *inside* a list
  /// row (Düzenle / Sil on a card). They still carry their label, but a raised
  /// button per row would push the row wider than a phone screen.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Widget button = dense
        ? TextButton.icon(
            icon: Icon(icon, size: 18),
            label: Text(label, style: const TextStyle(fontSize: 13)),
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: foregroundColor,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          )
        : ElevatedButton.icon(
            icon: Icon(icon, size: 18),
            label: Text(label),
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              // Keeps a row of these from growing taller than the app bar.
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          );

    return Tooltip(
      message: tooltip ?? label,
      preferBelow: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: dense ? 2 : 4),
        child: button,
      ),
    );
  }
}
