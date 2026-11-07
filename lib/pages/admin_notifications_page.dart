import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/admin_notification.dart';
import '../models/user_model.dart';
import '../providers/admin_notifications_provider.dart';
import '../providers/meal_photo_notifications_provider.dart';
import '../providers/user_provider.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../widgets/count_badge.dart';
import '../widgets/customer_chip.dart';
import '../widgets/labeled_action_button.dart';
import '../widgets/meal_thumbnail_image.dart';
import '../widgets/status_note.dart';
import 'chat_page_new.dart';
import 'customer_sum.dart';

enum AdminNotificationTab { chat, system }

const double _panelBreakpoint = 720;
const double _panelWidth = 440;
const double _panelMaxHeight = 680;

const Color _brandColor = Color(0xFFA16AEC);

ModalRoute<void>? _openCenterRoute;

final ValueNotifier<_TabRequest?> _tabRequests = ValueNotifier<_TabRequest?>(null);

class _TabRequest {
  const _TabRequest(this.tab);

  final AdminNotificationTab tab;
}

Future<void> openAdminNotificationCenter(
  BuildContext context, {
  AdminNotificationTab initialTab = AdminNotificationTab.chat,
  String? markReadId,
}) async {
  if (markReadId != null) {
    Provider.of<AdminNotificationsProvider>(context, listen: false)
        .markRead(markReadId)
        .catchError((Object e) {});
  }
  final ModalRoute<void>? open = _openCenterRoute;
  if (open != null && open.isActive && open.isCurrent) {
    _tabRequests.value = _TabRequest(initialTab);
    return;
  }
  final bool wide = MediaQuery.sizeOf(context).width >= _panelBreakpoint;
  final NavigatorState navigator = Navigator.of(context, rootNavigator: wide);
  final ModalRoute<void> route = wide
      ? RawDialogRoute<void>(
          barrierDismissible: true,
          barrierLabel: AdminNotificationCenter.closeLabel,
          barrierColor: Colors.black26,
          transitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (dialogContext, _, __) => SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, kToolbarHeight, 12, 16),
                child: _NotificationPanel(initialTab: initialTab),
              ),
            ),
          ),
          transitionBuilder: (context, animation, _, child) {
            final Animation<double> curved =
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                alignment: Alignment.topRight,
                child: child,
              ),
            );
          },
        )
      : MaterialPageRoute<void>(
          builder: (_) => AdminNotificationsPage(initialTab: initialTab),
        );
  _openCenterRoute = route;
  try {
    await navigator.push(route);
  } finally {
    if (identical(_openCenterRoute, route)) {
      _openCenterRoute = open != null && open.isActive ? open : null;
    }
  }
}

class AdminNotificationsPage extends StatelessWidget {
  final AdminNotificationTab initialTab;

  const AdminNotificationsPage({
    super.key,
    this.initialTab = AdminNotificationTab.chat,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AdminNotificationCenter.title),
        foregroundColor: Colors.white,
      ),
      body: AdminNotificationCenter(initialTab: initialTab),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  final AdminNotificationTab initialTab;

  const _NotificationPanel({required this.initialTab});

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double height = (size.height - kToolbarHeight - 40)
        .clamp(320.0, _panelMaxHeight)
        .toDouble();
    final double width =
        (size.width - 28).clamp(280.0, _panelWidth).toDouble();
    return Material(
      elevation: 16,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _PanelHeader(onClose: () => DialogUtils.closeOwnRoute(context)),
            Expanded(child: AdminNotificationCenter(initialTab: initialTab)),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _PanelHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final AdminNotificationsProvider system =
        Provider.of<AdminNotificationsProvider>(context, listen: false);
    final MealPhotoNotificationsProvider chat =
        Provider.of<MealPhotoNotificationsProvider>(context, listen: false);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8E54E9), _brandColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([system, chat]),
              builder: (context, _) {
                final int unread = system.unreadCount + chat.unreadCount;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      AdminNotificationCenter.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      unread == 0
                          ? AdminNotificationCenter.allReadText
                          : '$unread okunmamış bildirim',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            tooltip: AdminNotificationCenter.closeLabel,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class AdminNotificationCenter extends StatefulWidget {
  static const String title = 'Bildirimler';
  static const String closeLabel = 'Kapat';
  static const String allReadText = 'Hepsi okundu';

  final AdminNotificationTab initialTab;

  const AdminNotificationCenter({
    super.key,
    this.initialTab = AdminNotificationTab.chat,
  });

  @override
  State<AdminNotificationCenter> createState() =>
      _AdminNotificationCenterState();
}

class _AdminNotificationCenterState extends State<AdminNotificationCenter>
    with SingleTickerProviderStateMixin {
  static const String _chatTabLabel = 'Sohbet';
  static const String _systemTabLabel = 'Sistem';

  late final TabController _tabController;
  late final AdminNotificationsProvider _system;
  late final MealPhotoNotificationsProvider _chat;

  final Map<String, String> _names = {};
  final Set<String> _requestedNames = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: AdminNotificationTab.values.length,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _system = Provider.of<AdminNotificationsProvider>(context, listen: false);
    _chat = Provider.of<MealPhotoNotificationsProvider>(context, listen: false);
    _tabRequests.addListener(_onTabRequest);
    _loadNames();
  }

  @override
  void dispose() {
    _tabRequests.removeListener(_onTabRequest);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabRequest() {
    final _TabRequest? request = _tabRequests.value;
    if (request == null || ModalRoute.of(context)?.isCurrent != true) return;
    _tabController.animateTo(request.tab.index);
  }

  Future<void> _loadNames() async {
    final UserProvider userProvider =
        Provider.of<UserProvider>(context, listen: false);
    try {
      final List<UserModel> customers = await userProvider.fetchAllCustomers();
      if (!mounted) return;
      setState(() {
        for (final UserModel user in customers) {
          _names[user.userId] = _displayName(user);
          _requestedNames.add(user.userId);
        }
      });
    } catch (e) {
    }
  }

  void _ensureName(String userId) {
    if (!_requestedNames.add(userId)) return;
    Provider.of<UserProvider>(context, listen: false)
        .fetchUserDetails(userId: userId)
        .then((user) {
      if (!mounted || user == null) return;
      setState(() => _names[userId] = _displayName(user));
    }, onError: (Object e) {});
  }

  static String _displayName(UserModel user) =>
      user.fullName.isEmpty ? user.email : user.fullName;

  String? _nameOf(String userId) {
    final String? name = _names[userId];
    if (name == null) _ensureName(userId);
    return name;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: ListenableBuilder(
            listenable: Listenable.merge([_system, _chat]),
            builder: (context, _) => TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF5E35B1),
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: _brandColor,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: [
                _tab(Icons.chat_bubble_outline_rounded, _chatTabLabel,
                    _chat.unreadCount),
                _tab(Icons.notifications_none_rounded, _systemTabLabel,
                    _system.unreadCount),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ChatNotificationsList(provider: _chat, nameOf: _nameOf),
              _SystemNotificationsList(provider: _system),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tab(IconData icon, String label, int unread) {
    return Tab(
      height: 46,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
          if (unread > 0) ...[
            const SizedBox(width: 6),
            CountBadge(count: unread),
          ],
        ],
      ),
    );
  }
}

class _ListCaption extends StatelessWidget {
  final String text;
  final Widget? action;

  const _ListCaption({required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  final bool unread;

  const _UnreadDot({required this.unread});

  static const double _size = 10;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + 12,
      child: Center(
        child: unread
            ? Semantics(
                label: 'Okunmamış',
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.35),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final bool unread;
  final Widget leading;
  final String title;
  final String subtitle;
  final String time;
  final VoidCallback onTap;
  final Widget? footer;
  final Widget? trailing;
  final bool isTest;

  const _NotificationRow({
    super.key,
    required this.unread,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.onTap,
    this.footer,
    this.trailing,
    this.isTest = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: unread ? _brandColor.withValues(alpha: 0.07) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: _UnreadDot(unread: unread),
              ),
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                              color: unread
                                  ? Colors.black87
                                  : Colors.grey.shade800,
                            ),
                          ),
                        ),
                        if (isTest) ...[
                          const SizedBox(width: 6),
                          const _TestTag(),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                unread ? FontWeight.w700 : FontWeight.w400,
                            color: unread
                                ? const Color(0xFF5E35B1)
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: unread
                            ? Colors.grey.shade800
                            : Colors.grey.shade600,
                      ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: 8),
                      footer!,
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatNotificationsList extends StatefulWidget {
  final MealPhotoNotificationsProvider provider;
  final String? Function(String userId) nameOf;

  const _ChatNotificationsList({required this.provider, required this.nameOf});

  @override
  State<_ChatNotificationsList> createState() => _ChatNotificationsListState();
}

class _ChatNotificationsListState extends State<_ChatNotificationsList>
    with AutomaticKeepAliveClientMixin {
  static const String _caption = 'Bugün yüklenen öğün fotoğrafları';
  static const String _emptyText = 'Bugün henüz öğün fotoğrafı yüklenmedi.';
  static const String _errorText = 'Sohbet bildirimleri yüklenemedi.';
  static const String _unknownName = 'Danışan';

  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openChat(MealPhotoNotification item, String? name) async {
    await Navigator.of(context).push(ChatPage.route(
      overrideChatId: item.chatId,
      focusMessageId: item.messageId,
      userDisplayName: name,
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final MealPhotoNotificationsProvider provider = widget.provider;
        if (!provider.isLoaded) {
          return const StatusNote(showProgress: true, text: 'Yükleniyor...');
        }
        if (provider.hasError && provider.items.isEmpty) {
          return const StatusNote(
            icon: Icons.cloud_off_rounded,
            text: _errorText,
            isError: true,
          );
        }
        final List<MealPhotoNotification> items = provider.items;
        if (items.isEmpty) {
          return const StatusNote(
            icon: Icons.restaurant_menu_rounded,
            text: _emptyText,
          );
        }
        return Scrollbar(
          controller: _scrollController,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: items.length + 1,
            separatorBuilder: (_, index) => index == 0
                ? const SizedBox.shrink()
                : const Divider(height: 1, indent: 82),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _ListCaption(text: '$_caption (${items.length})');
              }
              final MealPhotoNotification item = items[index - 1];
              final String? name = widget.nameOf(item.chatId);
              final String? meal = item.mealLabel;
              return _NotificationRow(
                unread: !item.isRead,
                leading: _MealPhotoThumb(item: item),
                title: name ?? _unknownName,
                subtitle: meal == null
                    ? 'Öğün fotoğrafı yükledi'
                    : '$meal öğününün fotoğrafını yükledi',
                time: DateFormatter.formatTime(item.sentAt),
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Icon(Icons.chevron_right_rounded,
                      color: Colors.grey.shade400),
                ),
                onTap: () => _openChat(item, name),
              );
            },
          ),
        );
      },
    );
  }
}

class _MealPhotoThumb extends StatelessWidget {
  final MealPhotoNotification item;

  const _MealPhotoThumb({required this.item});

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: MealThumbnailImage(
        url: item.imageUrl,
        isOriginal: item.imageIsOriginal,
      ),
    );
  }
}

enum _Section {
  today('Bugün'),
  yesterday('Dün'),
  thisWeek('Bu Hafta'),
  older('Daha Eski');

  const _Section(this.label);

  final String label;

  static _Section of(DateTime fireAt, DateTime now) {
    final int daysAgo = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(fireAt.year, fireAt.month, fireAt.day))
        .inDays;
    if (daysAgo <= 0) return today;
    if (daysAgo == 1) return yesterday;
    if (daysAgo < 7) return thisWeek;
    return older;
  }
}

class _SystemNotificationsList extends StatefulWidget {
  final AdminNotificationsProvider provider;

  const _SystemNotificationsList({required this.provider});

  @override
  State<_SystemNotificationsList> createState() =>
      _SystemNotificationsListState();
}

class _SystemNotificationsListState extends State<_SystemNotificationsList>
    with AutomaticKeepAliveClientMixin {
  static const String _emptyText =
      'Sistem bildirimi yok. Kan tahlili hatırlatmaları ve günlük eksik '
      'tahlil listesi burada görünür.';
  static const String _errorText = 'Sistem bildirimleri yüklenemedi.';
  static const String _markAllLabel = 'Tümünü okundu say';
  static const String _loadOlderLabel = 'Daha eski bildirimleri göster';
  static const String _openCustomerLabel = 'Danışanı aç';
  static final DateFormat _weekdayTimeFormat =
      DateFormat('EEEE HH:mm', 'tr_TR');

  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markRead(AdminNotification notification) async {
    try {
      await widget.provider.markRead(notification.id);
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Bildirim okundu olarak işaretlenemedi: $e',
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      await widget.provider.markAllRead();
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Bildirimler okundu olarak işaretlenemedi: $e',
      );
    }
  }

  Future<void> _openCustomer(String userId, String name) async {
    await openCustomerSummaryById(context, userId: userId, displayName: name);
  }

  Future<void> _loadOlder() async {
    try {
      await widget.provider.loadOlder();
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Eski bildirimler yüklenemedi: $e',
      );
    }
  }

  String _timeLabel(DateTime fireAt, _Section section) {
    switch (section) {
      case _Section.today:
      case _Section.yesterday:
        return DateFormatter.formatTime(fireAt);
      case _Section.thisWeek:
        return _weekdayTimeFormat.format(fireAt);
      case _Section.older:
        return DateFormatter.formatNumericDate(fireAt);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final AdminNotificationsProvider provider = widget.provider;
        if (!provider.isLoaded) {
          return const StatusNote(showProgress: true, text: 'Yükleniyor...');
        }
        if (provider.hasError && provider.notifications.isEmpty) {
          return const StatusNote(
            icon: Icons.cloud_off_rounded,
            text: _errorText,
            isError: true,
          );
        }
        final List<AdminNotification> notifications = provider.notifications;
        if (notifications.isEmpty) {
          return const StatusNote(
            icon: Icons.notifications_off_outlined,
            text: _emptyText,
          );
        }

        final DateTime now = DateTime.now();
        final List<Widget> rows = [
          _ListCaption(
            text: provider.unreadCount == 0
                ? AdminNotificationCenter.allReadText
                : '${provider.unreadCount} okunmamış',
            action: provider.unreadCount == 0
                ? null
                : LabeledActionButton(
                    dense: true,
                    icon: Icons.done_all_rounded,
                    label: _markAllLabel,
                    foregroundColor: const Color(0xFF5E35B1),
                    onPressed: _markAllRead,
                  ),
          ),
        ];
        _Section? current;
        for (final AdminNotification notification in notifications) {
          final _Section section = _Section.of(notification.fireAt, now);
          if (section != current) {
            current = section;
            rows.add(_SectionHeader(label: section.label));
          }
          rows.add(_buildRow(
            notification,
            unread: !provider.isRead(notification),
            time: _timeLabel(notification.fireAt, section),
          ));
        }
        if (provider.canLoadOlder || provider.isLoadingOlder) {
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: provider.isLoadingOlder
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : LabeledActionButton(
                      dense: true,
                      icon: Icons.history_rounded,
                      label: _loadOlderLabel,
                      foregroundColor: const Color(0xFF5E35B1),
                      onPressed: _loadOlder,
                    ),
            ),
          ));
        }

        return Scrollbar(
          controller: _scrollController,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 12),
            children: rows,
          ),
        );
      },
    );
  }

  Widget _buildRow(
    AdminNotification notification, {
    required bool unread,
    required String time,
  }) {
    switch (notification.type) {
      case AdminNotificationType.bloodTestReminder:
        final String? userId = notification.userId;
        final String name = notification.userName ?? 'Danışan';
        return _NotificationRow(
          key: ValueKey<String>(notification.id),
          unread: unread,
          leading: _SystemIcon(
            icon: Icons.bloodtype_rounded,
            color: notification.stage == BloodTestReminderStage.dueDay
                ? Colors.red.shade600
                : Colors.orange.shade700,
          ),
          title: notification.title,
          subtitle: notification.body,
          time: time,
          isTest: notification.isTest,
          onTap: () => _markRead(notification),
          footer: userId == null
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: CustomerChip(
                    label: _openCustomerLabel,
                    onPressed: () => _openCustomer(userId, name),
                  ),
                ),
        );
      case AdminNotificationType.missingBloodTests:
        return _MissingBloodTestsRow(
          key: ValueKey<String>(notification.id),
          notification: notification,
          unread: unread,
          time: time,
          onTap: () => _markRead(notification),
          onCustomerTap: (customer) =>
              _openCustomer(customer.userId, customer.name),
        );
      case AdminNotificationType.test:
        return _NotificationRow(
          key: ValueKey<String>(notification.id),
          unread: unread,
          leading: _SystemIcon(
            icon: Icons.science_rounded,
            color: Colors.blue.shade600,
          ),
          title: notification.title,
          subtitle: notification.body,
          time: time,
          isTest: notification.isTest,
          onTap: () => _markRead(notification),
        );
    }
  }
}

class _TestTag extends StatelessWidget {
  const _TestTag();

  static const String _label = 'DENEME';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w800,
          color: Colors.blue.shade700,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }
}

class _SystemIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SystemIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

class _MissingBloodTestsRow extends StatefulWidget {
  final AdminNotification notification;
  final bool unread;
  final String time;
  final VoidCallback onTap;
  final ValueChanged<NotificationCustomer> onCustomerTap;

  const _MissingBloodTestsRow({
    super.key,
    required this.notification,
    required this.unread,
    required this.time,
    required this.onTap,
    required this.onCustomerTap,
  });

  @override
  State<_MissingBloodTestsRow> createState() => _MissingBloodTestsRowState();
}

class _MissingBloodTestsRowState extends State<_MissingBloodTestsRow> {
  static const int _collapsedCount = 6;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final List<NotificationCustomer> customers =
        widget.notification.customers;
    final bool canCollapse = customers.length > _collapsedCount;
    final List<NotificationCustomer> shown = _expanded || !canCollapse
        ? customers
        : customers.take(_collapsedCount).toList();
    final int hidden = customers.length - shown.length;

    return _NotificationRow(
      unread: widget.unread,
      leading: _SystemIcon(
        icon: Icons.assignment_late_rounded,
        color: Colors.deepPurple.shade400,
      ),
      title: widget.notification.title,
      subtitle: '${customers.length} danışanın kan tahlili sisteme girilmemiş '
          '(eklenmesinin üzerinden 1 hafta geçmiş).',
      time: widget.time,
      isTest: widget.notification.isTest,
      onTap: () {
        widget.onTap();
        if (canCollapse) setState(() => _expanded = !_expanded);
      },
      footer: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final NotificationCustomer customer in shown)
            CustomerChip(
              label: customer.name,
              onPressed: () => widget.onCustomerTap(customer),
            ),
          if (hidden > 0)
            ActionChip(
              label: Text('+$hidden daha'),
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.deepPurple.shade400,
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: Colors.deepPurple.shade50,
              side: BorderSide.none,
              onPressed: () => setState(() => _expanded = true),
            ),
        ],
      ),
    );
  }
}
