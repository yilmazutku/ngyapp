import 'package:flutter/material.dart';

import '../models/appointment_color_palette.dart';

/// Palet renklerinin yanında gösterilen küçük renk karesi.
class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black26),
      ),
    );
  }
}

/// "Varsayılan" seçeneğiyle birlikte tüm palet renklerini içeren dropdown
/// öğeleri. Rengin seçilebildiği her yer (Ayarlar, Danışanlar Özet) aynı
/// listeyi kullanır; null değer varsayılana dönmek demektir.
///
/// Öğeler [Expanded] içerdiği için dropdown'ın genişliği sınırlı olmalıdır
/// (`isExpanded: true` + genişliği belli bir kutu).
List<DropdownMenuItem<String?>> appointmentColorDropdownItems(
  AppointmentColorOption defaultOption,
) {
  return <DropdownMenuItem<String?>>[
    DropdownMenuItem<String?>(
      value: null,
      child: _colorItemRow(
        defaultOption.color,
        'Varsayılan (${defaultOption.label})',
      ),
    ),
    for (final opt in AppointmentColorPalette.options)
      DropdownMenuItem<String?>(
        value: opt.id,
        child: _colorItemRow(opt.color, opt.label),
      ),
  ];
}

Widget _colorItemRow(Color color, String label) {
  return Row(
    children: [
      PaletteSwatch(color: color, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}
