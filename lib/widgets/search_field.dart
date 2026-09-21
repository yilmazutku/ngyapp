import 'package:flutter/material.dart';

/// Listelerin üstünde kullanılan arama kutusu: soldaki büyüteç, yazı varken
/// beliren temizleme düğmesi ve çerçeveli/dense görünüm.
///
/// Sorguyu sayfa tutar: [controller] dışarıdan verilir ve filtreleme
/// [onChanged] ile yapılır. Temizleme düğmesi kutuyu boşaltıp [onChanged]'i
/// boş metinle çağırır, böylece sayfanın filtresi de sıfırlanır.
class SearchField extends StatelessWidget {
  /// Kutunun varsayılan en fazla genişliği: geniş ekranda satır boyunca
  /// uzamasın diye.
  static const double defaultMaxWidth = 320.0;

  static const String _clearTooltip = 'Aramayı temizle';

  final TextEditingController controller;

  /// Kutunun etiketi; ne aranabileceğini söyler (ör. "Danışan ara (ad soyad /
  /// e-posta)").
  final String label;

  final ValueChanged<String> onChanged;

  /// Kutunun en fazla genişliği. Dar ekranda kutu kendini kısaltır. Genişliği
  /// dışarıdaki yerleşim belirlesin isteniyorsa (ör. `Expanded` içinde)
  /// [double.infinity] verilir.
  final double maxWidth;

  const SearchField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.maxWidth = defaultMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      // Temizleme düğmesi yalnızca yazı varken görünür: kutu kendi değerini
      // dinlediği için sayfanın bunun uğruna yeniden çizilmesi gerekmez.
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          return TextField(
            controller: controller,
            decoration: InputDecoration(
              isDense: true,
              labelText: label,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: _clearTooltip,
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: onChanged,
          );
        },
      ),
    );
  }
}
