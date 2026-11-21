// lib/widgets/meal_image_card.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/meal_model.dart';
import '../providers/meal_state_and_upload_manager.dart';
import 'meal_thumbnail_image.dart';
import 'reaction_badge.dart';

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

  /// Height of the enlarged image shown in the detail dialog.
  final double dialogImageHeight;

  /// Fotoğrafın sahibi. Verilirse ve fotoğrafın küçük görseli yoksa, orijinal
  /// bir kez indirildiğinde küçük görsel üretilip kaydedilir
  /// ([MealManager.backfillThumbnail]); sonraki açılışlarda tam boy indirme
  /// gerekmez. Sohbet galerisi gibi öğün kaydı olmayan yerlerde verilmez.
  final String? backfillUserId;

  /// Fotoğrafın sohbetteki mesajına bırakılan tepkiler (uid -> emoji). Boş
  /// değilse küçük görselin köşesinde rozet olarak görünür; sohbetteki
  /// rozetle aynı toplamayı kullanır (bkz. [reactionCountsOf]). Tepki
  /// gösterilmeyen ekranlarda verilmez.
  final Map<String, String> reactions;

  /// Verilirse karta dokununca varsayılan ayrıntı diyaloğu yerine bu
  /// çağrılır: sayfa aynı diyaloğu ([showMealImageDetailsDialog]) kendi
  /// alt satırıyla (ör. "Sohbette göster") açar.
  final VoidCallback? onTap;

  /// Kart vurgulu mu (ör. sohbetten "Öğün Fotoğrafları'nda göster" ile bu
  /// fotoğrafa gelindi).
  final bool highlighted;

  final void Function(Offset globalPosition)? onMenu;

  const MealImageCard({
    super.key,
    required this.meal,
    required this.dialogImageHeight,
    this.backfillUserId,
    this.reactions = const {},
    this.onTap,
    this.highlighted = false,
    this.onMenu,
  });

  // Card metrics (previously the kMealCard* constants in ImagesTab).
  static const double _cardMargin = 4;
  static const double _cardPadding = 6;
  static const double _iconSize = 14;
  static const double _spacing = 4;
  static const double _labelFontSize = 12;
  static const double _timeIconSize = 12;
  static const double _timeFontSize = 11;
  static const double _timeIconGap = 2;
  static const double _highlightBorderWidth = 3;

  /// Kartın ve ayrıntı diyaloğunun ortak Hero etiketi (büyütme animasyonu).
  static String heroTagFor(MealModel meal) =>
      '${meal.imageUrl}_${meal.timestamp.millisecondsSinceEpoch}';

  static WidgetSpan _iconSpan(
          IconData icon, double size, Color? color, double gap) =>
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: EdgeInsets.only(right: gap),
          child: Icon(icon, size: size, color: color),
        ),
      );

  /// Orijinal indirildiğinde küçük görseli üretip kaydeden geri çağrı.
  /// Sağlayıcı build sırasında alınır; geri çağrı sonradan, context'e
  /// dokunmadan çalışır.
  OriginalBytesCallback _backfillCallback(
      MealManager mealManager, String userId) {
    return (Uint8List bytes) => mealManager.backfillThumbnail(
          userId: userId,
          meal: meal.mealType,
          date: meal.timestamp,
          imageUrl: meal.imageUrl,
          originalBytes: bytes,
        );
  }

  @override
  Widget build(BuildContext context) {
    final Color typeColor = mealTypeColor(meal.mealType);
    final String timeStr = DateFormat('HH:mm').format(meal.timestamp);
    final String heroTag = heroTagFor(meal);
    final int imageCount = meal.imageUrls.length;

    // Küçük görsel varsa yalnızca o indirilir; yoksa orijinal indirilir,
    // çözülürken küçültülür ve (sahibi biliniyorsa) küçük görsel bir kez
    // üretilip kaydedilir.
    final String? thumbUrl = meal.thumbUrlAt(0);
    final String? backfillUserId = this.backfillUserId;
    final OriginalBytesCallback? onOriginalLoaded =
        (thumbUrl == null && backfillUserId != null && meal.imageUrl.isNotEmpty)
            ? _backfillCallback(
                Provider.of<MealManager>(context, listen: false),
                backfillUserId,
              )
            : null;

    final Widget card = Card(
      elevation: 2,
      margin: const EdgeInsets.all(_cardMargin),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: highlighted
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: _highlightBorderWidth,
              )
            : BorderSide(color: typeColor.withValues(alpha: 0.5), width: 1),
      ),
      child: InkWell(
        onTap: onTap ??
            () => showMealImageDetailsDialog(
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
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: MealThumbnailImage(
                          url: thumbUrl ?? meal.imageUrl,
                          isOriginal: thumbUrl == null,
                          onOriginalLoaded: onOriginalLoaded,
                        ),
                      ),
                    ),
                    if (reactions.isNotEmpty)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: _MealReactionBadge(reactions: reactions),
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
              // Önce saat yerleşir, öğün adı kalan yere sığdığı kadar yazılır.
              // İkisi de tek satırlık metin (ikon metnin içinde): çok dar
              // kartta kısalır, satır taşmaz.
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          _iconSpan(
                            mealTypeIcon(meal.mealType),
                            _iconSize,
                            typeColor,
                            _spacing,
                          ),
                          TextSpan(text: meal.mealType.displayLabel),
                        ]),
                        style: TextStyle(
                          fontSize: _labelFontSize,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth),
                      child: Text.rich(
                        TextSpan(children: [
                          _iconSpan(
                            Icons.access_time,
                            _timeIconSize,
                            Colors.grey[600],
                            _timeIconGap,
                          ),
                          TextSpan(text: timeStr),
                        ]),
                        style: TextStyle(
                          fontSize: _timeFontSize,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final void Function(Offset globalPosition)? onMenu = this.onMenu;
    if (onMenu == null) return card;
    return GestureDetector(
      onSecondaryTapDown: (details) => onMenu(details.globalPosition),
      onLongPressStart: (details) => onMenu(details.globalPosition),
      child: card,
    );
  }
}

/// Küçük görselin köşesindeki tepki rozeti: fotoğrafın sohbetteki mesajına
/// bırakılan ifadeler. Aynı emojiler tek rozette toplanır, birden fazla kişi
/// bıraktıysa sayısı yazılır. Fotoğrafın üstünde durduğu için sohbetteki açık
/// rozet yerine, kartın fotoğraf sayısı rozetiyle aynı koyu zemin kullanılır.
class _MealReactionBadge extends StatelessWidget {
  final Map<String, String> reactions;

  const _MealReactionBadge({required this.reactions});

  static const double _emojiSize = 18;
  static const double _countSize = 16.5;

  @override
  Widget build(BuildContext context) {
    final Map<String, int> counts = reactionCountsOf(reactions);
    if (counts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry<String, int> entry in counts.entries) ...[
            Text(entry.key, style: const TextStyle(fontSize: _emojiSize)),
            if (entry.value > 1)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text(
                  '${entry.value}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: _countSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

typedef MealDetailsFooterBuilder = Widget Function(
  BuildContext dialogContext,
  MealModel meal,
);

/// Shows the enlarged meal detail dialog: the image(s) with pinch-to-zoom, the
/// meal type and upload date & time in the title, and the description if any.
///
/// Normally invoked by tapping a [MealImageCard]; exposed for reuse.
/// [footerBuilder] verilirse görselin altında sayfaya özel bir satır çıkar
/// (ör. Öğün Fotoğrafları'nda hızlı ifadeler ve "Sohbette göster"); satır
/// diyaloğu bir değerle kapatabilir, o değer döner.
Future<T?> showMealImageDetailsDialog<T>(
  BuildContext context,
  MealModel meal, {
  required double dialogImageHeight,
  required String heroTag,
  MealDetailsFooterBuilder? footerBuilder,
  List<MealModel> gallery = const [],
}) {
  final int index = gallery.indexOf(meal);
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => _MealImageDetailsDialog(
      meals: index < 0 ? <MealModel>[meal] : gallery,
      initialIndex: index < 0 ? 0 : index,
      dialogImageHeight: dialogImageHeight,
      heroTag: heroTag,
      footerBuilder: footerBuilder,
    ),
  );
}

class _MealImageDetailsDialog extends StatefulWidget {
  final List<MealModel> meals;
  final int initialIndex;
  final double dialogImageHeight;
  final String heroTag;
  final MealDetailsFooterBuilder? footerBuilder;

  const _MealImageDetailsDialog({
    required this.meals,
    required this.initialIndex,
    required this.dialogImageHeight,
    required this.heroTag,
    required this.footerBuilder,
  });

  @override
  State<_MealImageDetailsDialog> createState() =>
      _MealImageDetailsDialogState();
}

class _MealImageDetailsDialogState extends State<_MealImageDetailsDialog> {
  static const double _maxWidth = 520;
  static const double _imageGap = 8;
  static const double _sectionGap = 16;
  static const double _navGap = 8;
  static const String _previousTooltip = 'Önceki fotoğraf';
  static const String _nextTooltip = 'Sonraki fotoğraf';
  static const String _descriptionLabel = 'Açıklama:';
  static const String _closeLabel = 'Kapat';

  late int _index = widget.initialIndex;

  bool get _browsable => widget.meals.length > 1;
  bool get _hasPrevious => _index > 0;
  bool get _hasNext => _index < widget.meals.length - 1;

  void _showPrevious() {
    if (_hasPrevious) setState(() => _index--);
  }

  void _showNext() {
    if (_hasNext) setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final MealModel meal = widget.meals[_index];
    final double imageWidth =
        (MediaQuery.sizeOf(context).width - 64).clamp(280.0, _maxWidth);
    final MealDetailsFooterBuilder? footerBuilder = widget.footerBuilder;
    final String? description = meal.description;

    final Widget dialog = AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        '${meal.mealType.displayLabel} - ${DateFormat('d MMMM y, HH:mm', 'tr_TR').format(meal.timestamp)}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._buildImages(meal, imageWidth),
              if (_browsable) ...[
                const SizedBox(height: _navGap),
                _buildNavigation(context),
              ],
              const SizedBox(height: _sectionGap),
              if (footerBuilder != null) ...[
                KeyedSubtree(
                  key: ObjectKey(meal),
                  child: footerBuilder(context, meal),
                ),
                const SizedBox(height: _sectionGap),
              ],
              if (description != null && description.isNotEmpty) ...[
                const Text(
                  _descriptionLabel,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(description),
                const SizedBox(height: _sectionGap),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(_closeLabel),
        ),
      ],
    );

    if (!_browsable) return dialog;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _showPrevious,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _showNext,
      },
      child: Focus(autofocus: true, child: dialog),
    );
  }

  List<Widget> _buildImages(MealModel meal, double width) {
    final List<String> images = meal.imageUrls;
    return [
      for (int i = 0; i < images.length; i++)
        Padding(
          key: ValueKey<(MealModel, int)>((meal, i)),
          padding:
              EdgeInsets.only(bottom: i < images.length - 1 ? _imageGap : 0),
          child: _withHero(
            images.length == 1 && _index == widget.initialIndex,
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: width,
                height: widget.dialogImageHeight,
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: MealOriginalImage(
                    url: images[i],
                    thumbUrl: meal.thumbUrlAt(i),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _withHero(bool hero, Widget child) =>
      hero ? Hero(tag: widget.heroTag, child: child) : child;

  Widget _buildNavigation(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: _previousTooltip,
          icon: const Icon(Icons.chevron_left),
          onPressed: _hasPrevious ? _showPrevious : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _sectionGap),
          child: Text(
            '${_index + 1} / ${widget.meals.length}',
            style: theme.textTheme.titleSmall,
          ),
        ),
        IconButton.filledTonal(
          tooltip: _nextTooltip,
          icon: const Icon(Icons.chevron_right),
          onPressed: _hasNext ? _showNext : null,
        ),
      ],
    );
  }
}
