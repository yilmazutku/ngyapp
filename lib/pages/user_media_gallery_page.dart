// lib/pages/user_media_gallery_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ngy_app/models/logger.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/widgets/meal_image_card.dart';

/// Full-page gallery of the photos a specific user has uploaded **in the chat**.
///
/// Opened by an admin from the chat screen by tapping the user's name in the
/// app bar. Unlike the images tab (which also shows meal photos uploaded
/// elsewhere), this shows ONLY chat-uploaded photos.
///
/// Architecture:
/// - Source: [ChatManager.userUploadedImagesStream] (messages the user sent
///   with an image). chatId == userId, so this is exactly the user's photos.
/// - Each chat image is adapted to a [MealModel] and rendered with the shared
///   [MealImageCard] so the layout matches the images tab (5 per row, tap to
///   enlarge with meal type + upload date & time).
/// - Sorted oldest→newest so the most recent photo sits at the very bottom.
class UserMediaGalleryPage extends StatefulWidget {
  /// The user whose chat-uploaded photos are shown (chatId == userId).
  final String userId;

  const UserMediaGalleryPage({super.key, required this.userId});

  @override
  State<UserMediaGalleryPage> createState() => _UserMediaGalleryPageState();
}

class _UserMediaGalleryPageState extends State<UserMediaGalleryPage> {
  static const String _titleFallback = 'Fotoğraflar';
  static const int _columns = 5; // 5 photos per row (as requested)
  static const double _gridGap = 6.0;
  static const double _cardAspectRatio = 1.2; // matches MealImageCard's layout
  static const String _mealPathPrefix = 'meals/';
  static const String _mealTextPrefix = 'Öğün: ';

  final Logger logger = Logger.forClass(UserMediaGalleryPage);

  /// Owns the grid scroll position so the [Scrollbar] can attach to it
  /// (shared-controller rule) and so we can jump to the bottom on open.
  final ScrollController _scrollController = ScrollController();

  /// Live stream of the user's chat-uploaded photos.
  Stream<List<MessageData>>? _imagesStream;

  /// One-shot fetch of the user's profile for the app bar title.
  Future<UserModel?>? _userFuture;

  /// Ensures the one-time "scroll to newest (bottom)" happens only once.
  bool _didAutoScroll = false;

  @override
  void initState() {
    super.initState();
    final chat = Provider.of<ChatManager>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    _imagesStream = chat.userUploadedImagesStream(widget.userId);
    _userFuture = userProvider.fetchUserDetails(userId: widget.userId);
    logger.info('UserMediaGalleryPage initialized. userId={}', [widget.userId]);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    logger.info('UserMediaGalleryPage disposed. userId={}', [widget.userId]);
    super.dispose();
  }

  /// Derive the meal type of a chat-uploaded photo. Meal photos posted to the
  /// chat carry the meal's enum name in [MessageData.storagePath]
  /// ('meals/{uid}/{name}') and its label in [MessageData.text]
  /// ('Öğün: {label}'); anything else falls back to [Meals.none].
  Meals _mealTypeOf(MessageData m) {
    final path = m.storagePath ?? '';
    if (path.startsWith(_mealPathPrefix)) {
      final byName = Meals.fromName(path.split('/').last);
      if (byName != null) return byName;
    }
    final text = m.text ?? '';
    if (text.startsWith(_mealTextPrefix)) {
      final label = text.substring(_mealTextPrefix.length).trim();
      return Meals.values.firstWhere(
        (x) => x.label == label,
        orElse: () => Meals.none,
      );
    }
    return Meals.none;
  }

  /// Adapt a chat image message to a [MealModel] so the shared [MealImageCard]
  /// can render it exactly like the images tab.
  MealModel _toMeal(MessageData m) {
    final ts = (m.createdAt ?? m.clientCreatedAt)?.toDate() ?? DateTime.now();
    final url = m.imageUrl ?? '';
    return MealModel(
      mealId: m.id,
      mealType: _mealTypeOf(m),
      imageUrls: url.isEmpty ? const <String>[] : <String>[url],
      timestamp: ts,
      isChecked: true,
    );
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
      appBar: AppBar(title: _buildTitle()),
      body: StreamBuilder<List<MessageData>>(
        stream: _imagesStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            logger.err('User media stream error. userId={} error={}', [widget.userId, snap.error]);
            return const _CenteredNote(
              icon: Icons.error_outline,
              message: 'Fotoğraflar yüklenemedi. Lütfen tekrar deneyin.',
              isError: true,
            );
          }

          final messages = snap.data ?? const <MessageData>[];
          if (messages.isEmpty) {
            return const _CenteredNote(
              icon: Icons.photo_library_outlined,
              message: 'Bu kişi sohbette henüz fotoğraf yüklemedi.',
            );
          }

          // Oldest first so the newest photo sits at the very bottom.
          final meals = messages.map(_toMeal).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

          _scheduleScrollToBottom();

          return Column(
            children: [
              _PhotoCountHeader(count: meals.length),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cellWidth =
                        (constraints.maxWidth - _gridGap * (_columns + 1)) /
                            _columns;
                    final double thumbSize = cellWidth.clamp(48.0, 400.0);
                    // Floor the enlarged image height so tapping a small 5-per-row
                    // thumbnail still opens a usefully large preview.
                    final double dialogImageHeight =
                        (thumbSize * kMealDialogMultiplier).clamp(240.0, 480.0);

                    return Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(_gridGap),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _columns,
                          childAspectRatio: _cardAspectRatio,
                          crossAxisSpacing: _gridGap,
                          mainAxisSpacing: _gridGap,
                        ),
                        itemCount: meals.length,
                        itemBuilder: (context, i) => MealImageCard(
                          meal: meals[i],
                          thumbSize: thumbSize,
                          dialogImageHeight: dialogImageHeight,
                        ),
                      ),
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
