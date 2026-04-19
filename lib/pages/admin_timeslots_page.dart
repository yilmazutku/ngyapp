import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../dialogs/edit_appointment_dialog.dart';
import '../models/logger.dart';
import '../models/appointment_model.dart';
import '../models/event_model.dart';
import '../providers/timeslot_manager.dart';
import '../utils/dialog_utils.dart';
import '../models/time_range_config.dart';
import '../widgets/app_bar_with_back.dart';

final Logger logger = Logger.forClass(AdminTimeSlotsPage);

class AdminTimeSlotsPage extends StatefulWidget {
  const AdminTimeSlotsPage({super.key});

  @override
  createState() => _AdminTimeSlotsPageState();
}

class _AdminTimeSlotsPageState extends State<AdminTimeSlotsPage> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _showCalendar = true;

  /// Configurable day start/end used by interval generation and manual selection.
  TimeOfDay _dayStartTime = const TimeOfDay(hour: 9, minute: 30);
  TimeOfDay _dayEndTime = const TimeOfDay(hour: 18, minute: 30);

  /// What’s stored in Firebase for the selected day.
  List<String> _storedTimesForDay = [];

  /// Which times have appointments on them.
  final Map<String, bool> _hasAppointment = {};
  Map<String, List<AppointmentModel>> _appointmentsBySlot = {};
  Map<String, List<EventModel>> _eventsBySlot = {};


  /// Hoisted formatters
  static final DateFormat _dayTitleFmt = DateFormat('dd MMMM yyyy', 'tr_TR');
  static final DateFormat _docKeyFmt = DateFormat('yyyy-MM-dd');

  /// Scrolling
  late final ScrollController _verticalCtrl;
  static const _kVerticalKey = PageStorageKey('admin_timeslots_vertical');


  @override
  void initState() {
    super.initState();
    _verticalCtrl = ScrollController();
    _fetchDayData(_selectedDate);
  }

  @override
  void dispose() {
    _verticalCtrl.dispose();
    super.dispose();
  }

  /// Whenever a date is selected, fetch data
  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (_sameYMD(_selectedDate, selectedDay)) return; // no-op if unchanged
    setState(() {
      _selectedDate = selectedDay;
    });
    _fetchDayData(_selectedDate);
  }

  /// Format time slot for display
  String _formatTimeSlot(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  /// Parse "HH:mm" to TimeOfDay
  TimeOfDay? _parseTimeSlot(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length != 2) return null;
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  /// HH:mm → minutes since midnight
  int _minutesFromHHmm(String hhmm) {
    final p = hhmm.split(':');
    final h = int.parse(p[0]);
    final m = int.parse(p[1]);
    return h * 60 + m;
  }

  /// Sort helper (stable chronological)
  void _sortSlotsChronologically(List<String> list) {
    list.sort((a, b) => _minutesFromHHmm(a).compareTo(_minutesFromHHmm(b)));
  }

  /// Validate time slot format
  bool _isValidTimeSlot(String timeStr) => _parseTimeSlot(timeStr) != null;

  bool _sameYMD(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;


  Future<void> _fetchDayData(DateTime date) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final timeslotManager =
      Provider.of<TimeslotManager>(context, listen: false);

      final data = await timeslotManager.fetchTimeslotDataForDate(date);

      final storedTimes = (data['storedTimes'] as List)
          .map((e) => e.toString())
          .toList();

      final rawHasAppt = data['hasAppointment'] as Map;
      final hasAppt = <String, bool>{};
      rawHasAppt.forEach((key, value) {
        hasAppt[key.toString()] = value as bool;
      });

      final rawAppointmentsBySlot = data['appointmentsBySlot'] as Map?;
      final appointmentsBySlot = <String, List<AppointmentModel>>{};
      (rawAppointmentsBySlot ?? {}).forEach((key, value) {
        appointmentsBySlot[key.toString()] =
        List<AppointmentModel>.from(value as List);
      });

      final rawEventsBySlot = data['eventsBySlot'] as Map?;
      final eventsBySlot = <String, List<EventModel>>{};
      (rawEventsBySlot ?? {}).forEach((key, value) {
        eventsBySlot[key.toString()] =
            List<EventModel>.from(value as List);
      });

      if (!mounted) return;
      setState(() {
        _storedTimesForDay = storedTimes;
        _hasAppointment
          ..clear()
          ..addAll(hasAppt);
        _appointmentsBySlot = appointmentsBySlot;
        _eventsBySlot = eventsBySlot;
        _isLoading = false;
      });
    } catch (e) {
      logger.err('Error fetching day data: {}', [e]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Veri yüklenirken hata oluştu: $e',
      );
      setState(() {
        _isLoading = false;
      });
    }
  }


  /// Show custom time input dialog
  Future<TimeOfDay?> _showCustomTimeInputDialog(TimeOfDay initialTime) async {
    final controller = TextEditingController(
      text: _formatTimeSlot(initialTime),
    );

    return showDialog<TimeOfDay>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Saat Seç'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'HH:mm',
                  border: OutlineInputBorder(),
                  helperText: 'Örnek: 09:30',
                ),
                keyboardType: TextInputType.datetime,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final TimeOfDay? picked =
                      await showTimePicker(context: context, initialTime: initialTime);
                      if (picked != null) {
                        controller.text = _formatTimeSlot(picked);
                      }
                    },
                    icon: const Icon(Icons.access_time),
                    label: const Text('Saat Seçici'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () {
                final parts = controller.text.split(':');
                if (parts.length == 2) {
                  try {
                    final hour = int.parse(parts[0]);
                    final minute = int.parse(parts[1]);
                    if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
                      Navigator.pop(context, TimeOfDay(hour: hour, minute: minute));
                      return;
                    }
                  } catch (_) {}
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Geçersiz saat formatı'), backgroundColor: Colors.red),
                );
              },
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }

  /// Show dialog to configure time ranges
  Future<void> _showTimeRangeConfigDialog() async {
    TimeOfDay startTime = _dayStartTime;
    TimeOfDay endTime = _dayEndTime;
    final intervalController = TextEditingController(text: '30');

    try {
      return await showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (builderContext, setState) {
              final previewSlots = () {
                final interval = int.tryParse(intervalController.text) ?? 30;
                final timeConfig = TimeRangeConfig(
                  startTime: startTime,
                  endTime: endTime,
                  intervalMinutes: interval,
                );
                return timeConfig.generateTimeSlots();
              }();

              return AlertDialog(
                title: const Text('Zaman Aralığı Yapılandırması'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTimeRangePicker(
                        startTime: startTime,
                        endTime: endTime,
                        onStartTimeChanged: (t) => setState(() => startTime = t),
                        onEndTimeChanged: (t) => setState(() => endTime = t),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: TextField(
                          controller: intervalController,
                          decoration: const InputDecoration(
                            labelText: 'Aralık (dakika)',
                            hintText: '30',
                            border: OutlineInputBorder(),
                            helperText: 'Örnek: 30 dakika',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const Divider(),
                      const Text('Önizleme', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _buildTimeSlotPreview(previewSlots),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('İptal')),
                  ElevatedButton(
                    onPressed: () async {
                      final interval = int.tryParse(intervalController.text) ?? 30;
                      if (interval < 5) {
                        if (!mounted) return;
                        await DialogUtils.openError(
                          builderContext,
                          title: 'Hata',
                          message: 'Aralık en az 5 dakika olmalıdır.',
                        );
                        return;
                      }

                      final config = TimeRangeConfig(
                        startTime: startTime,
                        endTime: endTime,
                        intervalMinutes: interval,
                      );
                      final slots = config.generateTimeSlots();

                      Navigator.of(dialogContext).pop(); // close dialog first
                      if (!mounted) return;

                      // Pull fresh data once
                      final latestData = await _fetchLatestTimeSlotData();
                      final storedTimes =
                      (latestData['storedTimes'] as List<dynamic>).map((e) => e.toString()).toList();
                      final bookedTimeSlots = latestData['bookedTimeSlots'] as List<String>;

                      if (bookedTimeSlots.isNotEmpty) {
                        if (!mounted) return;
                        final proceed = await DialogUtils.openConfirm(
                          context,
                          title: 'Bilgi',
                          message:
                          'Aşağıdaki zaman dilimlerinde randevu bulunmakta. Bu dilimler otomatik olarak eklenecek:\n${bookedTimeSlots.join(", ")}\n\nDevam etmek istiyor musunuz?',
                        );
                        if (!proceed) return;
                      }

                      final slotsToAdd = slots.where((s) => !storedTimes.contains(s)).toList();
                      for (final booked in bookedTimeSlots) {
                        if (!storedTimes.contains(booked) && !slotsToAdd.contains(booked)) {
                          slotsToAdd.add(booked);
                        }
                      }

                      final allSlots = [...storedTimes, ...slotsToAdd];
                      _sortSlotsChronologically(allSlots);

                      try {
                        final success = await _saveTimeSlotsWithErrorHandling(allSlots);
                        if (success && mounted) {
                          await _fetchDayData(_selectedDate);
                        }
                      } catch (e) {
                        logger.err('Error in saving timeslots: {}', [e]);
                        if (mounted) {
                          await DialogUtils.openError(
                            context,
                            title: 'Hata',
                            message: 'Zaman dilimleri kaydedilemedi: ${e.toString()}',
                          );
                        }
                      }
                    },
                    child: const Text('Kaydet'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      intervalController.dispose();
    }
  }




  /// Fetch most recent time slot data from the database without UI update
  Future<Map<String, dynamic>> _fetchLatestTimeSlotData() async {
    try {
      final timeslotManager =
      Provider.of<TimeslotManager>(context, listen: false);
      return await timeslotManager.fetchTimeslotDataForDate(_selectedDate);
    } catch (e) {
      logger.err('Error fetching latest time slot data: {}', [e]);
      return {
        'storedTimes': <String>[],
        'hasAppointment': <String, bool>{},
        'bookedTimeSlots': <String>[],
        'appointmentsBySlot': <String, List<AppointmentModel>>{},
      };
    }
  }



  /// Shows a dialog with an error message
  Future<void> _showErrorDialog(String title, String message) async {
    if (!mounted) return;
    await DialogUtils.openError(context, title: title, message: message);
  }

  /// Validates time slots for duplication within the input
  List<String> _checkForDuplicatesInInput(List<String> timeSlots) {
    final seen = <String, int>{};
    for (final s in timeSlots) {
      seen[s] = (seen[s] ?? 0) + 1;
    }
    return seen.entries.where((e) => e.value > 1).map((e) => e.key).toList();
  }

  /// Validates time slots against existing data and bookings
  Future<Map<String, List<String>>> _validateTimeSlots(
      List<String> timeSlots, {
        String? currentEditingTime,
        bool checkExisting = true,
        bool checkBookings = true,
      }) async {
    final latestData = await _fetchLatestTimeSlotData();
    final storedTimes = (latestData['storedTimes'] as List<dynamic>).map((e) => e.toString()).toList();
    final rawHasAppointment = latestData['hasAppointment'] as Map;
    final hasAppointment = <String, bool>{};
    rawHasAppointment.forEach((key, value) {
      hasAppointment[key.toString()] = value as bool;
    });


    final Map<String, List<String>> result = {
      'existingSlots': [],
      'bookedSlots': [],
      'invalidSlots': [],
    };

    result['invalidSlots'] = timeSlots.where((slot) {
      final t = _parseTimeSlot(slot);
      return t == null;
    }).toList();

    if (checkExisting) {
      result['existingSlots'] = timeSlots.where((slot) {
        if (currentEditingTime != null && slot == currentEditingTime) return false;
        return storedTimes.contains(slot);
      }).toList();
    }

    if (checkBookings) {
      result['bookedSlots'] = timeSlots.where((slot) => hasAppointment[slot] == true).toList();
    }

    return result;
  }

  /// Save time slots with error handling
  Future<bool> _saveTimeSlotsWithErrorHandling(List<String> timeSlots) async {
    try {
      final timeslotManager =
      Provider.of<TimeslotManager>(context, listen: false);

      // unique + sorted
      final unique = {...timeSlots}.toList();
      _sortSlotsChronologically(unique);

      await timeslotManager.updateTimeSlots(_selectedDate, unique);

      if (mounted) {
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Zaman dilimleri başarıyla kaydedildi.',
        );
      }
      return true;
    } catch (e) {
      logger.err('Error in saving timeslots. {}', [e]);
      await _showErrorDialog(
        'Hata',
        'Zaman dilimleri kaydedilemedi. Lütfen destek talep ediniz.',
      );
      return false;
    }
  }



  /// Show dialog to add/edit time slots (manual entry)
  Future<void> _showTimeSlotDialog() async {
    final tempController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Zaman Dilimleri'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Zamanları virgülle ayırarak giriniz (örn: 09:00, 09:30, 10:00)',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tempController,
                decoration: const InputDecoration(
                  hintText: '09:00, 09:30, 10:00',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                final newTimeSlots = tempController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => _isValidTimeSlot(e))
                    .toList();

                if (newTimeSlots.isEmpty) {
                  if (!mounted) return;
                  await DialogUtils.openError(context, title: 'Hata', message: 'Lütfen geçerli bir zaman giriniz.');
                  return;
                }

                final duplicates = _checkForDuplicatesInInput(newTimeSlots);
                if (duplicates.isNotEmpty) {
                  if (!mounted) return;
                  await DialogUtils.openError(
                    context,
                    title: 'Hata',
                    message: 'Aşağıdaki zaman dilimleri tekrar ediyor:\n${duplicates.join(", ")}',
                  );
                  return;
                }

                final latestData = await _fetchLatestTimeSlotData();
                final storedTimes =
                (latestData['storedTimes'] as List<dynamic>).map((e) => e.toString()).toList();
                final rawHasAppointment = latestData['hasAppointment'] as Map;
                final hasAppointment = <String, bool>{};
                rawHasAppointment.forEach((key, value) {
                  hasAppointment[key.toString()] = value as bool;
                });


                final existingSlots = newTimeSlots.where((s) => storedTimes.contains(s)).toList();
                if (existingSlots.isNotEmpty) {
                  if (!mounted) return;
                  await DialogUtils.openError(
                    context,
                    title: 'Hata',
                    message: 'Aşağıdaki zaman dilimleri zaten mevcut:\n${existingSlots.join(", ")}',
                  );
                  return;
                }

                final bookedSlots = newTimeSlots.where((s) {
                  return hasAppointment[s] == true;
                }).toList();

                if (bookedSlots.isNotEmpty) {
                  if (!mounted) return;
                  await DialogUtils.openError(
                    context,
                    title: 'Hata',
                    message: 'Aşağıdaki zaman dilimleri randevu alınmış:\n${bookedSlots.join(", ")}',
                  );
                  return;
                }

                try {
                  final updated = [...storedTimes, ...newTimeSlots];
                  _sortSlotsChronologically(updated);
                  final success = await _saveTimeSlotsWithErrorHandling(updated);
                  if (success && mounted) {
                    await _fetchDayData(_selectedDate);
                  }
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                } catch (e) {
                  logger.err('Error in saving timeslots. {}', [e]);
                  if (!mounted) return;
                  await DialogUtils.openError(
                    context,
                    title: 'Hata',
                    message: 'Zaman dilimleri kaydedilemedi. Lütfen destek talep ediniz.',
                  );
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  /// Show dialog to edit a time slot
  Future<void> _showEditTimeSlotDialog(String currentTime) async {
    final controller = TextEditingController(text: currentTime);

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Zaman Dilimi Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'HH:mm', border: OutlineInputBorder()),
                keyboardType: TextInputType.datetime,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                final newTime = controller.text.trim();

                if (!_isValidTimeSlot(newTime)) {
                  await _showErrorDialog('Hata', 'Geçersiz zaman formatı. Lütfen girdiğiniz zamanı kontrol ediniz.');
                  return;
                }
                if (newTime == currentTime) {
                  Navigator.pop(context);
                  return;
                }

                final validation = await _validateTimeSlots([newTime], currentEditingTime: currentTime);

                if (validation['invalidSlots']!.isNotEmpty) {
                  await _showErrorDialog('Hata',
                      'Girdiğiniz zaman geçersiz saat formatında.');
                  return;
                }
                if (validation['existingSlots']!.isNotEmpty) {
                  await _showErrorDialog('Hata', 'Bu zaman dilimi zaten mevcut. Lütfen başka bir zaman seçiniz.');
                  return;
                }
                if (validation['bookedSlots']!.isNotEmpty) {
                  await _showErrorDialog('Hata', 'Bu zaman diliminde randevu bulunmakta. Lütfen başka bir zaman seçiniz.');
                  return;
                }

                final latestData = await _fetchLatestTimeSlotData();
                final storedTimes =
                (latestData['storedTimes'] as List<dynamic>).map((e) => e.toString()).toList();

                final updated = List<String>.from(storedTimes);
                final idx = updated.indexOf(currentTime);
                if (idx != -1) {
                  updated[idx] = newTime;
                  _sortSlotsChronologically(updated);
                  final success = await _saveTimeSlotsWithErrorHandling(updated);
                  if (success && mounted) Navigator.pop(context);
                } else {
                  await _showErrorDialog(
                    'Hata',
                    'Düzenlemek istediğiniz zaman dilimi bulunamadı. Sayfayı yenileyip tekrar deneyin.',
                  );
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  /// Show dialog to confirm deletion
  Future<void> _showDeleteConfirmationDialog(String time) async {
    return showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Zaman Dilimi Sil'),
          content: Text('$time zaman dilimini silmek istediğinize emin misiniz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                final latestData = await _fetchLatestTimeSlotData();
                final storedTimes =
                (latestData['storedTimes'] as List<dynamic>).map((e) => e.toString()).toList();
                final rawHasAppointment = latestData['hasAppointment'] as Map;
                final hasAppointment = <String, bool>{};
                rawHasAppointment.forEach((key, value) {
                  hasAppointment[key.toString()] = value as bool;
                });

                if (hasAppointment[time] == true) {
                  await _showErrorDialog(
                      'Hata', 'Bu zaman diliminde randevu bulunmakta. Önce randevuyu iptal etmeniz gerekiyor.');
                  return;
                }

                // Close the confirmation dialog first
                Navigator.pop(dialogContext);

                final updated = List<String>.from(storedTimes)..remove(time);
                // Save silently (without success dialog) for delete operations
                final success = await _saveTimeslotsSilently(updated);
                if (success && mounted) {
                  await _fetchDayData(_selectedDate);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
  }

  /// Save time slots silently (without showing success dialog) - used for delete operations
  Future<bool> _saveTimeslotsSilently(List<String> timeSlots) async {
    try {
      final timeslotManager =
          Provider.of<TimeslotManager>(context, listen: false);

      // unique + sorted
      final unique = {...timeSlots}.toList();
      _sortSlotsChronologically(unique);

      await timeslotManager.updateTimeSlots(_selectedDate, unique);
      return true;
    } catch (e) {
      logger.err('Error in saving timeslots. {}', [e]);
      if (mounted) {
        await _showErrorDialog(
          'Hata',
          'Zaman dilimleri kaydedilemedi. Lütfen destek talep ediniz.',
        );
      }
      return false;
    }
  }

  /// Show appointment details for a time slot
  Future<void> _showAppointmentDetails(String timeStr) async {
    final time = _parseTimeSlot(timeStr);
    if (time == null) return;

    final slotAppointments = _appointmentsBySlot[timeStr] ?? [];
    if (slotAppointments.isEmpty) {
      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Bilgi',
        message: 'Bu zaman diliminde randevu bulunamadı.',
      );
      return;
    }

    final appointment = slotAppointments.first;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) {
        return EditAppointmentDialog(
          appointment: appointment,
          onAppointmentUpdated: () async {
            await _fetchDayData(_selectedDate);
          },
        );
      },
    );
  }



  /// Build the time slots section with appointment info
  Widget _buildTimeSlotsSection() {
    if (_storedTimesForDay.isEmpty) {
      return const Center(child: Text('Bu tarih için zaman dilimi bulunmuyor'));
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(), // vertical scroll handled by parent
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.8,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _storedTimesForDay.length,
      itemBuilder: (context, index) => _buildTimeSlotItem(_storedTimesForDay[index]),
    );
  }

  /// Build individual time slot item
  String _formatEndTime(AppointmentModel appt) {
    final end = appt.appointmentDateTime
        .add(Duration(minutes: appt.durationMinutes));
    return '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  }

  String _formatStartTime(AppointmentModel appt) {
    final dt = appt.appointmentDateTime;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTimeSlotItem(String timeStr) {
    final hasAppt = _hasAppointment[timeStr] ?? false;
    final slotAppointments = _appointmentsBySlot[timeStr] ?? [];
    final slotEvents = _eventsBySlot[timeStr] ?? [];
    final isMobile = MediaQuery.of(context).size.shortestSide < 600;
    final baseFontSize = isMobile ? 14.0 : 16.0;

    final bool hasEvent = slotEvents.isNotEmpty;
    final Color cardColor = hasEvent
        ? Colors.deepPurple.shade50
        : hasAppt
            ? Colors.red[50]!
            : Colors.green[50]!;

    // Determine what label/details to show
    String? detailName;
    String? detailTimeRange;
    Color detailColor = Colors.red;

    if (hasEvent) {
      final e = slotEvents.first;
      detailName = e.name;
      final endStr =
          '${e.endDateTime.hour.toString().padLeft(2, '0')}:${e.endDateTime.minute.toString().padLeft(2, '0')}';
      final startStr =
          '${e.startDateTime.hour.toString().padLeft(2, '0')}:${e.startDateTime.minute.toString().padLeft(2, '0')}';
      detailTimeRange = '$startStr-$endStr';
      detailColor = Colors.deepPurple;
    } else if (slotAppointments.isNotEmpty) {
      final a = slotAppointments.first;
      detailName =
          '${a.user?.name ?? ''} ${a.user?.surname ?? ''}'.trim();
      detailTimeRange =
          '${_formatStartTime(a)}-${_formatEndTime(a)}';
    }

    return Card(
      elevation: 2,
      color: cardColor,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(timeStr,
                    style: TextStyle(
                        fontSize: baseFontSize,
                        fontWeight: FontWeight.bold)),
                if (hasAppt) ...[
                  const SizedBox(height: 2),
                  Text('Dolu',
                      style: TextStyle(
                          fontSize: baseFontSize - 4,
                          color: detailColor,
                          fontWeight: FontWeight.w600)),
                  if (!isMobile && detailName != null && detailName.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      detailName,
                      style: TextStyle(
                          fontSize: baseFontSize - 4,
                          color: detailColor,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (detailTimeRange != null)
                      Text(
                        detailTimeRange,
                        style: TextStyle(
                            fontSize: baseFontSize - 5,
                            color: detailColor.withValues(alpha: 0.7)),
                      ),
                  ],
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                  onTap: () =>
                      hasAppt ? _showAppointmentDetails(timeStr) : null),
            ),
          ),
          if (!hasAppt)
            Positioned(
              right: 0,
              top: 0,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 16),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditTimeSlotDialog(timeStr);
                  } else if (value == 'delete') {
                    _showDeleteConfirmationDialog(timeStr);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Show dialog that lets the admin configure the day start/end time.
  Future<void> _showDayTimeRangeDialog() async {
    TimeOfDay tempStart = _dayStartTime;
    TimeOfDay tempEnd = _dayEndTime;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            final startMinutes = tempStart.hour * 60 + tempStart.minute;
            final endMinutes = tempEnd.hour * 60 + tempEnd.minute;
            final isValid = endMinutes > startMinutes;

            return AlertDialog(
              title: const Text('Gün Saat Aralığı'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Aralıklı oluşturma ve elle seçme işlemlerinde kullanılacak günün başlangıç ve bitiş saatini belirleyin.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _buildTimeRangePicker(
                    startTime: tempStart,
                    endTime: tempEnd,
                    onStartTimeChanged: (t) =>
                        setDialogState(() => tempStart = t),
                    onEndTimeChanged: (t) =>
                        setDialogState(() => tempEnd = t),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isValid ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isValid ? Colors.green : Colors.red,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isValid ? Icons.check_circle : Icons.error,
                          color: isValid ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isValid
                                ? '${_formatTimeSlot(tempStart)} – ${_formatTimeSlot(tempEnd)}'
                                : 'Bitiş saati başlangıçtan sonra olmalıdır.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isValid
                                  ? Colors.green[800]
                                  : Colors.red[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: isValid
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() {
        _dayStartTime = tempStart;
        _dayEndTime = tempEnd;
      });
    }
  }

  /// Show dialog to select time range for interval generation
  Future<void> _showIntervalTimeRangeDialog(int intervalMinutes) async {
    final timeRangeConfig = TimeRangeConfig(
      startTime: _dayStartTime,
      endTime: _dayEndTime,
      intervalMinutes: intervalMinutes,
    );

    final newTimeSlots = _generateTimeSlots(timeRangeConfig);

    final latestData = await _fetchLatestTimeSlotData();
    final List<String> storedTimes =
    (latestData['storedTimes'] as List<dynamic>).map((e) => e.toString()).toList();
    final bookedTimeSlots = latestData['bookedTimeSlots'] as List<String>;

    if (bookedTimeSlots.isNotEmpty && mounted) {
      await DialogUtils.openInfo(
        context,
        title: 'Bilgi',
        message:
        'Aşağıdaki zaman dilimlerinde randevu bulunmakta. Bu dilimler otomatik olarak eklenecek:\n${bookedTimeSlots.join(", ")}',
      );
    }

    if (!mounted) return;

    try {
      final slotsToAdd = newTimeSlots.where((s) => !storedTimes.contains(s)).toList();
      for (final booked in bookedTimeSlots) {
        if (!storedTimes.contains(booked) && !slotsToAdd.contains(booked)) {
          slotsToAdd.add(booked);
        }
      }

      if (slotsToAdd.isEmpty) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Bilgi',
          message: 'Eklenecek yeni zaman dilimi bulunamadı. Tüm zaman dilimleri zaten mevcut.',
        );
        return;
      }

      final updated = [...storedTimes, ...slotsToAdd];
      _sortSlotsChronologically(updated);
      final success = await _saveTimeSlotsWithErrorHandling(updated);
      if (success && mounted) {
        await _fetchDayData(_selectedDate);
      }
    } catch (e) {
      logger.err('Error in saving timeslots. {}', [e]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Zaman dilimleri kaydedilemedi. Lütfen destek talep ediniz.',
      );
    }
  }

  /// Build time range picker with start and end time selectors
  Widget _buildTimeRangePicker({
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required Function(TimeOfDay) onStartTimeChanged,
    required Function(TimeOfDay) onEndTimeChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: ListTile(
            title: const Text('Başlangıç'),
            subtitle: Text(_formatTimeSlot(startTime)),
            onTap: () async {
              final TimeOfDay? picked = await _showCustomTimeInputDialog(startTime);
              if (picked != null) onStartTimeChanged(picked);
            },
          ),
        ),
        Expanded(
          child: ListTile(
            title: const Text('Bitiş'),
            subtitle: Text(_formatTimeSlot(endTime)),
            onTap: () async {
              final TimeOfDay? picked = await _showCustomTimeInputDialog(endTime);
              if (picked != null) onEndTimeChanged(picked);
            },
          ),
        ),
      ],
    );
  }

  /// Build preview of time slots
  Widget _buildTimeSlotPreview(List<String> slots) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: slots.map((s) => Chip(label: Text(s))).toList(),
        ),
      ),
    );
  }

  /// Show manual selection dialog - allows admin to pick individual time slots
  Future<void> _showManualSelectionDialog() async {
    TimeOfDay startTime = _dayStartTime;
    TimeOfDay endTime = _dayEndTime;
    const int intervalMinutes = 5; // 5-minute intervals for selection
    
    // Track selected slots - pre-populate with existing stored time slots
    final Set<String> selectedSlots = {..._storedTimesForDay};

    try {
      return await showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (builderContext, setDialogState) {
              // Generate all possible slots at 5-minute intervals
              final allSlots = _generateSlotsWithInterval(
                startTime,
                endTime,
                intervalMinutes,
              );

              return AlertDialog(
                title: const Text('Elle Seç'),
                content: SizedBox(
                  width: MediaQuery.of(dialogContext).size.width * 0.8,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTimeRangePicker(
                          startTime: startTime,
                          endTime: endTime,
                          onStartTimeChanged: (t) => setDialogState(() {
                            startTime = t;
                            // Clear selections when time range changes
                            selectedSlots.clear();
                          }),
                          onEndTimeChanged: (t) => setDialogState(() {
                            endTime = t;
                            // Clear selections when time range changes
                            selectedSlots.clear();
                          }),
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Zaman Dilimleri (${selectedSlots.length} seçildi)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setDialogState(() {
                                      selectedSlots.addAll(allSlots);
                                    });
                                  },
                                  child: const Text('Tümünü Seç'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setDialogState(() {
                                      selectedSlots.clear();
                                    });
                                  },
                                  child: const Text('Temizle'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Seçmek için tıklayın, tekrar tıklayarak seçimi kaldırın.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        _buildSelectableTimeSlotGrid(
                          allSlots,
                          selectedSlots,
                          (slot) {
                            setDialogState(() {
                              if (selectedSlots.contains(slot)) {
                                selectedSlots.remove(slot);
                              } else {
                                selectedSlots.add(slot);
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('İptal'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (selectedSlots.isEmpty) {
                        if (!mounted) return;
                        await DialogUtils.openError(
                          builderContext,
                          title: 'Hata',
                          message: 'Lütfen en az bir zaman dilimi seçin.',
                        );
                        return;
                      }

                      Navigator.of(dialogContext).pop(); // close dialog first
                      if (!mounted) return;

                      await _applyManualSelection(selectedSlots.toList());
                    },
                    child: const Text('Tamam'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      logger.err('Error in manual selection dialog: {}', [e]);
    }
  }

  /// Generate time slots with a given interval between start and end time
  List<String> _generateSlotsWithInterval(
    TimeOfDay startTime,
    TimeOfDay endTime,
    int intervalMinutes,
  ) {
    final slots = <String>[];
    int currentMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;

    while (currentMinutes <= endMinutes) {
      final hour = currentMinutes ~/ 60;
      final minute = currentMinutes % 60;
      if (hour < 24) {
        slots.add(_formatTimeSlot(TimeOfDay(hour: hour, minute: minute)));
      }
      currentMinutes += intervalMinutes;
    }
    return slots;
  }

  /// Build selectable time slot grid for manual selection
  Widget _buildSelectableTimeSlotGrid(
    List<String> allSlots,
    Set<String> selectedSlots,
    void Function(String slot) onSlotTap,
  ) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 350),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: allSlots.map((slot) {
            final isSelected = selectedSlots.contains(slot);
            final hasAppt = _hasAppointment[slot] ?? false;

            return GestureDetector(
              onTap: () => onSlotTap(slot),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: hasAppt
                      ? Colors.red[100]
                      : isSelected
                          ? Colors.green[400]
                          : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasAppt
                        ? Colors.red[400]!
                        : isSelected
                            ? Colors.green[700]!
                            : Colors.grey[400]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasAppt)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.event,
                          size: 14,
                          color: Colors.red[700],
                        ),
                      ),
                    Text(
                      slot,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: hasAppt
                            ? Colors.red[900]
                            : isSelected
                                ? Colors.white
                                : Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Apply the manual selection - save selected slots as available time slots
  Future<void> _applyManualSelection(List<String> selectedSlots) async {
    try {
      // Sort slots chronologically
      _sortSlotsChronologically(selectedSlots);

      // Fetch latest data to check for appointments
      final latestData = await _fetchLatestTimeSlotData();
      final bookedTimeSlots = latestData['bookedTimeSlots'] as List<String>;

      // Check if any booked slots are NOT in the selected slots
      final bookedButNotSelected = bookedTimeSlots
          .where((slot) => !selectedSlots.contains(slot))
          .toList();

      if (bookedButNotSelected.isNotEmpty) {
        if (!mounted) return;
        final proceed = await DialogUtils.openConfirm(
          context,
          title: 'Uyarı',
          message:
              'Aşağıdaki zaman dilimlerinde randevu bulunmakta ancak seçiminizde yer almıyor:\n${bookedButNotSelected.join(", ")}\n\nBu dilimler otomatik olarak eklenecek. Devam etmek istiyor musunuz?',
        );
        if (!proceed) return;
      }

      // Add booked slots that weren't selected (to preserve appointments)
      final finalSlots = [...selectedSlots];
      for (final booked in bookedButNotSelected) {
        if (!finalSlots.contains(booked)) {
          finalSlots.add(booked);
        }
      }
      _sortSlotsChronologically(finalSlots);

      // Save the time slots
      final success = await _saveTimeSlotsWithErrorHandling(finalSlots);
      if (success && mounted) {
        await _fetchDayData(_selectedDate);
      }
    } catch (e) {
      logger.err('Error in applying manual selection: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Zaman dilimleri kaydedilemedi: ${e.toString()}',
        );
      }
    }
  }

  /// Show dialog to copy time slots from another day
  Future<void> _showCopyFromAnotherDayDialog() async {
    DateTime? sourceDate;
    
    // Loop until user confirms or cancels
    while (true) {
      if (!mounted) return;
      
      // Step 1: Pick a source date
      sourceDate = await showDatePicker(
        context: context,
        initialDate: sourceDate ?? _selectedDate.subtract(const Duration(days: 1)),
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        helpText: 'Kopyalanacak günü seçin',
        confirmText: 'Seç',
        cancelText: 'İptal',
        locale: const Locale('tr', 'TR'),
      );

      // User cancelled date picker
      if (sourceDate == null || !mounted) return;

      // Don't allow copying from the same day
      if (_sameYMD(sourceDate, _selectedDate)) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Aynı günden kopyalama yapamazsınız. Lütfen farklı bir gün seçin.',
        );
        continue;
      }

      // Step 2: Fetch time slots from the source date
      try {
        final timeslotManager =
            Provider.of<TimeslotManager>(context, listen: false);
        final sourceData = await timeslotManager.fetchTimeslotDataForDate(sourceDate);

        final sourceAdminSlots = (sourceData['adminSlots'] as List)
            .map((e) => e.toString())
            .toList();

        if (sourceAdminSlots.isEmpty) {
          if (!mounted) return;
          final tryAgain = await DialogUtils.openConfirm(
            context,
            title: 'Bilgi',
            message:
                '${_dayTitleFmt.format(sourceDate)} tarihinde kopyalanacak zaman dilimi bulunamadı.\n\nBaşka bir gün seçmek ister misiniz?',
            confirmText: 'Evet',
            cancelText: 'Hayır',
          );
          if (tryAgain) continue;
          return;
        }

        _sortSlotsChronologically(sourceAdminSlots);

        // Step 3: Show confirmation dialog with the slots
        if (!mounted) return;
        final confirmed = await _showCopyConfirmationDialog(
          sourceDate,
          sourceAdminSlots,
        );

        if (confirmed == true) {
          await _applyCopyFromAnotherDay(sourceAdminSlots);
          return;
        } else if (confirmed == false) {
          // User clicked "Başka Gün Seç" - continue loop
          continue;
        } else {
          // User cancelled (null) - exit
          return;
        }
      } catch (e) {
        logger.err('Error fetching source date data: {}', [e]);
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Kaynak tarih verileri alınırken hata oluştu: ${e.toString()}',
        );
        return;
      }
    }
  }

  /// Show confirmation dialog for copying time slots
  /// Returns: true = confirmed, false = choose another day, null = cancelled
  Future<bool?> _showCopyConfirmationDialog(
    DateTime sourceDate,
    List<String> slots,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Zaman Dilimlerini Kopyala'),
          content: SizedBox(
            width: MediaQuery.of(dialogContext).size.width * 0.7,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(dialogContext).style,
                      children: [
                        TextSpan(
                          text: _dayTitleFmt.format(sourceDate),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' tarihinden '),
                        TextSpan(
                          text: '${slots.length} zaman dilimi',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' kopyalanacak:'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: slots.map((slot) {
                          return Chip(
                            label: Text(slot, style: const TextStyle(fontSize: 12)),
                            backgroundColor: Colors.green[100],
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Hedef tarih: ${_dayTitleFmt.format(_selectedDate)}',
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Başka Gün Seç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Kopyala'),
            ),
          ],
        );
      },
    );
  }

  /// Apply the copy from another day - merge with existing slots
  Future<void> _applyCopyFromAnotherDay(List<String> slotsToAdd) async {
    try {
      // Fetch latest data for current date
      final latestData = await _fetchLatestTimeSlotData();
      final currentStoredTimes = (latestData['storedTimes'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
      final bookedTimeSlots = latestData['bookedTimeSlots'] as List<String>;

      // Merge: add new slots that don't already exist
      final mergedSlots = {...currentStoredTimes, ...slotsToAdd}.toList();

      // Make sure booked slots are preserved
      for (final booked in bookedTimeSlots) {
        if (!mergedSlots.contains(booked)) {
          mergedSlots.add(booked);
        }
      }

      _sortSlotsChronologically(mergedSlots);

      // Save
      final success = await _saveTimeSlotsWithErrorHandling(mergedSlots);
      if (success && mounted) {
        await _fetchDayData(_selectedDate);
      }
    } catch (e) {
      logger.err('Error applying copy from another day: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Zaman dilimleri kopyalanırken hata oluştu: ${e.toString()}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWithBack(
        title: 'Zaman Aralıkları Yönetimi',
        actions: [
          // Keep any existing actions here
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildHeaderSection(),
          Expanded(
            child: Scrollbar(
              controller: _verticalCtrl,
              child: SingleChildScrollView(
                key: _kVerticalKey,
                controller: _verticalCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildTimeSlotsSection(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build header section with calendar and buttons
  Widget _buildHeaderSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCalendarCard(),
          const SizedBox(height: 24),
          _buildActionButtons(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Build calendar card with toggle
  Widget _buildCalendarCard() {
    return Card(
      elevation: 4,
      child: Column(
        children: [
          ListTile(
            title: Row(
              children: [
                const Icon(Icons.calendar_today),
                const SizedBox(width: 8),
                Text(
                  _dayTitleFmt.format(_selectedDate),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            trailing: IconButton(
              icon: Icon(_showCalendar ? Icons.expand_less : Icons.expand_more, size: 32),
              onPressed: () => setState(() => _showCalendar = !_showCalendar),
              tooltip: _showCalendar ? 'Takvimi Gizle' : 'Takvimi Göster',
            ),
          ),
          if (_showCalendar)
            TableCalendar(
              firstDay: DateTime.now().subtract(const Duration(days: 365)),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _selectedDate,
              selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
              onDaySelected: _onDaySelected,
              calendarFormat: CalendarFormat.week,
              availableCalendarFormats: const {
                CalendarFormat.week: 'Week',
              },
              calendarStyle: const CalendarStyle(
                todayDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                selectedDecoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }

  /// Build action buttons for the page
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 800) {
            return Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              alignment: WrapAlignment.center,
              children: _buildActionButtonsList(),
            );
          } else {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _buildActionButtonsList(),
              ),
            );
          }
        },
      ),
    );
  }

  /// List of action buttons to be used in both layouts
  List<Widget> _buildActionButtonsList() {
    final rangeLabel =
        '${_formatTimeSlot(_dayStartTime)}–${_formatTimeSlot(_dayEndTime)}';

    return [
      ElevatedButton.icon(
        onPressed: _showDayTimeRangeDialog,
        icon: const Icon(Icons.schedule),
        label: Text('Saat Aralığı ($rangeLabel)'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple[50],
          foregroundColor: Colors.deepPurple[900],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      Container(height: 36, width: 1, color: Colors.grey[300]),
      ElevatedButton.icon(
        onPressed: _showDeleteAllConfirmationDialog,
        icon: const Icon(Icons.delete_forever),
        label: const Text('Tüm Zamanları Sil'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[100],
          foregroundColor: Colors.red[900],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      Container(height: 36, width: 1, color: Colors.grey[300]),
      ElevatedButton.icon(
        onPressed: () => _showIntervalTimeRangeDialog(30),
        icon: const Icon(Icons.access_time),
        label: const Text('30dk Aralıkla Oluştur'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[100],
          foregroundColor: Colors.blue[900],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      ElevatedButton.icon(
        onPressed: () => _showIntervalTimeRangeDialog(20),
        icon: const Icon(Icons.access_time),
        label: const Text('20dk Aralıkla Oluştur'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green[100],
          foregroundColor: Colors.green[900],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      ElevatedButton.icon(
        onPressed: _showTimeSlotDialog,
        icon: const Icon(Icons.add),
        label: const Text('Elle Ekle'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.amber[100],
          foregroundColor: Colors.amber[900],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      ElevatedButton.icon(
        onPressed: _showManualSelectionDialog,
        icon: const Icon(Icons.touch_app),
        label: const Text('Elle Seç'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal[100],
          foregroundColor: Colors.teal[900],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      ElevatedButton.icon(
        onPressed: _showCopyFromAnotherDayDialog,
        icon: const Icon(Icons.content_copy),
        label: const Text('Başka Günden Kopyala'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.indigo[100],
          foregroundColor: Colors.indigo[900],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    ];
  }

  Future<void> _deleteAllTimeSlots() async {
    ///TODO: big query olan yerler, mesela bura, firebase ile optimize edilmeli bi şekil
    try {
      final timeslotManager =
      Provider.of<TimeslotManager>(context, listen: false);

      await timeslotManager.deleteTimeSlots(_selectedDate, preserveBooked: true);

      // Reload data from manager
      final data =
      await timeslotManager.fetchTimeslotDataForDate(_selectedDate);

      final storedTimes = (data['storedTimes'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
      final hasAppt =
      Map<String, bool>.from(data['hasAppointment'] as Map<dynamic, dynamic>);

      if (!mounted) return;
      setState(() {
        _storedTimesForDay = storedTimes;
        _hasAppointment
          ..clear()
          ..addAll(hasAppt);
      });

      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message:
        'Tüm boş zaman dilimleri silindi. Randevulu zaman dilimleri korundu.',
      );
    } catch (e) {
      logger.err('Error deleting time slots: {}', [e]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Zaman dilimleri silinirken bir hata oluştu: ${e.toString()}',
      );
    }
  }


  Future<void> _showDeleteAllConfirmationDialog() async {
    final confirm = await DialogUtils.openConfirm(
      context,
      title: 'Tüm Zaman Dilimlerini Sil',
      message:
      'Bu tarihteki tüm boş zaman dilimlerini silmek istediğinizden emin misiniz? Randevulu zaman dilimleri korunacaktır. Bu işlem geri alınamaz.',
      confirmText: 'Evet, Sil',
      cancelText: 'İptal',
    );

    if (confirm) {
      await _deleteAllTimeSlots();
    }
  }

  List<String> _generateTimeSlots(TimeRangeConfig config) {
    final slots = <String>[];
    var currentTime = config.startTime;

    while (currentTime.hour < config.endTime.hour ||
        (currentTime.hour == config.endTime.hour && currentTime.minute <= config.endTime.minute)) {
      slots.add(_formatTimeSlot(currentTime));
      final total = currentTime.hour * 60 + currentTime.minute + config.intervalMinutes;
      currentTime = TimeOfDay(hour: total ~/ 60, minute: total % 60);
    }
    return slots;
  }
}


// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:provider/provider.dart';
//
// import '../dialogs/edit_appointment_dialog.dart';
// import '../models/logger.dart';
// import '../models/appointment_model.dart';
// import '../providers/timeslot_manager.dart';
// import '../utils/dialog_utils.dart';
// import '../widgets/app_bar_with_back.dart';
// import '../widgets/loading_overlay.dart';
//
// final Logger logger = Logger.forClass(AdminTimeSlotsPage);
//
// class AdminTimeSlotsPage extends StatefulWidget {
//   const AdminTimeSlotsPage({super.key});
//
//   @override
//   createState() => _AdminTimeSlotsPageState();
// }
//
// class _AdminTimeSlotsPageState extends State<AdminTimeSlotsPage>
//     with LoadingStateMixin {
//   DateTime _selectedDate = DateTime.now();
//   bool _isFetching = false;
//
//   /// Stored time slots for the selected day
//   List<String> _storedTimesForDay = [];
//
//   /// Which times have appointments
//   final Map<String, bool> _hasAppointment = {};
//   Map<String, List<AppointmentModel>> _appointmentsBySlot = {};
//
//   /// Time range for the toggle grid
//   static const int _gridStartHour = 8;
//   static const int _gridEndHour = 20;
//   static const int _intervalMinutes = 30;
//
//   /// Formatters
//   static final DateFormat _dayTitleFmt = DateFormat('d MMMM yyyy, EEEE', 'tr_TR');
//   static final DateFormat _shortDayFmt = DateFormat('d', 'tr_TR');
//   static final DateFormat _weekdayFmt = DateFormat('EEE', 'tr_TR');
//
//   /// All possible time slots in the grid
//   late final List<String> _allPossibleSlots;
//
//   @override
//   void initState() {
//     super.initState();
//     _allPossibleSlots = _generateAllPossibleSlots();
//     _fetchDayData(_selectedDate);
//   }
//
//   /// Generate all possible time slots for the grid
//   List<String> _generateAllPossibleSlots() {
//     final slots = <String>[];
//     for (int hour = _gridStartHour; hour < _gridEndHour; hour++) {
//       for (int min = 0; min < 60; min += _intervalMinutes) {
//         slots.add('${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}');
//       }
//     }
//     // Add the end hour slot (e.g., 20:00)
//     slots.add('${_gridEndHour.toString().padLeft(2, '0')}:00');
//     return slots;
//   }
//
//   /// Fetch data for the selected date
//   Future<void> _fetchDayData(DateTime date) async {
//     setState(() => _isFetching = true);
//
//     try {
//       final timeslotManager = Provider.of<TimeslotManager>(context, listen: false);
//       final data = await timeslotManager.fetchTimeslotDataForDate(date);
//
//       final storedTimes = (data['storedTimes'] as List).map((e) => e.toString()).toList();
//       final rawHasAppt = data['hasAppointment'] as Map;
//       final hasAppt = <String, bool>{};
//       rawHasAppt.forEach((key, value) {
//         hasAppt[key.toString()] = value as bool;
//       });
//
//       final rawAppointmentsBySlot = data['appointmentsBySlot'] as Map?;
//       final appointmentsBySlot = <String, List<AppointmentModel>>{};
//       (rawAppointmentsBySlot ?? {}).forEach((key, value) {
//         appointmentsBySlot[key.toString()] = List<AppointmentModel>.from(value as List);
//       });
//
//       if (!mounted) return;
//       setState(() {
//         _storedTimesForDay = storedTimes;
//         _hasAppointment
//           ..clear()
//           ..addAll(hasAppt);
//         _appointmentsBySlot = appointmentsBySlot;
//         _isFetching = false;
//       });
//     } catch (e) {
//       logger.err('Error fetching day data: {}', [e]);
//       if (!mounted) return;
//       await DialogUtils.openError(
//         context,
//         title: 'Hata',
//         message: 'Veri yüklenirken hata oluştu: $e',
//       );
//       setState(() => _isFetching = false);
//     }
//   }
//
//   /// Toggle a time slot on/off
//   Future<void> _toggleTimeSlot(String timeStr) async {
//     final hasAppt = _hasAppointment[timeStr] ?? false;
//
//     // If there's an appointment, show details instead
//     if (hasAppt) {
//       await _showAppointmentDetails(timeStr);
//       return;
//     }
//
//     final isCurrentlyEnabled = _storedTimesForDay.contains(timeStr);
//
//     List<String> updated;
//     if (isCurrentlyEnabled) {
//       updated = List<String>.from(_storedTimesForDay)..remove(timeStr);
//     } else {
//       updated = [..._storedTimesForDay, timeStr];
//     }
//
//     // Sort chronologically
//     updated.sort((a, b) {
//       final ap = a.split(':');
//       final bp = b.split(':');
//       final am = int.parse(ap[0]) * 60 + int.parse(ap[1]);
//       final bm = int.parse(bp[0]) * 60 + int.parse(bp[1]);
//       return am.compareTo(bm);
//     });
//
//     // Optimistic UI update
//     setState(() {
//       _storedTimesForDay = updated;
//     });
//
//     try {
//       final timeslotManager = Provider.of<TimeslotManager>(context, listen: false);
//       await timeslotManager.updateTimeSlots(_selectedDate, updated);
//     } catch (e) {
//       logger.err('Error toggling timeslot: {}', [e]);
//       // Revert on error
//       await _fetchDayData(_selectedDate);
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
//         );
//       }
//     }
//   }
//
//   /// Apply a preset (common time patterns)
//   Future<void> _applyPreset(String presetName, int startHour, int startMin, int endHour, int endMin, int interval) async {
//     final confirm = await DialogUtils.openConfirm(
//       context,
//       title: presetName,
//       message: 'Bu şablon mevcut zaman dilimlerinin üzerine yazılacak. Devam etmek istiyor musunuz?',
//       confirmText: 'Uygula',
//     );
//
//     if (!confirm) return;
//
//     startLoading();
//
//     try {
//       // Generate slots from preset
//       final slots = <String>[];
//       int currentMinutes = startHour * 60 + startMin;
//       final endMinutes = endHour * 60 + endMin;
//
//       while (currentMinutes <= endMinutes) {
//         final h = currentMinutes ~/ 60;
//         final m = currentMinutes % 60;
//         slots.add('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
//         currentMinutes += interval;
//       }
//
//       // Get booked slots to preserve them
//       final bookedSlots = _hasAppointment.entries
//           .where((e) => e.value)
//           .map((e) => e.key)
//           .toList();
//
//       // Merge: keep booked slots even if not in preset
//       final finalSlots = {...slots, ...bookedSlots}.toList();
//       finalSlots.sort((a, b) {
//         final ap = a.split(':');
//         final bp = b.split(':');
//         final am = int.parse(ap[0]) * 60 + int.parse(ap[1]);
//         final bm = int.parse(bp[0]) * 60 + int.parse(bp[1]);
//         return am.compareTo(bm);
//       });
//
//       final timeslotManager = Provider.of<TimeslotManager>(context, listen: false);
//       await timeslotManager.updateTimeSlots(_selectedDate, finalSlots);
//
//       await _fetchDayData(_selectedDate);
//
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('$presetName uygulandı (${finalSlots.length} slot)'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       }
//     } catch (e) {
//       logger.err('Error applying preset: {}', [e]);
//       if (mounted) {
//         await DialogUtils.openError(context, title: 'Hata', message: 'Şablon uygulanamadı: $e');
//       }
//     } finally {
//       stopLoading();
//     }
//   }
//
//   /// Copy slots from another date
//   Future<void> _copyFromDate() async {
//     final DateTime? pickedDate = await showDatePicker(
//       context: context,
//       initialDate: _selectedDate.subtract(const Duration(days: 1)),
//       firstDate: DateTime.now().subtract(const Duration(days: 365)),
//       lastDate: DateTime.now().add(const Duration(days: 365)),
//       helpText: 'Kopyalanacak günü seçin',
//       locale: const Locale('tr', 'TR'),
//     );
//
//     if (pickedDate == null || !mounted) return;
//
//     final confirm = await DialogUtils.openConfirm(
//       context,
//       title: 'Günü Kopyala',
//       message: '${_dayTitleFmt.format(pickedDate)} tarihindeki zaman dilimleri bu güne kopyalanacak. Mevcut boş slotların üzerine yazılacak. Devam?',
//       confirmText: 'Kopyala',
//     );
//
//     if (!confirm) return;
//
//     startLoading();
//
//     try {
//       final timeslotManager = Provider.of<TimeslotManager>(context, listen: false);
//
//       // Fetch source day slots
//       final sourceData = await timeslotManager.fetchTimeslotDataForDate(pickedDate);
//       final sourceSlots = (sourceData['storedTimes'] as List).map((e) => e.toString()).toList();
//
//       if (sourceSlots.isEmpty) {
//         if (mounted) {
//           await DialogUtils.openInfo(context, title: 'Bilgi', message: 'Seçilen günde zaman dilimi bulunamadı.');
//         }
//         return;
//       }
//
//       // Keep current booked slots
//       final bookedSlots = _hasAppointment.entries
//           .where((e) => e.value)
//           .map((e) => e.key)
//           .toList();
//
//       final finalSlots = {...sourceSlots, ...bookedSlots}.toList();
//       finalSlots.sort((a, b) {
//         final ap = a.split(':');
//         final bp = b.split(':');
//         final am = int.parse(ap[0]) * 60 + int.parse(ap[1]);
//         final bm = int.parse(bp[0]) * 60 + int.parse(bp[1]);
//         return am.compareTo(bm);
//       });
//
//       await timeslotManager.updateTimeSlots(_selectedDate, finalSlots);
//       await _fetchDayData(_selectedDate);
//
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('${sourceSlots.length} zaman dilimi kopyalandı'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       }
//     } catch (e) {
//       logger.err('Error copying from date: {}', [e]);
//       if (mounted) {
//         await DialogUtils.openError(context, title: 'Hata', message: 'Kopyalama başarısız: $e');
//       }
//     } finally {
//       stopLoading();
//     }
//   }
//
//   /// Clear all (non-booked) slots
//   Future<void> _clearAll() async {
//     final bookedCount = _hasAppointment.values.where((v) => v).length;
//     final freeCount = _storedTimesForDay.length - bookedCount;
//
//     if (freeCount == 0) {
//       await DialogUtils.openInfo(
//         context,
//         title: 'Bilgi',
//         message: 'Silinecek boş zaman dilimi yok.',
//       );
//       return;
//     }
//
//     final confirm = await DialogUtils.openConfirm(
//       context,
//       title: 'Tümünü Temizle',
//       message: '$freeCount boş zaman dilimi silinecek. Randevulu slotlar korunacak. Devam?',
//       confirmText: 'Temizle',
//     );
//
//     if (!confirm) return;
//
//     startLoading();
//
//     try {
//       final timeslotManager = Provider.of<TimeslotManager>(context, listen: false);
//       await timeslotManager.deleteTimeSlots(_selectedDate, preserveBooked: true);
//       await _fetchDayData(_selectedDate);
//
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Boş slotlar temizlendi'), backgroundColor: Colors.orange),
//         );
//       }
//     } catch (e) {
//       logger.err('Error clearing slots: {}', [e]);
//       if (mounted) {
//         await DialogUtils.openError(context, title: 'Hata', message: 'Temizleme başarısız: $e');
//       }
//     } finally {
//       stopLoading();
//     }
//   }
//
//   /// Show appointment details
//   Future<void> _showAppointmentDetails(String timeStr) async {
//     final slotAppointments = _appointmentsBySlot[timeStr] ?? [];
//     if (slotAppointments.isEmpty) {
//       if (!mounted) return;
//       await DialogUtils.openInfo(
//         context,
//         title: 'Bilgi',
//         message: 'Bu zaman diliminde randevu bulunamadı.',
//       );
//       return;
//     }
//
//     final appointment = slotAppointments.first;
//
//     if (!mounted) return;
//     await showDialog(
//       context: context,
//       builder: (context) {
//         return EditAppointmentDialog(
//           appointment: appointment,
//           onAppointmentUpdated: () async {
//             await _fetchDayData(_selectedDate);
//           },
//         );
//       },
//     );
//   }
//
//   /// Navigate to a specific date
//   void _goToDate(DateTime date) {
//     if (_selectedDate.year == date.year &&
//         _selectedDate.month == date.month &&
//         _selectedDate.day == date.day) return;
//
//     setState(() => _selectedDate = date);
//     _fetchDayData(date);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: const AppBarWithBack(title: 'Zaman Dilimleri'),
//       body: Stack(
//         children: [
//           Column(
//             children: [
//               _buildDateStrip(),
//               _buildQuickActions(),
//               const Divider(height: 1),
//               Expanded(
//                 child: _isFetching
//                     ? const Center(child: CircularProgressIndicator())
//                     : _buildTimeGrid(),
//               ),
//             ],
//           ),
//           if (isLoading) const LoadingOverlay(message: 'İşlem yapılıyor...'),
//         ],
//       ),
//     );
//   }
//
//   /// Horizontal date strip for quick navigation
//   Widget _buildDateStrip() {
//     final today = DateTime.now();
//     final dates = List.generate(14, (i) => today.add(Duration(days: i - 3)));
//
//     return Container(
//       color: Theme.of(context).colorScheme.surfaceContainerHighest,
//       padding: const EdgeInsets.symmetric(vertical: 8),
//       child: Column(
//         children: [
//           // Month/Year header with navigation
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 IconButton(
//                   icon: const Icon(Icons.chevron_left),
//                   onPressed: () => _goToDate(_selectedDate.subtract(const Duration(days: 7))),
//                   tooltip: 'Önceki hafta',
//                 ),
//                 Text(
//                   _dayTitleFmt.format(_selectedDate),
//                   style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 IconButton(
//                   icon: const Icon(Icons.chevron_right),
//                   onPressed: () => _goToDate(_selectedDate.add(const Duration(days: 7))),
//                   tooltip: 'Sonraki hafta',
//                 ),
//               ],
//             ),
//           ),
//           // Date chips
//           SizedBox(
//             height: 70,
//             child: ListView.builder(
//               scrollDirection: Axis.horizontal,
//               padding: const EdgeInsets.symmetric(horizontal: 8),
//               itemCount: dates.length,
//               itemBuilder: (context, index) {
//                 final date = dates[index];
//                 final isSelected = date.year == _selectedDate.year &&
//                     date.month == _selectedDate.month &&
//                     date.day == _selectedDate.day;
//                 final isToday = date.year == today.year &&
//                     date.month == today.month &&
//                     date.day == today.day;
//
//                 return Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 4),
//                   child: GestureDetector(
//                     onTap: () => _goToDate(date),
//                     child: AnimatedContainer(
//                       duration: const Duration(milliseconds: 200),
//                       width: 52,
//                       decoration: BoxDecoration(
//                         color: isSelected
//                             ? Theme.of(context).colorScheme.primary
//                             : isToday
//                             ? Theme.of(context).colorScheme.primaryContainer
//                             : Colors.transparent,
//                         borderRadius: BorderRadius.circular(12),
//                         border: isToday && !isSelected
//                             ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
//                             : null,
//                       ),
//                       child: Column(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           Text(
//                             _weekdayFmt.format(date).toUpperCase(),
//                             style: TextStyle(
//                               fontSize: 11,
//                               fontWeight: FontWeight.w500,
//                               color: isSelected
//                                   ? Theme.of(context).colorScheme.onPrimary
//                                   : Theme.of(context).colorScheme.onSurfaceVariant,
//                             ),
//                           ),
//                           const SizedBox(height: 4),
//                           Text(
//                             _shortDayFmt.format(date),
//                             style: TextStyle(
//                               fontSize: 20,
//                               fontWeight: FontWeight.bold,
//                               color: isSelected
//                                   ? Theme.of(context).colorScheme.onPrimary
//                                   : Theme.of(context).colorScheme.onSurface,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   /// Quick action buttons
//   Widget _buildQuickActions() {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       padding: const EdgeInsets.all(12),
//       child: Row(
//         children: [
//           // Presets
//           _QuickActionChip(
//             icon: Icons.schedule,
//             label: '09:30-18:00 (30dk)',
//             color: Colors.blue,
//             onTap: () => _applyPreset('Standart Gün', 9, 30, 18, 0, 30),
//           ),
//           const SizedBox(width: 8),
//           _QuickActionChip(
//             icon: Icons.speed,
//             label: '09:00-18:00 (20dk)',
//             color: Colors.green,
//             onTap: () => _applyPreset('Yoğun Gün', 9, 0, 18, 0, 20),
//           ),
//           const SizedBox(width: 8),
//           _QuickActionChip(
//             icon: Icons.wb_sunny_outlined,
//             label: '09:00-13:00 (30dk)',
//             color: Colors.orange,
//             onTap: () => _applyPreset('Yarım Gün (Sabah)', 9, 0, 13, 0, 30),
//           ),
//           const SizedBox(width: 8),
//           // Divider
//           Container(height: 32, width: 1, color: Colors.grey.shade300),
//           const SizedBox(width: 8),
//           // Copy from another day
//           _QuickActionChip(
//             icon: Icons.content_copy,
//             label: 'Günden Kopyala',
//             color: Colors.purple,
//             onTap: _copyFromDate,
//           ),
//           const SizedBox(width: 8),
//           // Clear all
//           _QuickActionChip(
//             icon: Icons.delete_sweep,
//             label: 'Temizle',
//             color: Colors.red,
//             onTap: _clearAll,
//           ),
//         ],
//       ),
//     );
//   }
//
//   /// The main time grid - tap to toggle slots
//   Widget _buildTimeGrid() {
//     final enabledCount = _storedTimesForDay.length;
//     final bookedCount = _hasAppointment.values.where((v) => v).length;
//
//     return Column(
//       children: [
//         // Stats bar
//         Container(
//           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//           color: Theme.of(context).colorScheme.surfaceContainerLow,
//           child: Row(
//             children: [
//               _StatBadge(
//                 icon: Icons.check_circle,
//                 label: 'Aktif',
//                 count: enabledCount,
//                 color: Colors.green,
//               ),
//               const SizedBox(width: 16),
//               _StatBadge(
//                 icon: Icons.event_busy,
//                 label: 'Dolu',
//                 count: bookedCount,
//                 color: Colors.red,
//               ),
//               const Spacer(),
//               Text(
//                 'Tıklayarak aç/kapat',
//                 style: TextStyle(
//                   fontSize: 12,
//                   color: Theme.of(context).colorScheme.onSurfaceVariant,
//                 ),
//               ),
//             ],
//           ),
//         ),
//         // Grid
//         Expanded(
//           child: GridView.builder(
//             padding: const EdgeInsets.all(12),
//             gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
//               maxCrossAxisExtent: 90,
//               childAspectRatio: 1.8,
//               crossAxisSpacing: 8,
//               mainAxisSpacing: 8,
//             ),
//             itemCount: _allPossibleSlots.length,
//             itemBuilder: (context, index) {
//               final timeStr = _allPossibleSlots[index];
//               return _buildTimeSlotTile(timeStr);
//             },
//           ),
//         ),
//       ],
//     );
//   }
//
//   /// Individual time slot tile
//   Widget _buildTimeSlotTile(String timeStr) {
//     final isEnabled = _storedTimesForDay.contains(timeStr);
//     final hasAppt = _hasAppointment[timeStr] ?? false;
//
//     Color backgroundColor;
//     Color foregroundColor;
//     IconData? icon;
//
//     if (hasAppt) {
//       backgroundColor = Colors.red.shade100;
//       foregroundColor = Colors.red.shade900;
//       icon = Icons.event;
//     } else if (isEnabled) {
//       backgroundColor = Colors.green.shade100;
//       foregroundColor = Colors.green.shade900;
//       icon = Icons.check;
//     } else {
//       backgroundColor = Colors.grey.shade200;
//       foregroundColor = Colors.grey.shade600;
//       icon = null;
//     }
//
//     return Material(
//       color: backgroundColor,
//       borderRadius: BorderRadius.circular(8),
//       child: InkWell(
//         onTap: () => _toggleTimeSlot(timeStr),
//         borderRadius: BorderRadius.circular(8),
//         child: Container(
//           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               if (icon != null) ...[
//                 Icon(icon, size: 14, color: foregroundColor),
//                 const SizedBox(width: 4),
//               ],
//               Text(
//                 timeStr,
//                 style: TextStyle(
//                   fontSize: 13,
//                   fontWeight: isEnabled || hasAppt ? FontWeight.bold : FontWeight.normal,
//                   color: foregroundColor,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// /// Quick action chip widget
// class _QuickActionChip extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final Color color;
//   final VoidCallback onTap;
//
//   const _QuickActionChip({
//     required this.icon,
//     required this.label,
//     required this.color,
//     required this.onTap,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       color: color.withOpacity(0.15),
//       borderRadius: BorderRadius.circular(20),
//       child: InkWell(
//         onTap: onTap,
//         borderRadius: BorderRadius.circular(20),
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//           child: Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Icon(icon, size: 18, color: color),
//               const SizedBox(width: 6),
//               Text(
//                 label,
//                 style: TextStyle(
//                   fontSize: 13,
//                   fontWeight: FontWeight.w500,
//                   color: color,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// /// Stat badge widget
// class _StatBadge extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final int count;
//   final Color color;
//
//   const _StatBadge({
//     required this.icon,
//     required this.label,
//     required this.count,
//     required this.color,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Icon(icon, size: 16, color: color),
//         const SizedBox(width: 4),
//         Text(
//           '$count $label',
//           style: TextStyle(
//             fontSize: 13,
//             fontWeight: FontWeight.w500,
//             color: color,
//           ),
//         ),
//       ],
//     );
//   }
// }
