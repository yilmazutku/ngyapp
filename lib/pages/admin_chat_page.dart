// lib/pages/admin_chat_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:ngy_app/pages/chat_page_new.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/widgets/meal_thumbnail_image.dart';
import 'package:ngy_app/utils/date_formatter.dart';
import 'package:ngy_app/utils/dialog_utils.dart';
import 'package:ngy_app/utils/search_text.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/search_field.dart';

/// Admin chat list page displaying all chats where the admin is a participant.
/// 
/// Features:
/// - Shows all user chats sorted by last message time
/// - Displays last message text and/or image preview
/// - Tapping a chat opens the full conversation
/// - Real-time updates via Firestore streams
/// - Admins can initiate new chats with any customer user
/// - Danışan adına göre arama ve "Okunmamışlar" süzgeci; adlar bir kez okunur
///   ve saklanır (liste her güncellendiğinde yeniden okunmaz). Arama listede
///   sohbeti olmayan danışanları da bulur; onlarla sohbet buradan açılır
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

/// Sohbet satırının menüsündeki işlemler.
enum _ChatRowAction { delete }

class _AdminChatListPageState extends State<AdminChatListPage> {
  static const String _searchLabel = 'Danışan ara (ad soyad / e-posta)';
  static const String _unreadOnlyLabel = 'Okunmamışlar';
  static const String _noMatchText = 'Aramaya uyan sohbet yok.';
  static const String _noUnreadText = 'Okunmamış sohbet yok.';
  static const String _otherCustomersTitle = 'Listede olmayan danışanlar';
  static const String _openChatLabel = 'Sohbeti aç';

  /// Flag to ignore the first purely-cached snapshot to avoid showing stale data
  bool _serverSeen = false;

  /// Danışanlar (uid -> kullanıcı): liste açılırken bir kez okunur; satırlar
  /// adı buradan alır. Müşteri listesinde olmayan bir sohbet sahibi bir kez
  /// ayrıca okunur ([_ensureUserLoaded]).
  final Map<String, UserModel> _usersById = {};

  /// Aramada karşılaştırılan kelimeler (ad soyad + e-posta), önceden
  /// normalize edilmiş.
  final Map<String, List<String>> _searchWordsById = {};

  /// Adı bir kez istenmiş kullanıcılar; aynı kişi tekrar tekrar okunmaz.
  final Set<String> _requestedUserIds = {};

  /// Kaydı bulunamayan (ör. silinmiş) kullanıcılar; satırda kimliği görünür.
  final Set<String> _missingUserIds = {};
  bool _customersLoaded = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _unreadOnly = false;

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
    _chatStream = _buildChatStream();
    _loadCustomers();
  }

  /// Danışan adlarını okur: açılışta oturumdaki önbellekten gelebilir,
  /// "Yenile" ile ([forceRefresh]) sunucudan okunur.
  Future<void> _loadCustomers({bool forceRefresh = false}) async {
    final UserProvider userProvider =
        Provider.of<UserProvider>(context, listen: false);
    try {
      final List<UserModel> customers =
          await userProvider.fetchAllCustomers(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        for (final UserModel user in customers) {
          _rememberUser(user);
        }
        _customersLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _customersLoaded = true);
    }
  }

  void _rememberUser(UserModel user) {
    _usersById[user.userId] = user;
    _requestedUserIds.add(user.userId);
    _searchWordsById[user.userId] =
        searchWordsOf('${user.fullName} ${user.email}');
  }

  /// Müşteri listesinde olmayan sohbet sahibinin adını bir kez okur.
  void _ensureUserLoaded(String userId) {
    if (!_customersLoaded || !_requestedUserIds.add(userId)) return;
    Provider.of<UserProvider>(context, listen: false)
        .fetchUserDetails(userId: userId)
        .then((user) {
      if (!mounted) return;
      setState(() {
        if (user == null) {
          _missingUserIds.add(userId);
        } else {
          _rememberUser(user);
        }
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _missingUserIds.add(userId));
    });
  }

  /// Satırda görünen ad; henüz okunmadıysa null, kaydı yoksa kimliği.
  String? _displayNameOf(String userId) {
    final UserModel? user = _usersById[userId];
    if (user == null) return _missingUserIds.contains(userId) ? userId : null;
    return user.fullName.isEmpty ? user.email : user.fullName;
  }

  /// Sohbeti açar. Ad biliniyorsa sohbet sayfası başlık için ayrıca okumaz.
  void _openChat(String chatId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          overrideChatId: chatId,
          userDisplayName: _usersById.containsKey(chatId)
              ? _displayNameOf(chatId)
              : null,
        ),
      ),
    );
  }

  /// Aramaya uyan ama listede sohbeti olmayan danışanlar (sohbeti hiç
  /// başlamamış ya da listenin gösterdiği son sohbetlerden eski), ada göre.
  List<UserModel> _otherMatchingCustomers(
    List<String> queryWords,
    Set<String> listedChatIds,
  ) {
    if (queryWords.isEmpty || _unreadOnly || _selectionMode) return const [];
    final List<UserModel> matches = [
      for (final UserModel user in _usersById.values)
        if (!listedChatIds.contains(user.userId) &&
            matchesSearchWords(
              queryWords,
              _searchWordsById[user.userId] ?? const [],
            ))
          user,
    ];
    matches.sort((a, b) => compareSearchText(a.fullName, b.fullName));
    return matches;
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
    _searchController.dispose();
    super.dispose();
  }

  /// Opens a dialog for selecting a user to start a new chat.
  /// 
  /// Shows a searchable list of all customer users. When a user is selected,
  /// navigates to ChatPage with the selected user's ID.
  Future<void> _showNewChatDialog() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    
    final selectedUserId = await showDialog<String>(
      context: context,
      builder: (context) => _UserSelectionDialog(
        userProvider: userProvider,
      ),
    );
    
    if (selectedUserId != null && mounted) {
      _openChat(selectedUserId);
    }
  }

  /// Confirm and permanently delete a chat and its messages. Öğün
  /// fotoğrafları danışanın öğün kayıtlarında kalır (bkz.
  /// [ChatPage.deleteChatPhotosNote]); onay metni bunu söyler.
  ///
  /// Runs from the page's own context so the confirm/loading/info dialogs stay
  /// valid even after the deleted item disappears from the streamed list.
  Future<void> _handleDeleteChat(String chatId, String displayName) async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Sohbeti Sil',
      message: '"$displayName" ile olan sohbet ve tüm mesajları kalıcı olarak '
          'silinecek. ${ChatPage.deleteChatPhotosNote} Bu işlem geri '
          'alınamaz.\n\nDevam etmek istiyor musunuz?',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );

    if (!confirmed) {
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

  /// Confirm and permanently delete all currently selected chats and their
  /// messages (meal photos stay, see [ChatPage.deleteChatPhotosNote]). Shows
  /// the same style of confirmation used for a single deletion, then a live
  /// progress loader while deleting one by one.
  Future<void> _handleDeleteSelectedChats() async {
    final ids = _selectedChatIds.toList();
    if (ids.isEmpty) return;

    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Seçili Sohbetleri Sil',
      message: 'Seçili ${ids.length} sohbet ve tüm mesajları kalıcı olarak '
          'silinecek. ${ChatPage.deleteChatPhotosNote} Bu işlem geri '
          'alınamaz.\n\nDevam etmek istiyor musunuz?',
      confirmText: 'Sil',
      cancelText: 'İptal',
    );

    if (!confirmed) {
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
            _enterSelectionMode();
          },
        ),
        LabeledActionButton(
          icon: Icons.refresh,
          label: 'Yenile',
          onPressed: () {
            setState(() {
              _chatStream = _buildChatStream();
            });
            _loadCustomers(forceRefresh: true);
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
        LabeledActionButton(
          icon: Icons.select_all,
          label: 'Tümünü Seç',
          onPressed: canSelectAll ? _selectAllVisible : null,
        ),
        LabeledActionButton(
          icon: Icons.delete,
          label: 'Seçilenleri Sil',
          foregroundColor: count == 0 ? null : Colors.red,
          onPressed: count == 0 ? null : _handleDeleteSelectedChats,
        ),
      ],
    );
  }

  /// Arama kutusu ve "Okunmamışlar" süzgeci.
  Widget _buildFilters(int unreadChats) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SearchField(
              controller: _searchController,
              label: _searchLabel,
              maxWidth: double.infinity,
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text('$_unreadOnlyLabel ($unreadChats)'),
            selected: _unreadOnly,
            onSelected: (value) => setState(() => _unreadOnly = value),
          ),
        ],
      ),
    );
  }

  /// Sohbet satırları; aramada altta listede sohbeti olmayan danışanlar
  /// ([otherCustomers]).
  Widget _buildChatList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String adminUid,
    List<UserModel> otherCustomers,
  ) {
    final int otherCount =
        otherCustomers.isEmpty ? 0 : otherCustomers.length + 1;
    return ListView.separated(
      itemCount: docs.length + otherCount,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i >= docs.length) {
          final int index = i - docs.length;
          if (index == 0) return const _SectionTitle(_otherCustomersTitle);
          return _buildOtherCustomer(otherCustomers[index - 1]);
        }

        final d = docs[i];
        final chatId = d.id; // In one-chat-per-user model, chatId == userUid
        final data = d.data();
        _ensureUserLoaded(chatId);

        // Eski özetler de güncel öğün adıyla görünür
        // ("Öğün Fotoğrafı (Ara Öğün 2)" -> "(Ara)").
        final lastMsg =
            Meals.chatTextForDisplay((data['lastMessage'] ?? '') as String);
        final lastAt = data['lastMessageAt'] as Timestamp?;

        final ts = lastAt?.toDate();
        final timeStr = ts == null ? '' : DateFormatter.formatChatListTime(ts);

        // Son mesaj fotoğrafsa küçük görseli (eski özetlerde orijinali); metin
        // mesajı özeti boşaltır.
        final String lastImageUrl = (data['lastImageUrl'] as String?) ?? '';
        final String thumbUrl = (data['lastImageThumbUrl'] as String?) ?? '';

        return _ChatListItem(
          chatId: chatId,
          displayName: _displayNameOf(chatId),
          initials: _usersById[chatId]?.initials,
          lastMsg: lastMsg,
          previewUrl: thumbUrl.isNotEmpty
              ? thumbUrl
              : (lastImageUrl.isEmpty ? null : lastImageUrl),
          previewIsOriginal: thumbUrl.isEmpty,
          timeStr: timeStr,
          unreadCount: ChatManager.getUnreadCountFromChatData(data, adminUid),
          onOpen: _openChat,
          onDelete: _handleDeleteChat,
          selectionMode: _selectionMode,
          selected: _selectedChatIds.contains(chatId),
          onToggleSelected: _toggleSelected,
          onLongPressSelect: _enterSelectionMode,
        );
      },
    );
  }

  /// Aramada bulunan, listede sohbeti olmayan danışan; sohbet buradan açılır.
  Widget _buildOtherCustomer(UserModel user) {
    final String name = user.fullName.isEmpty ? user.email : user.fullName;
    return ListTile(
      leading: _InitialsAvatar(initials: user.initials),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        user.email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: () => _openChat(user.userId),
        child: const Text(_openChatLabel),
      ),
      onTap: () => _openChat(user.userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminUid = FirebaseAuth.instance.currentUser!.uid;

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
              return const _CenterNote('Sunucu dizini hazırlanıyor… Birazdan yüklenecek.');
            }
            
            // Other errors
            return _ErrorView(error: err.toString());
          }

          // No data received
          if (!snap.hasData) {
            return const _CenterNote('Veri bulunamadı.');
          }

          // Process snapshot data
          final data = snap.data!;
          final fromCache = data.metadata.isFromCache;
          final docs = data.docs;

          // Ignore first cached snapshot to avoid showing stale data
          // This ensures users see fresh data from the server
          if (fromCache && !_serverSeen) {
            return const _CenterNote('Sunucu ile eşitleniyor…');
          }
          if (!fromCache) {
            _serverSeen = true;
          }

          // Empty state
          if (docs.isEmpty) {
            return const _CenterNote('Sohbet bulunamadı.');
          }

          final int unreadChats = docs
              .where((doc) =>
                  ChatManager.getUnreadCountFromChatData(doc.data(), adminUid) >
                  0)
              .length;
          final List<String> queryWords = searchWordsOf(_searchQuery);
          final List<UserModel> otherCustomers = _otherMatchingCustomers(
            queryWords,
            {for (final doc in docs) doc.id},
          );
          final visibleDocs = docs.where((doc) {
            if (_unreadOnly &&
                ChatManager.getUnreadCountFromChatData(doc.data(), adminUid) ==
                    0) {
              return false;
            }
            if (queryWords.isEmpty) return true;
            return matchesSearchWords(
              queryWords,
              _searchWordsById[doc.id] ?? const [],
            );
          }).toList();

          // Track visible chat IDs so "select all" knows what to select.
          _visibleChatIds = visibleDocs.map((e) => e.id).toList();

          return Column(
            children: [
              _buildFilters(unreadChats),
              const Divider(height: 1),
              Expanded(
                child: visibleDocs.isEmpty && otherCustomers.isEmpty
                    ? _CenterNote(
                        queryWords.isEmpty ? _noUnreadText : _noMatchText)
                    : _buildChatList(visibleDocs, adminUid, otherCustomers),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Widget representing a single chat item in the admin chat list.
///
/// Solda danışanın baş harfleri, altında son mesaj (fotoğrafsa küçük
/// görseliyle, metni yoksa "Fotoğraf"), sağda saat ve okunmamış sayısı.
/// Silme, yanlışlıkla basılmasın diye satırın "⋮" menüsündedir ve onay ister.
class _ChatListItem extends StatelessWidget {
  final String chatId;

  /// Danışanın adı; henüz okunmadıysa null.
  final String? displayName;

  /// Avatardaki baş harfler; ad henüz okunmadıysa null.
  final String? initials;
  final String lastMsg;

  /// Son mesaj fotoğrafsa küçük görseli (yoksa orijinali); değilse null.
  final String? previewUrl;

  /// [previewUrl] küçük görsel değil, orijinal mi (eski özet).
  final bool previewIsOriginal;
  final String timeStr;
  final int unreadCount;

  final void Function(String chatId) onOpen;

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
    required this.displayName,
    required this.initials,
    required this.lastMsg,
    required this.previewUrl,
    required this.previewIsOriginal,
    required this.timeStr,
    required this.unreadCount,
    required this.onOpen,
    required this.onDelete,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelected,
    required this.onLongPressSelect,
  });

  static const String _loadingName = 'Yükleniyor…';
  static const String _photoText = 'Fotoğraf';
  static const String _menuTooltip = 'Diğer işlemler';
  static const String _deleteLabel = 'Sohbeti Sil';
  static const double _previewSize = 32;

  @override
  Widget build(BuildContext context) {
    final String? name = displayName;
    final ThemeData theme = Theme.of(context);
    final String? preview = previewUrl;
    final bool unread = unreadCount > 0;

    return ListTile(
      selected: selectionMode && selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      leading: selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelected(chatId),
            )
          : _InitialsAvatar(initials: initials),
      title: Text(
        name ?? _loadingName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: unread ? FontWeight.bold : FontWeight.w500,
          color: name == null ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Row(
        children: [
          if (preview != null) ...[
            // Liste kartlarının optimize görseli: küçük görsel iner, eski
            // özetlerde orijinal küçültülerek çözülür; indirmeler sıraya
            // girer (200 satır aynı anda indirmez).
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: _previewSize,
                height: _previewSize,
                child: MealThumbnailImage(
                  url: preview,
                  isOriginal: previewIsOriginal,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              lastMsg.isEmpty && preview != null ? _photoText : lastMsg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: unread
                  ? TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    )
                  : null,
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
                  color: unread ? Colors.green.shade700 : Colors.grey,
                  fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (unread) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          // Delete chat — admin only, onaylı. Hidden in bulk-select mode
          // (bulk delete lives in the app bar).
          if (!selectionMode)
            PopupMenuButton<_ChatRowAction>(
              tooltip: _menuTooltip,
              onSelected: (action) {
                switch (action) {
                  case _ChatRowAction.delete:
                    onDelete(chatId, name ?? chatId);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<_ChatRowAction>(
                  value: _ChatRowAction.delete,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      _deleteLabel,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      onLongPress: selectionMode ? null : () => onLongPressSelect(chatId),
      // Okundu işaretini sohbet sayfası açılınca kendisi koyar; burada
      // beklenirse sayfa geç (çevrimdışıyken hiç) açılır.
      onTap: selectionMode
          ? () => onToggleSelected(chatId)
          : () => onOpen(chatId),
    );
  }
}

/// Danışanın baş harfleriyle yuvarlak avatar; ad henüz okunmadıysa kişi
/// ikonu.
class _InitialsAvatar extends StatelessWidget {
  final String? initials;

  const _InitialsAvatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String? letters = initials;
    return CircleAvatar(
      backgroundColor: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
      child: letters == null
          ? const Icon(Icons.person)
          : Text(
              letters,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
    );
  }
}

/// Listedeki bölüm başlığı ("Listede olmayan danışanlar").
class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Text(
        text,
        style: theme.textTheme.labelLarge
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
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

  const _UserSelectionDialog({
    required this.userProvider,
  });

  @override
  State<_UserSelectionDialog> createState() => _UserSelectionDialogState();
}

class _UserSelectionDialogState extends State<_UserSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  
  List<UserModel> _allUsers = [];
  List<UserModel> _filteredUsers = [];

  /// Kullanıcı -> aramada karşılaştırılan kelimeler (önceden hesaplanır).
  final Map<String, List<String>> _searchWords = {};
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
    try {
      final users = await widget.userProvider.fetchAllCustomers();
      
      // Sort users by name for easier browsing (Türkçe harfler doğru yerde).
      users.sort((a, b) => compareSearchText(a.fullName, b.fullName));

      if (!mounted) return;

      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        for (final UserModel user in users) {
          _searchWords[user.userId] =
              searchWordsOf('${user.fullName} ${user.email}');
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Filter users based on search query.
  ///
  /// Ad soyad ve e-posta kelimelerinin başında aranır; Türkçe harfler
  /// katlanır ("i" yazan "İnci"yi de bulur, bkz. [searchWordsOf]).
  void _filterUsers(String query) {
    final List<String> queryWords = searchWordsOf(query);
    setState(() {
      _filteredUsers = queryWords.isEmpty
          ? _allUsers
          : _allUsers
              .where((user) => matchesSearchWords(
                    queryWords,
                    _searchWords[user.userId] ?? const [],
                  ))
              .toList();
    });
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
          leading: _InitialsAvatar(initials: user.initials),
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
            Navigator.of(context).pop(user.userId);
          },
        );
      },
    );
  }
}
