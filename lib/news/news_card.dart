import 'package:flutter/material.dart';

import 'news_model.dart';

/// Compact list row for a single news item, shared by the announcements list
/// page and the public blog page. Shows the title (max two lines) and, if the
/// item has an image, a small thumbnail sized to match two lines of the title
/// text so many items fit on the page.
class NewsCard extends StatelessWidget {
  static const double _titleFontSize = 16;
  static const double _titleLineHeight = 1.4;

  /// Thumbnail edge length: exactly as tall as two lines of the title text.
  static const double _thumbSize = _titleFontSize * _titleLineHeight * 2;

  final NewsModel news;
  final VoidCallback onTap;

  const NewsCard({
    super.key,
    required this.news,
    required this.onTap,
  });

  bool get _hasImage => news.imageUrl != null && news.imageUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  news.title,
                  style: const TextStyle(
                    fontSize: _titleFontSize,
                    height: _titleLineHeight,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_hasImage) ...[
                const SizedBox(width: 12),
                _buildThumbnail(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _thumbSize,
        height: _thumbSize,
        child: Image.network(
          news.imageUrl!,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: Colors.grey[200],
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image, size: 20, color: Colors.grey),
            );
          },
        ),
      ),
    );
  }
}
