// dekont_viewer_page.dart

import 'package:flutter/material.dart';
import '../widgets/app_bar_with_back.dart';

class DekontViewerPage extends StatelessWidget {
  final String dekontUrl;

  const DekontViewerPage({super.key, required this.dekontUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWithBack(
        title: 'Dekont Görüntüleyici',
      ),
      body: Center(
        child: Image.network(
          dekontUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const CircularProgressIndicator();
          },
          errorBuilder: (context, error, stackTrace) {
            return const Text('Error loading image.');
          },
        ),
      ),
    );
  }
}
