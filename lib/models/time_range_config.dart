import 'package:flutter/material.dart';

class TimeRangeConfig {
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int intervalMinutes;

  TimeRangeConfig({
    required this.startTime,
    required this.endTime,
    required this.intervalMinutes,
  });

  List<String> generateTimeSlots() {
    final List<String> slots = [];
    TimeOfDay currentTime = startTime;

    while (currentTime.hour < endTime.hour ||
        (currentTime.hour == endTime.hour &&
            currentTime.minute <= endTime.minute)) {
      slots.add(_formatTimeSlot(currentTime));
      currentTime = TimeOfDay(
        hour: currentTime.hour + (currentTime.minute + intervalMinutes) ~/ 60,
        minute: (currentTime.minute + intervalMinutes) % 60,
      );
    }

    return slots;
  }

  String _formatTimeSlot(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
