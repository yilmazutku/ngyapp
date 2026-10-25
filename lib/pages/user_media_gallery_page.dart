// lib/pages/user_media_gallery_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/utils/menu_utils.dart';
import 'package:ngy_app/widgets/chat/message_actions_sheet.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';
import 'package:ngy_app/widgets/home_button.dart';

/// Full-page gallery of the photos a specific user has uploaded **in the chat**.
///
/// Opened from the chat screen by tapping the title in the app bar: the admin
/// taps the user's name, the user taps the dietitian's name and sees their own
/// photos. Unlike the images tab (which also shows meal photos uploaded
/// elsewhere), this shows ONLY chat-uploaded photos.
///
/// Architecture:
/// - Source: [ChatManager.userUploadedImagesStream] (messages the user sent
///   with an image). chatId == userId, so this is exactly the user's photos.
/// - Each chat image is adapted to a [MealModel] and rendered with the shared
///   [MealImageCard] so the layout matches the images tab (tap to enlarge with
///   meal type + upload date & time). Sütun sayısı genişliğe göre değişir:
///   telefonda 3, geniş ekranda 5 (bkz. [UserMediaGalleryGrid]).
/// - Sorted oldest→newest so the most recent photo sits at the very bottom.
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

  /// Büyük görsel diyaloğundaki düğmelerin arası.
  static const double _footerButtonGap = 8;

  /// Owns the grid scroll position so the [Scrollbar] can attach to it
  /// (shared-controller rule) and so we can jump to the bottom on open.
  final ScrollController _scrollController = ScrollController();

  /// Live stream of the user's chat-uploaded photos.
  Stream<List<MessageData>>? _imagesStream;

  /// One-shot fetch of the user's profile for the app bar title.
  Future<UserModel?>? _userFuture;

  late final bool _isOwnGallery;

  /// Ensures the one-time "scroll to newest (bottom)" happens only once.
  bool _didAutoScroll = false;

  @override
  void initState() {
    super.initState();
    final chat = Provider.of<ChatManager>(context, listen: false);
    _imagesStream = chat.userUploadedImagesStream(widget.userId);
    _isOwnGallery =
        FirebaseAuth.instance.currentUser?.uid == widget.userId;
    if (!_isOwnGallery) {
      _userFuture = Provider.of<UserProvider>(context, listen: false)
          .fetchUserDetails(userId: widget.userId);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
        if (onDeletePhoto != null) await onDeletePhoto(message);
    }
  }

  /// Jump to the bottom once so the newest photo is visible on open.
  void _scheduleScrollToBottom() {
    if (_didAutoScroll) return;
    _didAutoScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(),
        actions: const [HomeButton()],
      ),
      body: StreamBuilder<List<MessageData>>(
        stream: _imagesStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return const _CenteredNote(
              icon: Icons.error_outline,
              message: 'Fotoğraflar yüklenemedi. Lütfen tekrar deneyin.',
              isError: true,
            );
          }

          final messages = snap.data ?? const <MessageData>[];
          if (messages.isEmpty) {
            return _CenteredNote(
              icon: Icons.photo_library_outlined,
              message: _isOwnGallery ? _ownEmptyText : _emptyText,
            );
          }
          final Map<String, MessageData> messagesById = {
            for (final MessageData message in messages) message.id: message,
          };

          // Oldest first so the newest photo sits at the very bottom.
          final meals = messages.map(_toMeal).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

          _scheduleScrollToBottom();

          return Column(
            children: [
              _PhotoCountHeader(count: meals.length),
              Expanded(
                child: UserMediaGalleryGrid(
                  controller: _scrollController,
                  itemCount: meals.length,
                  itemBuilder: (context, i, dialogImageHeight) {
                    final MessageData? message = messagesById[meals[i].mealId];
                    return MealImageCard(
                      meal: meals[i],
                      dialogImageHeight: dialogImageHeight,
                      onTap: message == null
                          ? null
                          : () =>
                              _openPhoto(meals[i], message, dialogImageHeight),
                      onMenu: message == null
                          ? null
                          : (globalPosition) =>
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
class UserMediaGalleryGrid extends StatelessWidget {
  static const int _minColumns = 2;
  static const int _maxColumns = 5;
  static const double _minCardWidth = 110.0;
  static const double _gridGap = 6.0;
  static const double _cardAspectRatio = 0.85;

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

  const UserMediaGalleryGrid({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
  });

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

        return Scrollbar(
          controller: controller,
          thumbVisibility: true,
          child: GridView.builder(
            controller: controller,
            padding: const EdgeInsets.all(_gridGap),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: _cardAspectRatio,
              crossAxisSpacing: _gridGap,
              mainAxisSpacing: _gridGap,
            ),
            itemCount: itemCount,
            itemBuilder: (context, i) =>
                itemBuilder(context, i, dialogImageHeight),
          ),
        );
      },
    );
  }
}

/// Small header above the grid showing how many photos the user uploaded.
class _PhotoCountHeader extends StatelessWidget {
  final int count;

  const _PhotoCountHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        '$count fotoğraf',
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

  const _CenteredNote({
    required this.icon,
    required this.message,
    this.isError = false,
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
          ],
        ),
      ),
    );
  }
}
