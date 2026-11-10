import 'package:flutter/material.dart';

import '../models/admin_notification.dart';
import '../utils/date_formatter.dart';

class BloodTestReminderPreview extends StatelessWidget {
  const BloodTestReminderPreview({super.key, required this.testDate, this.now});

  final DateTime testDate;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final DateTime now = this.now ?? DateTime.now();
    final Map<BloodTestReminderStage, DateTime> plan =
        BloodTestReminderSchedule.plan(testDate, now);
    final bool alreadyDue =
        !plan[BloodTestReminderStage.dueDay]!.isAfter(now);

    String whenOf(BloodTestReminderStage stage) {
      final DateTime fireAt = plan[stage]!;
      final DateTime nominal =
          BloodTestReminderSchedule.fireTime(testDate, stage);
      return fireAt.isAfter(nominal)
          ? 'Hemen'
          : DateFormatter.formatLongDateTime(fireAt);
    }

    final List<String> lines = alreadyDue
        ? [
            'Bu tahlilin üzerinden 3 ay geçmiş. Hatırlatma yüklenince hemen '
                'Sistem bildirimlerine düşer.',
          ]
        : [
            if (plan.containsKey(BloodTestReminderStage.dayBefore))
              '${whenOf(BloodTestReminderStage.dayBefore)} · 3 ay dolmadan '
                  '1 gün önce',
            '${whenOf(BloodTestReminderStage.dueDay)} · 3 ay doluyor',
          ];

    final Color color = alreadyDue ? Colors.orange.shade800 : Colors.deepPurple;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            alreadyDue
                ? Icons.warning_amber_rounded
                : Icons.notifications_active_outlined,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!alreadyDue)
                  Text(
                    'Hatırlatmalar',
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                for (final String line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(line, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
