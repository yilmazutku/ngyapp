// lib/pages/user_media_gallery_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/user_photo_gallery_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/utils/menu_utils.dart';
import 'package:ngy_app/widgets/chat/history_edge.dart';
import 'package:ngy_app/widgets/chat/message_actions_sheet.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';

/// Full-page gallery of the photos a specific user has uploaded **in the chat**.
///
/// Opened from the chat screen by tapping the title in the app bar: the admin
/// taps the user's name, the user taps the dietitian's name and sees their own
/// photos. Unlike the images tab (which also shows meal photos uploaded
/// elsewhere), this shows ONLY chat-uploaded photos.
///
/// Architecture:
/// - Source: [UserPhotoGalleryProvider] (messages the user sent with an
///   image). chatId == userId, so this is exactly the user's photos. Son
///   mesajlardaki fotoğraflar canlı dinlenir; ızgara en üste yaklaştıkça eski
///   sayfalar yüklenir (sohbet sayfasındaki düzen), bütün mesajlar bir kerede
///   okunmaz. Üstteki sayı yalnızca yüklenenlerin değil, fotoğrafların
///   toplamıdır ([UserPhotoGalleryProvider.totalCount]).
/// - Each chat image is adapted to a [MealModel] and rendered with the shared
///   [MealImageCard] so the layout matches the images tab (tap to enlarge with
///   meal type + upload date & time). Sütun sayısı genişliğe göre değişir:
///   telefonda 3, geniş ekranda 5 (bkz. [UserMediaGalleryGrid]).
/// - Sorted oldest→newest so the most recent photo sits at the very bottom;
///   galeri en yeni fotoğraftan açılır.
/// - Bir fotoğrafa dokununca büyük görsel diyaloğu açılır; altındaki
///   "Sohbette göster" sayfayı fotoğrafın mesaj kimliğiyle kapatır, sohbet o
///   mesaja gider. Danışan kendi galerisinde yanındaki "Fotoğrafı Sil" ile
///   fotoğrafı silebilir (uzun basınca açılan menüdeki gibi).
class UserMediaGalleryPage extends StatefulWidget {
  /// The user whose chat-uploaded photos are shown (chatId == userId).
  final String userId;

  final Future<void> Function(MessageData message)? onDeletePhoto;

  const UserMediaGalleryPage({
    super.key,
    required this.userId,
    this.onDeletePhoto,
  });

  @override
  State<UserMediaGalleryPage> createState() => _UserMediaGalleryPageState();
}

class _UserMediaGalleryPageState extends State<UserMediaGalleryPage> {
  static const String _titleFallback = 'Fotoğraflar';
  static const String _ownTitle = 'Fotoğraflarım';
  static const String _emptyText = 'Bu kişi sohbette henüz fotoğraf yüklemedi.';
  static const String _ownEmptyText = 'Sohbette henüz fotoğraf yüklemediniz.';
  static const String _goToChatLabel = 'Sohbette göster';
  static const String _loadErrorText =
      'Fotoğraflar yüklenemedi. Lütfen tekrar deneyin.';
  static const String _olderLoadErrorText = 'Eski fotoğraflar yüklenemedi.';
  static const String _olderOfflineText =
      'Bağlantı yok; eski fotoğraflar yüklenemedi.';
  static const String _retryLabel = 'Tekrar dene';
  static const String _countSuffix = 'fotoğraf';

  /// Büyük görsel diyaloğundaki düğmelerin arası.
  static const double _footerButtonGap = 8;

  /// Owns the grid scroll position so the [Scrollbar] can attach to it
  /// (shared-controller rule).
  final ScrollController _scrollController = ScrollController();

  late final UserPhotoGalleryProvider _gallery;

  /// One-shot fetch of the user's profile for the app bar title.
  Future<UserModel?>? _userFuture;

  late final bool _isOwnGallery;

  bool _opened = false;

  bool _complete = false;

  bool _layoutPending = false;

  @override
  void initState() {
    super.initState();
    final chat = Provider.of<ChatManager>(context, listen: false);
    _gallery = UserPhotoGalleryProvider(chat: chat, userId: widget.userId)
      ..addListener(_onGalleryChanged)
      ..start();
    _isOwnGallery = chat.auth.currentUser?.uid == widget.userId;
    if (!_isOwnGallery) {
      _userFuture = Provider.of<UserProvider>(context, listen: false)
          .fetchUserDetails(userId: widget.userId);
    }
  }

  @override
  void dispose() {
    _gallery
      ..removeListener(_onGalleryChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onGalleryChanged() {
    if (!_opened && !_gallery.isLoading && !_gallery.hasFailed) {
      _opened = true;
      _complete = _gallery.atStart;
    }
    _layoutPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutPending = false;
      if (!mounted) return;
      _showCompleteIfWholeGalleryFits();
      _loadOlderIfNearOldest();
    });
  }

  ScrollPosition? get _gridPosition {
    if (!_scrollController.hasClients) return null;
    final ScrollPosition position = _scrollController.position;
    return position.hasContentDimensions ? position : null;
  }

  void _showCompleteIfWholeGalleryFits() {
    final ScrollPosition? position = _gridPosition;
    if (_complete ||
        !_gallery.atStart ||
        position == null ||
        position.maxScrollExtent > 0) {
      return;
    }
    setState(() => _complete = true);
  }

  void _loadOlderIfNearOldest() {
    final ScrollPosition? position = _gridPosition;
    if (_layoutPending || position == null) return;
    if (position.maxScrollExtent - position.pixels <=
        UserMediaGalleryGrid.loadOlderThreshold) {
      _gallery.loadOlder();
    }
  }

  String _countLabel(int loaded) {
    final int? total = _gallery.totalCount;
    if (total != null) return '$total $_countSuffix';
    return _gallery.totalCountUnavailable ? '$loaded+ $_countSuffix' : '';
  }

  String get _olderErrorText =>
      _gallery.olderOffline ? _olderOfflineText : _olderLoadErrorText;

  Widget? _buildTopEdge() {
    if (_gallery.isLoadingOlder) return const HistoryEdge.loading();
    if (_gallery.olderLoadFailed) {
      return HistoryEdge.retry(
        text: '$_olderErrorText $_retryLabel',
        onRetry: _gallery.retryOlder,
      );
    }
    return null;
  }

  /// Derive the meal type of a chat-uploaded photo (see
  /// [MessageData.photoMeal]); anything else falls back to [Meals.none].
  Meals _mealTypeOf(MessageData m) => m.photoMeal ?? Meals.none;

  /// Adapt a chat image message to a [MealModel] so the shared [MealImageCard]
  /// can render it exactly like the images tab.
  MealModel _toMeal(MessageData m) {
    final ts = m.sentAt ?? DateTime.now();
    final url = m.imageUrl ?? '';
    return MealModel(
      mealId: m.id,
      mealType: _mealTypeOf(m),
      imageUrls: url.isEmpty ? const <String>[] : <String>[url],
      // Kart küçük görseli indirir (varsa).
      thumbUrls: <String>[m.thumbUrl ?? ''],
      timestamp: ts,
      isChecked: true,
    );
  }

  /// Fotoğraf bu galeriden silinebilir mi: yalnızca danışanın kendi öğün
  /// fotoğrafı (silme işlevi yalnızca ona verilir).
  bool _canDelete(MessageData message) =>
      widget.onDeletePhoto != null && message.isMealPhoto;

  /// Fotoğrafın büyük görsel diyaloğunu açar. "Sohbette göster" seçilirse
  /// galeri fotoğrafın mesaj kimliğiyle kapanır (bkz. `ChatPage`);
  /// silinebiliyorsa yanında "Fotoğrafı Sil" vardır.
  Future<void> _openPhoto(
    MealModel photo,
    MessageData message,
    double dialogImageHeight,
  ) async {
    final bool canDelete = _canDelete(message);
    final _PhotoAction? action = await showMealImageDetailsDialog<_PhotoAction>(
      context,
      photo,
      dialogImageHeight: dialogImageHeight,
      heroTag: MealImageCard.heroTagFor(photo),
      footerBuilder: (dialogContext) => Wrap(
        spacing: _footerButtonGap,
        runSpacing: _footerButtonGap,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text(_goToChatLabel),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_PhotoAction.goToChat),
          ),
          if (canDelete)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              icon: Icon(MessageAction.deletePhoto.icon),
              label: Text(MessageAction.deletePhoto.label),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_PhotoAction.deletePhoto),
            ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    await _runPhotoAction(message, action);
  }

  Future<void> _openPhotoMenu(MessageData message, Offset globalPosition) async {
    final bool canDelete = _canDelete(message);
    final Color errorColor = Theme.of(context).colorScheme.error;

    final _PhotoAction? action = await showMenuAt<_PhotoAction>(
      context,
      globalPosition: globalPosition,
      items: [
        const PopupMenuItem<_PhotoAction>(
          value: _PhotoAction.goToChat,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.chat_bubble_outline),
            title: Text(_goToChatLabel),
          ),
        ),
        if (canDelete)
          PopupMenuItem<_PhotoAction>(
            value: _PhotoAction.deletePhoto,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(MessageAction.deletePhoto.icon, color: errorColor),
              title: Text(
                MessageAction.deletePhoto.label,
                style: TextStyle(color: errorColor),
              ),
            ),
          ),
      ],
    );
    if (action == null || !mounted) return;
    await _runPhotoAction(message, action);
  }

  /// Diyalogdan ya da menüden seçilen işlemi yapar.
  Future<void> _runPhotoAction(MessageData message, _PhotoAction action) async {
    switch (action) {
      case _PhotoAction.goToChat:
        Navigator.of(context).pop(message.id);
      case _PhotoAction.deletePhoto:
        final Future<void> Function(MessageData message)? onDeletePhoto =
            widget.onDeletePhoto;
        if (onDeletePhoto == null) return;
        await onDeletePhoto(message);
        if (mounted) await _gallery.refreshMessage(message.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(),
      ),
      body: ListenableBuilder(
        listenable: _gallery,
        builder: (context, _) {
          if (_gallery.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_gallery.hasFailed) {
            return const _CenteredNote(
              icon: Icons.error_outline,
              message: _loadErrorText,
              isError: true,
            );
          }

          final List<MessageData> photos = _gallery.photos;
          if (photos.isEmpty) {
            if (_gallery.olderLoadFailed) {
              return _CenteredNote(
                icon: Icons.error_outline,
                message: _olderErrorText,
                isError: true,
                actionLabel: _retryLabel,
                onAction: _gallery.retryOlder,
              );
            }
            if (!_gallery.atStart) {
              return const Center(child: CircularProgressIndicator());
            }
            return _CenteredNote(
              icon: Icons.photo_library_outlined,
              message: _isOwnGallery ? _ownEmptyText : _emptyText,
            );
          }

          return Column(
            children: [
              _PhotoCountHeader(label: _countLabel(photos.length)),
              Expanded(
                child: UserMediaGalleryGrid(
                  controller: _scrollController,
                  itemCount: photos.length,
                  complete: _complete,
                  topEdge: _buildTopEdge(),
                  onNearOldest: _loadOlderIfNearOldest,
                  itemBuilder: (context, i, dialogImageHeight) {
                    final MessageData message = photos[i];
                    final MealModel photo = _toMeal(message);
                    return MealImageCard(
                      meal: photo,
                      dialogImageHeight: dialogImageHeight,
                      onTap: () =>
                          _openPhoto(photo, message, dialogImageHeight),
                      onMenu: (globalPosition) =>
                          _openPhotoMenu(message, globalPosition),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// App bar title: the user's resolved full name, falling back to a generic
  /// label while loading or if the profile can't be read.
  Widget _buildTitle() {
    if (_isOwnGallery) return const Text(_ownTitle);
    return FutureBuilder<UserModel?>(
      future: _userFuture,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const Text(_titleFallback);
        final fullName = '${user.name} ${user.surname}'.trim();
        return Text(
          fullName.isEmpty ? _titleFallback : fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

enum _PhotoAction { goToChat, deletePhoto }

/// Galerinin fotoğraf ızgarası. Sütun sayısı genişlikten çıkar: kart en az
/// [_minCardWidth] genişlikte kalır (telefonda 3 sütun), geniş ekranda en
/// fazla [_maxColumns]. Kart oranı, Öğün Fotoğrafları şeridindeki kartla
/// aynı: görsel, altındaki öğün/saat satırından sonra da kareye yakın kalır.
///
/// Fotoğraflar en yeni başta verilir ([itemBuilder]'ın dizini) ve eskiden
/// yeniye, soldan sağa, yukarıdan aşağı dizilir; ızgara en yeniden (alttan)
/// açılır ve eski fotoğraflar üste eklenir, ekrandaki kartlar yer değiştirmez.
/// [complete] ise (galerinin tamamı) ilk fotoğraf sol üstten başlar; değilse
/// en yeni fotoğraf sağ alttadır ve eksik hücreler en üst satırın solunda
/// kalır.
class UserMediaGalleryGrid extends StatelessWidget {
  static const int _minColumns = 2;
  static const int _maxColumns = 5;
  static const double _minCardWidth = 110.0;
  static const double _gridGap = 6.0;
  static const double _cardAspectRatio = 0.85;

  static const double loadOlderThreshold = 400.0;

  /// Izgaranın kaydırma konumu; [Scrollbar] ile paylaşılır.
  final ScrollController controller;

  final int itemCount;

  /// Kartı kurar; [dialogImageHeight] karta dokununca açılan büyük görselin
  /// yüksekliğidir (kart genişliğinden hesaplanır).
  final Widget Function(
    BuildContext context,
    int index,
    double dialogImageHeight,
  ) itemBuilder;

  final bool complete;

  final Widget? topEdge;

  final VoidCallback? onNearOldest;

  const UserMediaGalleryGrid({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.complete = false,
    this.topEdge,
    this.onNearOldest,
  });

  static int cellCountFor(int itemCount, int columns) =>
      (itemCount / columns).ceil() * columns;

  static int? itemIndexAt(
    int cell, {
    required int itemCount,
    required int columns,
    required bool complete,
  }) {
    final int cells = cellCountFor(itemCount, columns);
    final int rowFromTop = cells ~/ columns - 1 - cell ~/ columns;
    final int cellFromFirst = rowFromTop * columns + cell % columns;
    final int index = (complete ? itemCount : cells) - 1 - cellFromFirst;
    return index < 0 || index >= itemCount ? null : index;
  }

  bool _reportIfNearOldest(ScrollMetrics metrics, int depth) {
    final VoidCallback? onNearOldest = this.onNearOldest;
    if (depth == 0 &&
        onNearOldest != null &&
        metrics.maxScrollExtent - metrics.pixels <= loadOlderThreshold) {
      Future<void>.microtask(onNearOldest);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final int columns = ((width - _gridGap) / (_minCardWidth + _gridGap))
            .floor()
            .clamp(_minColumns, _maxColumns);
        final double cellWidth =
            (width - _gridGap * (columns + 1)) / columns;
        // Küçük karta dokununca da büyük görsel kullanışlı boyda açılsın.
        final double dialogImageHeight =
            (cellWidth * kMealDialogMultiplier).clamp(240.0, 480.0);
        final Widget? topEdge = this.topEdge;

        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) =>
              _reportIfNearOldest(notification.metrics, notification.depth),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) =>
                _reportIfNearOldest(notification.metrics, notification.depth),
            child: Align(
              alignment: Alignment.topCenter,
              child: Scrollbar(
                controller: controller,
                thumbVisibility: true,
                child: CustomScrollView(
                  controller: controller,
                  reverse: true,
                  shrinkWrap: true,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(_gridGap),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: _cardAspectRatio,
                          crossAxisSpacing: _gridGap,
                          mainAxisSpacing: _gridGap,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, cell) {
                            final int? index = itemIndexAt(
                              cell,
                              itemCount: itemCount,
                              columns: columns,
                              complete: complete,
                            );
                            return index == null
                                ? const SizedBox.shrink()
                                : itemBuilder(
                                    context, index, dialogImageHeight);
                          },
                          childCount: cellCountFor(itemCount, columns),
                        ),
                      ),
                    ),
                    if (topEdge != null) SliverToBoxAdapter(child: topEdge),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small header above the grid showing how many photos the user uploaded.
class _PhotoCountHeader extends StatelessWidget {
  final String label;

  const _PhotoCountHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Centered icon + message used for the empty and error states.
class _CenteredNote extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CenteredNote({
    required this.icon,
    required this.message,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

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
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
