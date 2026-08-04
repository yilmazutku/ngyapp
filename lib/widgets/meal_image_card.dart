// lib/widgets/meal_image_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/meal_model.dart';
import 'chat_image_preview.dart';

/// Multiplier from a thumbnail's size to the enlarged detail-dialog image height.
const double kMealDialogMultiplier = 2.8;

/// Meal-type → accent color. Shared so the images tab and the chat photo
/// gallery colour meal cards identically.
Color mealTypeColor(Meals type) {
  switch (type) {
    case Meals.br:
      return Colors.orange;
    case Meals.lunch:
      return Colors.green;
    case Meals.dinner:
      return Colors.indigo;
    case Meals.firstmid:
    case Meals.secondmid:
    case Meals.thirdmid:
      return Colors.purple;
    case Meals.none:
      return Colors.grey;
  }
}

/// Meal-type → icon (shared, see [mealTypeColor]).
IconData mealTypeIcon(Meals type) {
  switch (type) {
    case Meals.br:
      return Icons.breakfast_dining;
    case Meals.lunch:
      return Icons.lunch_dining;
    case Meals.dinner:
      return Icons.dinner_dining;
    case Meals.firstmid:
    case Meals.secondmid:
    case Meals.thirdmid:
      return Icons.restaurant;
    case Meals.none:
      return Icons.image;
  }
}

/// A single meal-image card: a thumbnail with the meal type and time beneath it.
/// Tapping it opens a detail dialog with the enlarged image(s), meal type, and
/// upload date & time (see [showMealImageDetailsDialog]).
///
/// Shared between the images tab and the chat photo gallery so both render meal
/// photos identically (DRY).
class MealImageCard extends StatelessWidget {
  /// The meal to render. In the chat gallery this is adapted from a chat image
  /// message; in the images tab it is a real meal document.
  final MealModel meal;

  /// Logical thumbnail size, used to downsample the decoded image.
  final double thumbSize;

  /// Height of the enlarged image shown in the detail dialog.
  final double dialogImageHeight;

  const MealImageCard({
    super.key,
    required this.meal,
    required this.thumbSize,
    required this.dialogImageHeight,
  });

  // Card metrics (previously the kMealCard* constants in ImagesTab).
  static const double _cardMargin = 4;
  static const double _cardPadding = 6;
  static const double _iconSize = 14;
  static const double _spacing = 4;
  static const double _labelFontSize = 12;
  static const double _timeIconSize = 12;
  static const double _timeFontSize = 11;

  @override
  Widget build(BuildContext context) {
    final Color typeColor = mealTypeColor(meal.mealType);
    final String timeStr = DateFormat('HH:mm').format(meal.timestamp);
    final String heroTag =
        '${meal.imageUrl}_${meal.timestamp.millisecondsSinceEpoch}';
    final int imageCount = meal.imageUrls.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final int cache = (thumbSize * dpr).round();

        return Card(
          elevation: 2,
          margin: const EdgeInsets.all(_cardMargin),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: typeColor.withValues(alpha: 0.5), width: 1),
          ),
          child: InkWell(
            onTap: () => showMealImageDetailsDialog(
              context,
              meal,
              dialogImageHeight: dialogImageHeight,
              heroTag: heroTag,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(_cardPadding),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Hero(
                          tag: heroTag,
                          child: ChatImagePreview(
                            imageUrl: meal.imageUrl,
                            borderRadius: 8,
                            cacheWidth: cache,
                            cacheHeight: cache,
                            fit: BoxFit.cover,
                            onTap: () => showMealImageDetailsDialog(
                              context,
                              meal,
                              dialogImageHeight: dialogImageHeight,
                              heroTag: heroTag,
                            ),
                          ),
                        ),
                        if (imageCount > 1)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.photo_library,
                                      size: 12, color: Colors.white),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$imageCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(_cardPadding),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              mealTypeIcon(meal.mealType),
                              size: _iconSize,
                              color: typeColor,
                            ),
                            const SizedBox(width: _spacing),
                            Flexible(
                              child: Text(
                                meal.mealType.label,
                                style: TextStyle(
                                  fontSize: _labelFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: typeColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: _timeIconSize,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 2),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: _timeFontSize,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shows the enlarged meal detail dialog: the image(s) with pinch-to-zoom, the
/// meal type and upload date & time in the title, and the description if any.
///
/// Normally invoked by tapping a [MealImageCard]; exposed for reuse.
Future<void> showMealImageDetailsDialog(
  BuildContext context,
  MealModel meal, {
  required double dialogImageHeight,
  required String heroTag,
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) {
      const double kDialogMaxWidth = 520;
      final screen = MediaQuery.of(dialogContext).size;
      final double approxBodyWidth =
          (screen.width - 64).clamp(280.0, kDialogMaxWidth);
      final images = meal.imageUrls;

      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(
          '${meal.mealType.label} - ${DateFormat('d MMMM y, HH:mm', 'tr_TR').format(meal.timestamp)}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (images.length == 1)
                  Hero(
                    tag: heroTag,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: approxBodyWidth,
                        height: dialogImageHeight,
                        child: InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: ChatImagePreview(
                            imageUrl: images.first,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (images.isNotEmpty)
                  ...images.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final url = entry.value;
                    return Padding(
                      padding: EdgeInsets.only(
                          bottom: idx < images.length - 1 ? 8.0 : 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: approxBodyWidth,
                          height: dialogImageHeight,
                          child: InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: ChatImagePreview(
                              imageUrl: url,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                if (meal.description != null &&
                    meal.description!.isNotEmpty) ...[
                  const Text(
                    'Açıklama:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(meal.description!),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kapat'),
          ),
        ],
      );
    },
  );
}
