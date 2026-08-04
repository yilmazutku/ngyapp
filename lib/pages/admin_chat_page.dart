// lib/pages/admin_chat_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ngy_app/pages/chat_page_new.dart';
import 'package:ngy_app/models/logger.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/widgets/chat_image_preview.dart';
import 'package:ngy_app/utils/dialog_utils.dart';

/// Admin chat list page displaying all chats where the admin is a participant.
/// 
/// Features:
/// - Shows all user chats sorted by last message time
/// - Displays last message text and/or image preview
/// - Tapping a chat opens the full conversation
/// - Real-time updates via Firestore streams
/// - Admins can initiate new chats with any customer user
/// 
/// Architecture:
/// - Uses server-side sorting (requires Firestore composite index)
/// - Index required: chats collection, fields: participants (array-contains), lastMessageAt (descending)
/// - Ignores first cached snapshot to avoid showing stale data
/// - Handles index-building transient errors gracefully
/// 
/// Query structure:
/// - Collection: chats
/// - Filter: participants array-contains adminUid
/// - Order: lastMessageAt descending
/// - Limit: 200 most recent chats
class AdminChatListPage extends StatefulWidget {
  const AdminChatListPage({super.key});

  @override
  State<AdminChatListPage> createState() => _AdminChatListPageState();
}

class _AdminChatListPageState extends State<AdminChatListPage> {
  final Logger logger = Logger.forClass(AdminChatListPage);
  
  /// Flag to ignore the first purely-cached snapshot to avoid showing stale data
  bool _serverSeen = false;

  /// Whether the list is currently in multi-select (bulk) mode.
  bool _selectionMode = false;

  /// Chat IDs selected while in bulk-select mode.
  final Set<String> _selectedChatIds = <String>{};

  /// Chat IDs currently rendered by the stream (used for "select all").
  List<String> _visibleChatIds = <String>[];

  /// Stable chat stream kept in a field so toggling selection (setState) does
  /// not resubscribe the Firestore stream and flash the list to a spinner.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _chatStream;

  @override
  void initState() {
    super.initState();
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    logger.info('AdminChatListPage initialized. adminUid={}', [adminUid ?? 'null']);
    _chatStream = _buildChatStream();
  }

  /// Builds the Firestore stream of chats where this admin is a participant.
  ///
  /// IMPORTANT: This requires a composite index in Firestore:
  ///   Collection: chats
  ///   Fields: participants (Array-contains), lastMessageAt (Descending)
  Stream<QuerySnapshot<Map<String, dynamic>>> _buildChatStream() {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final q = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: adminUid)
        .orderBy('lastMessageAt', descending: true)
        .limit(200);
    return q.snapshots(includeMetadataChanges: true);
  }

  // ===== Bulk selection =====

  /// Enter multi-select mode, optionally selecting an initial chat.
  void _enterSelectionMode([String? initialChatId]) {
    setState(() {
      _selectionMode = true;
      if (initialChatId != null) _selectedChatIds.add(initialChatId);
    });
  }

  /// Leave multi-select mode and clear the current selection.
  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedChatIds.clear();
    });
  }

  /// Toggle a single chat's selection. Automatically leaves selection mode when
  /// the last selected item is removed.
  void _toggleSelected(String chatId) {
    setState(() {
      if (!_selectedChatIds.remove(chatId)) {
        _selectedChatIds.add(chatId);
      }
      if (_selectedChatIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  /// Select every chat currently visible in the list.
  void _selectAllVisible() {
    setState(() {
      _selectedChatIds
        ..clear()
        ..addAll(_visibleChatIds);
    });
  }

  @override
  void dispose() {
    logger.info('AdminChatListPage disposed');
    super.dispose();
  }

  /// Opens a dialog for selecting a user to start a new chat.
  /// 
  /// Shows a searchable list of all customer users. When a user is selected,
  /// navigates to ChatPage with the selected user's ID.
  Future<void> _showNewChatDialog() async {
    logger.info('Opening new chat user selection dialog');
    
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    
    final selectedUserId = await showDialog<String>(
      context: context,
      builder: (context) => _UserSelectionDialog(
        userProvider: userProvider,
        logger: logger,
      ),
    );
    
    if (selectedUserId != null && mounted) {
      logger.info('User selected for new chat. userId={}', [selectedUserId]);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(overrideChatId: selectedUserId),
        ),
      );
    } else {
      logger.debug('New chat dialog cancelled or no user selected');
    }
  }

  /// Confirm and permanently delete a chat (with all messages and photos).
  ///
  /// Runs from the page's own context so the confirm/loading/info dialogs stay
  /// valid even after the deleted item disappears from the streamed list.
  Future<void> _handleDeleteChat(String chatId, String displayName) async {
    logger.info('Delete chat requested from list. chatId={} name="{}"', [chatId, displayName]);

    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Sohbeti Sil',
      message: '"$displayName" ile olan sohbet, tüm mesajlar ve yüklenen fotoğraflar '
          'kalıcı olarak silinecek. Bu işlem geri alınamaz.\n\nDevam etmek istiyor musunuz?',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );

    if (!confirmed) {
      logger.debug('Chat deletion cancelled. chatId={}', [chatId]);
      return;
    }

    if (!mounted) return;
    final chatManager = Provider.of<ChatManager>(context, listen: false);

    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoading(context, message: 'Sohbet siliniyor...');
      loadingOpen = true;
    }

    try {
      await chatManager.deleteChat(chatId);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        await DialogUtils.openInfo(context, title: 'Başarılı', message: 'Sohbet silindi.');
      }
    } catch (e) {
      logger.err('Chat deletion failed. chatId={} error={}', [chatId, e]);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Sohbet silinemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  /// Confirm and permanently delete all currently selected chats (with their
  /// messages and photos). Shows the same style of confirmation used for a
  /// single deletion, then a live progress loader while deleting one by one.
  Future<void> _handleDeleteSelectedChats() async {
    final ids = _selectedChatIds.toList();
    if (ids.isEmpty) return;

    logger.info('Bulk delete requested. count={}', [ids.length]);

    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Seçili Sohbetleri Sil',
      message: 'Seçili ${ids.length} sohbet, tüm mesajlar ve yüklenen fotoğraflar '
          'kalıcı olarak silinecek. Bu işlem geri alınamaz.\n\nDevam etmek istiyor musunuz?',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );

    if (!confirmed) {
      logger.debug('Bulk deletion cancelled. count={}', [ids.length]);
      return;
    }

    if (!mounted) return;
    final chatManager = Provider.of<ChatManager>(context, listen: false);

    final progress = ValueNotifier<String>('Sohbetler siliniyor... (0/${ids.length})');
    bool loadingOpen = false;
    if (mounted) {
      DialogUtils.openLoadingProgress(context, messageListenable: progress);
      loadingOpen = true;
    }

    int deleted = 0;
    final List<String> failed = [];

    try {
      for (var i = 0; i < ids.length; i++) {
        final chatId = ids[i];
        try {
          await chatManager.deleteChat(chatId);
          deleted++;
        } catch (e) {
          logger.err('Bulk delete: chat deletion failed. chatId={} error={}', [chatId, e]);
          failed.add(chatId);
        }
        progress.value = 'Sohbetler siliniyor... (${i + 1}/${ids.length})';
      }

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        if (failed.isEmpty) {
          await DialogUtils.openInfo(
            context,
            title: 'Başarılı',
            message: '$deleted sohbet silindi.',
          );
        } else {
          await DialogUtils.openError(
            context,
            title: 'Kısmen Tamamlandı',
            message: '$deleted sohbet silindi, ${failed.length} sohbet silinemedi. '
                'Lütfen tekrar deneyin.',
          );
        }
      }
    } catch (e) {
      logger.err('Bulk delete failed unexpectedly. error={}', [e]);

      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }

      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Sohbetler silinemedi. Lütfen tekrar deneyin.',
        );
      }
    } finally {
      progress.dispose();
      if (mounted) {
        _exitSelectionMode();
      }
    }
  }

  /// Default (non-selection) app bar.
  PreferredSizeWidget _buildDefaultAppBar() {
    return AppBar(
      title: const Text('Tüm Sohbetler'),
      actions: [
        // Bulk-select entry point with a visible label (left of refresh).
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          icon: const Icon(Icons.checklist),
          label: const Text('Toplu Seç'),
          onPressed: () {
            logger.info('Bulk-select mode entered');
            _enterSelectionMode();
          },
        ),
        IconButton(
          tooltip: 'Yenile',
          icon: const Icon(Icons.refresh),
          onPressed: () {
            logger.info('Manual refresh button tapped');
            setState(() {
              _chatStream = _buildChatStream();
            });
          },
        ),
      ],
    );
  }

  /// App bar shown while in bulk-select mode: shows the selected count and the
  /// "select all" / "delete selected" actions.
  PreferredSizeWidget _buildSelectionAppBar() {
    final count = _selectedChatIds.length;
    final canSelectAll = _visibleChatIds.isNotEmpty &&
        !_visibleChatIds.every(_selectedChatIds.contains);
    return AppBar(
      leading: IconButton(
        tooltip: 'Vazgeç',
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('$count seçildi'),
      actions: [
        IconButton(
          tooltip: 'Tümünü Seç',
          icon: const Icon(Icons.select_all),
          onPressed: canSelectAll ? _selectAllVisible : null,
        ),
        IconButton(
          tooltip: 'Seçilenleri Sil',
          icon: const Icon(Icons.delete),
          color: count == 0 ? null : Colors.red,
          onPressed: count == 0 ? null : _handleDeleteSelectedChats,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminUid = FirebaseAuth.instance.currentUser!.uid;
    logger.debug('Building AdminChatListPage. adminUid={} selectionMode={}', [adminUid, _selectionMode]);

    return Scaffold(
      appBar: _selectionMode ? _buildSelectionAppBar() : _buildDefaultAppBar(),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _showNewChatDialog,
              icon: const Icon(Icons.add_comment),
              label: const Text('Yeni Sohbet'),
              tooltip: 'Yeni sohbet başlat',
            ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _chatStream,
        builder: (context, snap) {
          // Loading state (keep showing existing data across resubscribes)
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            logger.debug('Chats stream: waiting for initial connection');
            return const Center(child: CircularProgressIndicator());
          }

          // Error handling
          if (snap.hasError) {
            final err = snap.error;
            
            // Special case: Firestore composite index is still building
            // This is a transient error that resolves automatically
            if (err is FirebaseException &&
                err.plugin == 'cloud_firestore' &&
                err.code == 'failed-precondition') {
              logger.warn('Composite index is still building. Waiting for completion...');
              return const _CenterNote('Sunucu dizini hazırlanıyor… Birazdan yüklenecek.');
            }
            
            // Other errors
            logger.err('Chats stream error. error={}', [err]);
            return _ErrorView(error: err.toString());
          }

          // No data received
          if (!snap.hasData) {
            logger.warn('Chats stream: no data received');
            return const _CenterNote('Veri bulunamadı.');
          }

          // Process snapshot data
          final data = snap.data!;
          final fromCache = data.metadata.isFromCache;
          final hasPendingWrites = data.metadata.hasPendingWrites;
          final docs = data.docs;

          logger.debug(
            'Chats stream update. docCount={} fromCache={} hasPendingWrites={}',
            [docs.length, fromCache, hasPendingWrites],
          );

          // Ignore first cached snapshot to avoid showing stale data
          // This ensures users see fresh data from the server
          if (fromCache && !_serverSeen) {
            logger.debug('Ignoring first cached snapshot, waiting for server data');
            return const _CenterNote('Sunucu ile eşitleniyor…');
          }
          if (!fromCache) {
            _serverSeen = true;
            logger.debug('Server data received, _serverSeen set to true');
          }

          // Empty state
          if (docs.isEmpty) {
            logger.debug('No chats found');
            return const _CenterNote('Sohbet bulunamadı.');
          }

          logger.debug('Rendering {} chats', [docs.length]);

          // Track visible chat IDs so "select all" knows what to select.
          _visibleChatIds = docs.map((e) => e.id).toList();

          // Render chat list
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final chatId = d.id; // In one-chat-per-user model, chatId == userUid
              final data = d.data();
              
              // Extract chat metadata
              final lastMsg = (data['lastMessage'] ?? '') as String;
              final lastImageUrl = data['lastImageUrl'] as String?;
              final lastAt = data['lastMessageAt'] as Timestamp?;
              
              // Format timestamp
              final ts = lastAt?.toDate();
              final timeStr = ts == null
                  ? ''
                  : '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
              
              // Show image preview if lastImageUrl exists and is not empty
              // (lastImageUrl is cleared when a text-only message is sent)
              final hasImage = lastImageUrl != null && lastImageUrl.isNotEmpty;

              // Get unread count for this admin
              final unreadCount = ChatManager.getUnreadCountFromChatData(data, adminUid);
              
              // Debug log for unread count
              logger.debug(
                'Chat item: chatId={} adminUid={} unreadCount={} rawData={}',
                [chatId, adminUid, unreadCount, data['adminUnreadCount']],
              );

              return _ChatListItem(
                chatId: chatId,
                lastMsg: lastMsg,
                lastImageUrl: lastImageUrl,
                timeStr: timeStr,
                hasImage: hasImage,
                unreadCount: unreadCount,
                logger: logger,
                onDelete: _handleDeleteChat,
                selectionMode: _selectionMode,
                selected: _selectedChatIds.contains(chatId),
                onToggleSelected: _toggleSelected,
                onLongPressSelect: _enterSelectionMode,
              );
            },
          );
        },
      ),
    );
  }
}

/// Widget representing a single chat item in the admin chat list.
/// 
/// Fetches user details to display name instead of UID.
/// Shows last message, image preview, timestamp, and unread badge.
class _ChatListItem extends StatelessWidget {
  final String chatId;
  final String lastMsg;
  final String? lastImageUrl;
  final String timeStr;
  final bool hasImage;
  final int unreadCount;
  final Logger logger;

  /// Called when the admin taps the delete (trash) icon for this chat.
  /// Receives the chatId and the resolved display name for the confirmation.
  final void Function(String chatId, String displayName) onDelete;

  /// Whether the list is in bulk-select mode.
  final bool selectionMode;

  /// Whether this chat is currently selected.
  final bool selected;

  /// Toggles this chat's selection (used while in bulk-select mode).
  final void Function(String chatId) onToggleSelected;

  /// Enters bulk-select mode and selects this chat (long-press).
  final void Function(String chatId) onLongPressSelect;

  const _ChatListItem({
    required this.chatId,
    required this.lastMsg,
    required this.lastImageUrl,
    required this.timeStr,
    required this.hasImage,
    required this.unreadCount,
    required this.logger,
    required this.onDelete,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelected,
    required this.onLongPressSelect,
  });

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return FutureBuilder(
      future: userProvider.fetchUserDetails(userId: chatId),
      builder: (context, snapshot) {
        // Determine display name: user's full name or fallback to UID
        String displayName = chatId; // Fallback to UID
        
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          final firstName = user.name.trim();
          final lastName = user.surname.trim() ?? '';
          displayName = lastName.isNotEmpty ? '$firstName $lastName' : firstName;
          logger.debug('User name loaded for chat list. chatId={} name="{}"', [chatId, displayName]);
        } else if (snapshot.hasError) {
          logger.warn('Failed to load user name for chat list. chatId={} error={}', [chatId, snapshot.error]);
        }

        return Column(
          children: [
            // Main chat list tile
            ListTile(
              selected: selectionMode && selected,
              selectedTileColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              leading: selectionMode
                  ? Checkbox(
                      value: selected,
                      onChanged: (_) => onToggleSelected(chatId),
                    )
                  : const Icon(Icons.person),
              title: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show last message text if available
                  if (lastMsg.isNotEmpty)
                    Text(
                      lastMsg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  
                  // Show image indicator if last message included an image
                  if (hasImage)
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Icon(Icons.image, size: 16, color: Colors.blue),
                          SizedBox(width: 4),
                          Text('Görsel', style: TextStyle(color: Colors.blue)),
                        ],
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: unreadCount > 0 ? Colors.green.shade700 : Colors.grey,
                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Delete chat (and all its photos) — admin only.
                  // Hidden in bulk-select mode (bulk delete lives in the app bar).
                  if (!selectionMode)
                    IconButton(
                      tooltip: 'Sohbeti Sil',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () {
                        logger.debug('Chat delete icon tapped. chatId={}', [chatId]);
                        onDelete(chatId, displayName);
                      },
                    ),
                ],
              ),
              onLongPress:
                  selectionMode ? null : () => onLongPressSelect(chatId),
              onTap: selectionMode
                  ? () => onToggleSelected(chatId)
                  : () async {
                      logger.info('Opening chat for user. chatId={} userName="{}"', [chatId, displayName]);
                      // Mark chat as read when admin opens it
                      final chatManager = Provider.of<ChatManager>(context, listen: false);
                      await chatManager.markChatAsRead(chatId);
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(overrideChatId: chatId),
                        ),
                      );
                    },
            ),
            
            // Show image preview below the list tile if available
            if (hasImage)
              Padding(
                padding: const EdgeInsets.only(left: 72.0, bottom: 8.0, right: 16.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    height: 60,
                    width: 80,
                    child: ChatImagePreview(
                      imageUrl: lastImageUrl,
                      width: 80,
                      height: 60,
                      usePlaceholder: false,
                      borderRadius: 8.0,
                      onTap: selectionMode
                          ? () => onToggleSelected(chatId)
                          : () {
                              logger.info('Image preview tapped, opening chat. chatId={} userName="{}"', [chatId, displayName]);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(overrideChatId: chatId),
                                ),
                              );
                            },
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Helper widget to display centered informational text.
/// Used for loading states, empty states, and sync messages.
class _CenterNote extends StatelessWidget {
  final String text;
  
  const _CenterNote(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// Helper widget to display error information with troubleshooting hints.
/// Shows the error message and common causes for chat loading failures.
class _ErrorView extends StatelessWidget {
  final String error;
  
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Sohbetler yüklenemedi:\n$error\n\n'
              'Muhtemel nedenler:\n'
              '• Gerekli Firestore indeksleri henüz oluşturulmadı\n'
              '• Yetki hatası (security rules)\n'
              '• Ağ/bağlantı problemi',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
    );
  }
}

/// Dialog for selecting a user to start a new chat.
/// 
/// Features:
/// - Fetches all customer users on initialization
/// - Searchable by name, surname, or email
/// - Displays user name and email in the list
/// - Returns the selected user's ID or null if cancelled
class _UserSelectionDialog extends StatefulWidget {
  final UserProvider userProvider;
  final Logger logger;

  const _UserSelectionDialog({
    required this.userProvider,
    required this.logger,
  });

  @override
  State<_UserSelectionDialog> createState() => _UserSelectionDialogState();
}

class _UserSelectionDialogState extends State<_UserSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Load all customer users from Firestore.
  Future<void> _loadUsers() async {
    widget.logger.debug('Loading users for new chat dialog');
    
    try {
      final users = await widget.userProvider.fetchAllCustomers();
      
      // Sort users by name for easier browsing
      users.sort((a, b) {
        final nameA = '${a.name} ${a.surname}'.toLowerCase();
        final nameB = '${b.name} ${b.surname}'.toLowerCase();
        return nameA.compareTo(nameB);
      });
      
      if (!mounted) return;
      
      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _isLoading = false;
      });
      
      widget.logger.info('Loaded {} users for new chat selection', [users.length]);
    } catch (e) {
      widget.logger.err('Error loading users for new chat dialog: {}', [e]);
      
      if (!mounted) return;
      
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Filter users based on search query.
  /// 
  /// Matches against name, surname, and email (case-insensitive).
  void _filterUsers(String query) {
    final normalizedQuery = query.toLowerCase().trim();
    
    if (normalizedQuery.isEmpty) {
      setState(() {
        _filteredUsers = _allUsers;
      });
      return;
    }
    
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        final fullName = '${user.name} ${user.surname}'.toLowerCase();
        final email = user.email.toLowerCase();
        return fullName.contains(normalizedQuery) || email.contains(normalizedQuery);
      }).toList();
    });
    
    widget.logger.debug('Search filter applied. query="{}" results={}', [query, _filteredUsers.length]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kullanıcı Seçin'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'İsim veya e-posta ile ara...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterUsers('');
                        },
                      )
                    : null,
              ),
              onChanged: _filterUsers,
            ),
            const SizedBox(height: 12),
            
            // User list
            Expanded(
              child: _buildUserList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
      ],
    );
  }

  /// Build the user list based on current loading/error/data state.
  Widget _buildUserList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Kullanıcılar yüklenemedi',
              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    if (_filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_search, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Aramayla eşleşen kullanıcı bulunamadı'
                  : 'Henüz kayıtlı kullanıcı yok',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return ListView.separated(
      itemCount: _filteredUsers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        final fullName = '${user.name} ${user.surname}'.trim();
        final displayName = fullName.isNotEmpty ? fullName : 'İsimsiz Kullanıcı';
        
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            user.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () {
            widget.logger.debug('User selected in dialog. userId={} name="{}"', [user.userId, displayName]);
            Navigator.of(context).pop(user.userId);
          },
        );
      },
    );
  }
}
