import 'package:flutter/material.dart';

/// Ortalanmış durum bloğu: yükleniyor / boş liste / hata ekranları için.
///
/// [showProgress] true iken ikon yerine yükleme göstergesi çizilir; [action]
/// verilirse metnin altına (ör. "Yenile") bir buton eklenir.
class StatusNote extends StatelessWidget {
  final IconData? icon;
  final String text;
  final bool isError;
  final bool showProgress;
  final Widget? action;

  const StatusNote({
    super.key,
    this.icon,
    required this.text,
    this.isError = false,
    this.showProgress = false,
    this.action,
  }) : assert(icon != null || showProgress);

  static const double _iconSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final Color color = isError ? Colors.red.shade700 : Colors.grey.shade600;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress)
              const CircularProgressIndicator()
            else
              Icon(icon, size: _iconSize, color: color),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
