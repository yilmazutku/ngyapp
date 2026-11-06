import 'package:flutter/material.dart';

import '../models/appointment_color_palette.dart';
import '../models/summary_color_config.dart';
import '../models/user_model.dart';
import '../utils/birthdays.dart';

const double kBirthdayChipHeight = 20.0;
const double kBirthdayChipGap = 3.0;
const String kBirthdayPrefix = 'DG: ';

class BirthdayChip extends StatelessWidget {
  const BirthdayChip({super.key, required this.user, required this.day});

  final UserModel user;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final Color background =
        AppointmentColorsRegistry.colorFor(AppointmentColorSlot.birthday);
    final Color foreground =
        SummaryColorsRegistry.readableTextColor(background);
    final DateTime? birthDate = user.birthDate;
    final String tooltip = birthDate == null
        ? 'Doğum günü: ${user.fullName}'
        : 'Doğum günü: ${user.fullName} '
            '(${BirthdayIndex.ageOn(birthDate, day)} yaşına giriyor)';

    return Tooltip(
      message: tooltip,
      child: Container(
        height: kBirthdayChipHeight,
        margin: const EdgeInsets.only(top: kBirthdayChipGap),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: background.withValues(alpha: 0.45),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cake_rounded, size: 13, color: foreground),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$kBirthdayPrefix${user.fullName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
