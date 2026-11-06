import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../pages/admin_notifications_page.dart';
import '../providers/admin_notifications_provider.dart';
import '../providers/meal_photo_notifications_provider.dart';
import 'labeled_action_button.dart';

class AdminNotificationBell extends StatelessWidget {
  const AdminNotificationBell({super.key});

  static const String _label = 'Bildirimler';

  @override
  Widget build(BuildContext context) {
    final AdminNotificationsProvider system =
        Provider.of<AdminNotificationsProvider>(context, listen: false);
    final MealPhotoNotificationsProvider chat =
        Provider.of<MealPhotoNotificationsProvider>(context, listen: false);
    return ListenableBuilder(
      listenable: Listenable.merge([system, chat]),
      builder: (context, _) {
        final int unread = system.unreadCount + chat.unreadCount;
        return LabeledActionButton(
          icon: unread > 0
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
          label: _label,
          tooltip: unread > 0 ? '$_label ($unread okunmamış)' : _label,
          badgeCount: unread,
          onPressed: () => openAdminNotificationCenter(context),
        );
      },
    );
  }
}
