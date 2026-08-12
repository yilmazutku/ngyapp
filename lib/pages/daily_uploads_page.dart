import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/meal_model.dart';
import '../providers/meal_state_and_upload_manager.dart';
import '../widgets/meal_image_card.dart';

/// Shows the photos a user uploaded on a specific day, grouped by meal.
///
/// Opened from the "Planım" page. Each meal that has photos is shown as a card
/// (meal type + time + thumbnail); tapping it enlarges the photo(s) and shows
/// the meal type and upload time. View-only.
class DailyUploadsPage extends StatefulWidget {
  final String userId;

  /// The day whose uploads are shown (defaults to "today" from the caller).
  final DateTime date;

  const DailyUploadsPage({
    super.key,
    required this.userId,
    required this.date,
  });

  @override
  State<DailyUploadsPage> createState() => _DailyUploadsPageState();
}

class _DailyUploadsPageState extends State<DailyUploadsPage> {
  static const int _columns = 3;
  static const double _gap = 8.0;
  static const double _cardAspectRatio = 0.85;

  final Logger logger = Logger.forClass(DailyUploadsPage);
  final ScrollController _scrollController = ScrollController();

  Future<List<MealModel>>? _mealsFuture;

  @override
  void initState() {
    super.initState();
    final mealManager = Provider.of<MealManager>(context, listen: false);
    _mealsFuture = mealManager.fetchMeals(
      null,
      userId: widget.userId,
      showAllImages: true,
      date: DateFormat('yyyy-MM-dd').format(widget.date),
    );
    logger.info('DailyUploadsPage initialized. userId={} date={}',
        [widget.userId, DateFormat('yyyy-MM-dd').format(widget.date)]);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMMM y', 'tr_TR').format(widget.date);

    return Scaffold(
      appBar: AppBar(title: const Text('Bugün Yüklediklerim')),
      body: FutureBuilder<List<MealModel>>(
        future: _mealsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            logger.err('DailyUploadsPage load error: {}', [snap.error]);
            return const _Note(
              icon: Icons.error_outline,
              text: 'Fotoğraflar yüklenemedi. Lütfen tekrar deneyin.',
              isError: true,
            );
          }

          // Only meals that actually have uploaded photos, oldest meal first.
          final meals = (snap.data ?? const <MealModel>[])
              .where((m) => m.imageUrls.isNotEmpty)
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

          if (meals.isEmpty) {
            return _Note(
              icon: Icons.photo_library_outlined,
              text: 'Bu gün ($dateStr) için henüz fotoğraf yüklemediniz.',
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    dateStr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cellWidth =
                          (constraints.maxWidth - _gap * (_columns + 1)) /
                              _columns;
                      final double thumbSize = cellWidth.clamp(80.0, 400.0);
                      final double dialogImageHeight =
                          (thumbSize * kMealDialogMultiplier)
                              .clamp(240.0, 480.0);

                      return GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(_gap),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _columns,
                          childAspectRatio: _cardAspectRatio,
                          crossAxisSpacing: _gap,
                          mainAxisSpacing: _gap,
                        ),
                        itemCount: meals.length,
                        itemBuilder: (context, i) => MealImageCard(
                          meal: meals[i],
                          thumbSize: thumbSize,
                          dialogImageHeight: dialogImageHeight,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Centered icon + message for empty / error states.
class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isError;

  const _Note({required this.icon, required this.text, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red.shade700 : Colors.grey.shade600;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}
