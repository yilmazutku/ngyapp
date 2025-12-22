// lib/widgets/chat_image_preview.dart
import 'package:flutter/material.dart';

/// A reusable widget for displaying image previews in chat/messages/pages.
/// Supports lightweight thumbnail downsampling via cacheWidth/cacheHeight.
class ChatImagePreview extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback? onTap;
  final bool usePlaceholder;

  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;

  // Optional: request smaller decoded image to save memory/bandwidth
  final int? cacheWidth;
  final int? cacheHeight;

  const ChatImagePreview({
    super.key,
    required this.imageUrl,
    this.onTap,
    this.usePlaceholder = false,
    this.width,
    this.height,
    this.borderRadius = 12.0,
    this.cacheWidth,
    this.cacheHeight,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final imageWidth = width ?? screenWidth * 0.55;
    final imageHeight = height ?? screenHeight * 0.25;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: usePlaceholder || imageUrl == null
            ? _placeholder(imageWidth, imageHeight)
            : Image.network(
          imageUrl!,
          width: imageWidth,
          height: imageHeight,
          fit: fit,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          errorBuilder: (context, error, stackTrace) =>
              _error(imageWidth, imageHeight),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _loading(imageWidth, imageHeight, loadingProgress);
          },
        ),
      ),
    );
  }

  Widget _placeholder(double w, double h) => Container(
    width: w,
    height: h,
    color: Colors.grey.shade200,
    alignment: Alignment.center,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image, size: 36, color: Colors.grey.shade600),
        const SizedBox(height: 8),
        Text(
          'Önizleme',
          style: TextStyle(
            color: Colors.grey.shade800,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _error(double w, double h) => Container(
    width: w,
    height: h,
    color: Colors.grey.shade200,
    alignment: Alignment.center,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image, size: 36, color: Colors.grey.shade600),
        const SizedBox(height: 8),
        Text(
          'Görsel Yüklenemedi',
          style: TextStyle(
            color: Colors.grey.shade800,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _loading(
      double w, double h, ImageChunkEvent loadingProgress) =>
      Container(
        width: w,
        height: h,
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: CircularProgressIndicator(
          value: loadingProgress.expectedTotalBytes != null
              ? loadingProgress.cumulativeBytesLoaded /
              loadingProgress.expectedTotalBytes!
              : null,
        ),
      );
}
