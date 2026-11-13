import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../dialogs/add_appointment_dialog.dart';
import '../dialogs/dialog_widgets.dart';
import '../models/appointment_model.dart';
import '../models/event_model.dart';
import '../models/user_model.dart';
import '../providers/appointment_colors_provider.dart';
import '../providers/appointment_manager.dart';
import '../providers/event_provider.dart';
import '../providers/timeslot_manager.dart';
import '../providers/user_provider.dart';
import '../dialogs/edit_appointment_dialog.dart';
import '../dialogs/edit_event_dialog.dart';
import '../dialogs/overlap_warning_dialog.dart';
import '../dialogs/reschedule_appointment_dialog.dart';
import '../utils/birthdays.dart';
import '../utils/calendar_drag.dart';
import '../utils/dialog_utils.dart';
import '../utils/postponement_notices.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/birthday_chip.dart';
import '../widgets/labeled_action_button.dart';

// Configuration constants
const double kMainMargin = 4.0; // Margin around the day columns
const double kDayTitleFontSize = 14.0; // Font size for the day header
const int kDaysToShow = 6; // Pazartesi..Cumartesi (Pazar gösterilmez)

// Time grid constants
const int kStartHour = 8; // grid starts at 08:30 (see kStartMinute)
const int kStartMinute = 30; // minute-of-hour the grid starts at
const int kEndHour = 20; // grid ends at 20:00
// Grid boundaries expressed in minutes-from-midnight.
const int kGridStartMinutes = kStartHour * 60 + kStartMinute; // 510 (08:30)
const int kGridEndMinutes = kEndHour * 60; // 1200 (20:00)
const int kSnapMinutes = 10;
const int kTimeLabelStepMinutes = 30;
// Total height of the time grid. This is the one number to turn when the cards
// feel too cramped or the day needs to fit on less scrolling — everything else
// (pixels per minute, card heights, card font sizes) is derived from it.
//
// At 1200 (1.74 px/min) a two-line label fits from ~16 minutes upward, and at
// the full 11px font from ~20 minutes upward — so every real appointment type
// (Tartım is drawn at a 20-minute minimum, the rest are 30/45/60) shows both
// lines even when two of them share a slot side by side.
//
// 900  → 1.30 px/min, less scrolling, two lines only from ~21 min
// 1200 → 1.74 px/min, current
// 1980 → 2.87 px/min, large cards, a lot of scrolling
const double kTotalGridHeight = 1656;

const double kTimeColumnWidth = 50.0; // Width of the time labels column
const double kTimeLabelRightPadding = 8.0;
const double kHourLabelFontSize = 11.0;
const double kHalfHourLabelFontSize = 9.5;
const double kDayHeaderHeight = 54.0; // Height for day title + add button
// Same header, mobile layout (single-day view has a slimmer header).
const double kMobileDayHeaderHeight = 36.0;
const double kDayDividerWidth = 1; // Width of vertical dividing lines between days (editable)
const double kScrollbarGutter = 12.0;



// "Tartım" visits are only ~5 min long; on the calendar their card is given at
// least this many minutes' worth of height so the label stays readable (their
// stored duration is unchanged).
const int kTartimMinDisplayMinutes = 20;

// Calculated: pixels per minute based on total height and hours
// 11 hours (9-20) = 660 minutes, so kTotalGridHeight / 660 = pixels per minute
const double kPixelsPerMinute =
    kTotalGridHeight / (kGridEndMinutes - kGridStartMinutes);

// --- Appointment/event card text geometry -----------------------------------
// A card's height is fixed by its duration (durationMinutes * kPixelsPerMinute),
// so the only way to be sure the label fits is to derive the font size from that
// height instead of picking it by hand. Every value the calculation depends on
// is a constant here, so the grid can be retuned from one place.
const double kCardVerticalMargin = 1.0; // card margin, top and bottom
const double kCardHorizontalMargin = 2.0;
const double kCardPadding = 4.0; // inner padding on every side
const double kCardBorderWidth = 1.0;
// Line height as a multiple of the font size. Pinned instead of left to the
// font's own metrics, otherwise "two lines" is not a number we can compute.
const double kCardTextLineHeight = 1.15;
// The label is allowed to wrap onto this many lines; the font is shrunk until
// that many lines fit in the card.
const int kCardMaxTextLines = 2;
const double kCardMaxFontSize = 11.0;
// Never shrink past this: below it the label is unreadable, and clipping the
// text is the better failure.
const double kCardMinFontSize = 7.5;

const double kDragSourceOpacity = 0.35;
const double kDragAutoScrollEdge = 56.0;
const double kDragAutoScrollVelocity = 40.0;
const double kDragClickSlop = 6.0;

const String kPostponedMark = '(E)';
const String kBurnedMark = '(Y)';
const String kPostponedMarkMeaning = 'Ertelenmiş randevu';
const String kBurnedMarkMeaning = 'Yakılmış randevu';
const String kDragHint = 'Randevuyu taşımak için basılı tutup sürükleyin';

// Hoisted formatters (avoid re-creating in every build)
final DateFormat _dayTitleFmt = DateFormat('d MMMM EEEE', 'tr_TR');
final DateFormat _rangeFmt = DateFormat('d MMMM', 'tr_TR');
final DateFormat _fullFmt = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');
final DateFormat _timeFmt = DateFormat('HH:mm');

class AdminAppointmentsPage extends StatefulWidget {
  const AdminAppointmentsPage({super.key});

  @override
  createState() => _AdminAppointmentsPageState();
}

class _AdminAppointmentsPageState extends State<AdminAppointmentsPage> {
  DateTime? startDate;
  DateTime? endDate;
  bool isTest = false; // test mode

  MeetingType? selectedMeetingType;
  Set<AppointmentStatus> selectedStatuses = Set.from(AppointmentStatus.values);
  // Newest first by default: the most recent appointment is the one the
  // admin usually looks for.
  String? sortOption = 'Tarih Azalan';

  final List<MeetingType?> meetingTypes = [null, ...MeetingType.values];
  final List<AppointmentStatus?> meetingStatuses = [null, ...AppointmentStatus.values];
  final List<String> sortOptions = ['Tarih Artan', 'Tarih Azalan', 'İsim A-Z', 'İsim Z-A'];

  late Future<List<AppointmentModel>> _appointmentsFuture;
  List<EventModel> _events = [];

  BirthdayIndex _birthdays = const BirthdayIndex.empty();

  // Scroll controllers + keys (avoid "no ScrollPosition" and preserve positions)
  late final ScrollController _verticalCtrl;

  static const _kVerticalKey = PageStorageKey('admin_appts_vertical');

  // Mobile daily view: selected day for single-day display
  late DateTime _selectedDay;

  // Threshold for mobile view (single day) vs desktop view (weekly)
  static const double _kMobileBreakpoint = 600.0;

  static const String _unknownCustomer = 'Bilinmiyor';
  static const String _reschedulingMessage = 'Randevu taşınıyor...';
  static const String _rescheduleFailedMessage =
      'Randevu taşınırken bir hata oluştu';
  static const String _notDraggableTitle = 'Randevu Taşınamaz';

  final GlobalKey _gridKey = GlobalKey();
  final ValueNotifier<String?> _draggedAppointmentId =
      ValueNotifier<String?>(null);
  final ValueNotifier<CalendarDropTarget?> _dropTarget =
      ValueNotifier<CalendarDropTarget?>(null);
  _GridLayout _gridLayout =
      const _GridLayout(days: <DateTime>[], headerHeight: kDayHeaderHeight);
  _AppointmentDrag? _drag;
  EdgeDraggingAutoScroller? _autoScroller;
  bool _refreshingInPlace = false;

  @override
  void initState() {
    super.initState();

    // Week: Monday..Saturday of current week
    final now = DateTime.now();
    final difference = now.weekday - DateTime.monday;
    final monday = now.subtract(Duration(days: difference));
    startDate = DateTime(monday.year, monday.month, monday.day);
    endDate = startDate!.add(const Duration(days: kDaysToShow - 1));

    // Mobile: start with today
    _selectedDay = DateTime(now.year, now.month, now.day);

    _verticalCtrl = ScrollController();

    _fetchAllAppointments();
    _fetchEvents();
    _loadBirthdays();
    // Danışanların saat seçicisinin okuduğu dolu saat aynası eski randevularla
    // doldurulur; beklenmez.
    Provider.of<TimeslotManager>(context, listen: false)
        .backfillBusySlotsOnce();
  }

  @override
  void dispose() {
    _clearDrag();
    _draggedAppointmentId.dispose();
    _dropTarget.dispose();
    _verticalCtrl.dispose();
    super.dispose();
  }

  /// Initiates fetching of all appointments
  void _fetchAllAppointments() {
    _clearDrag();
    _appointmentsFuture = _fetchAppointmentsWithUsers();
  }

  Future<void> _loadBirthdays({bool forceRefresh = false}) async {
    final UserProvider userProvider =
        Provider.of<UserProvider>(context, listen: false);
    final AppointmentColorsProvider colorsProvider =
        Provider.of<AppointmentColorsProvider>(context, listen: false);
    try {
      await colorsProvider.fetchColors();
    } catch (e) {
    }
    try {
      final List<UserModel> customers =
          await userProvider.fetchAllCustomers(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() => _birthdays = BirthdayIndex(customers));
    } catch (e) {
    }
  }

  double _dayHeaderHeightFor(List<DateTime> days) {
    int maxBirthdays = 0;
    for (final DateTime day in days) {
      final int count = _birthdays.on(day).length;
      if (count > maxBirthdays) maxBirthdays = count;
    }
    return kDayHeaderHeight +
        maxBirthdays * (kBirthdayChipHeight + kBirthdayChipGap);
  }

  Future<void> _fetchEvents() async {
    if (startDate == null || endDate == null) return;
    try {
      final eventProvider =
          Provider.of<EventProvider>(context, listen: false);
      final events = await eventProvider.fetchEventsForDateRange(
          startDate!, endDate!.add(const Duration(days: 1)));
      if (mounted) {
        setState(() => _events = events);
      }
    } catch (e) {
    }
  }

  void _showAddEventDialog(DateTime selectedDate) {
    final nameCtrl = TextEditingController();
    final startHourCtrl = TextEditingController(text: '09');
    final startMinCtrl = TextEditingController(text: '00');
    final endHourCtrl = TextEditingController(text: '10');
    final endMinCtrl = TextEditingController(text: '00');

    TimeOfDay? _parseFields(
        TextEditingController hCtrl, TextEditingController mCtrl) {
      final h = int.tryParse(hCtrl.text);
      final m = int.tryParse(mCtrl.text);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
        return null;
      }
      return TimeOfDay(hour: h, minute: m);
    }

    Widget buildTimeRow(String label, TextEditingController hCtrl,
        TextEditingController mCtrl) {
      return Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          SizedBox(
            width: 56,
            child: TextField(
              controller: hCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 2,
              decoration: const InputDecoration(
                counterText: '',
                hintText: 'SS',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            width: 56,
            child: TextField(
              controller: mCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 2,
              decoration: const InputDecoration(
                counterText: '',
                hintText: 'DD',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
            ),
          ),
        ],
      );
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Etkinlik Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Etkinlik Adı',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              buildTimeRow('Başlangıç', startHourCtrl, startMinCtrl),
              const SizedBox(height: 12),
              buildTimeRow('Bitiş', endHourCtrl, endMinCtrl),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('İptal')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  if (!mounted) return;
                  await DialogUtils.openError(dialogContext,
                      title: 'Hata',
                      message: 'Lütfen etkinlik adı giriniz.');
                  return;
                }
                final startTime =
                    _parseFields(startHourCtrl, startMinCtrl);
                final endTime = _parseFields(endHourCtrl, endMinCtrl);
                if (startTime == null || endTime == null) {
                  if (!mounted) return;
                  await DialogUtils.openError(dialogContext,
                      title: 'Hata',
                      message: 'Geçersiz saat formatı. SS:DD olarak giriniz.');
                  return;
                }
                final startDt = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    startTime.hour,
                    startTime.minute);
                final endDt = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    endTime.hour,
                    endTime.minute);
                if (!endDt.isAfter(startDt)) {
                  if (!mounted) return;
                  await DialogUtils.openError(dialogContext,
                      title: 'Hata',
                      message:
                          'Bitiş saati başlangıçtan sonra olmalıdır.');
                  return;
                }
                // Non-blocking overlap warning: if this event clashes with an
                // existing meeting, inform the admin and let them decide.
                final appointmentManager =
                    Provider.of<AppointmentManager>(context, listen: false);
                final conflicts =
                    await appointmentManager.findOverlappingAppointments(
                  start: startDt,
                  durationMinutes: endDt.difference(startDt).inMinutes,
                );
                if (conflicts.isNotEmpty) {
                  if (!mounted) return;
                  final proceed = await showOverlapWarningDialog(context,
                      conflicts: conflicts);
                  if (!proceed) return;
                }
                // Guarded on the dialog's own context, which is the one
                // being popped.
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                try {
                  // Re-checked after the await: the page may be gone by now.
                  if (!mounted) return;
                  final eventProvider =
                      Provider.of<EventProvider>(context, listen: false);
                  await eventProvider.addEvent(EventModel(
                    eventId: '',
                    name: name,
                    startDateTime: startDt,
                    endDateTime: endDt,
                    createDate: DateTime.now(),
                  ));
                  if (mounted) {
                    _fetchAllAppointments();
                    await _fetchEvents();
                  }
                } catch (e) {
                  if (mounted) {
                    await DialogUtils.openError(context,
                        title: 'Hata',
                        message: 'Etkinlik oluşturulamadı: $e');
                  }
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    ).then((_) {
      nameCtrl.dispose();
      startHourCtrl.dispose();
      startMinCtrl.dispose();
      endHourCtrl.dispose();
      endMinCtrl.dispose();
    });
  }

  Widget _buildEventCard(EventModel event, double cardHeight) {
    final String timeRange =
        '${_timeFmt.format(event.startDateTime)}-${_timeFmt.format(event.endDateTime)}';
    final String displayText = '$timeRange ${event.name}';

    return GestureDetector(
      onTap: () => _showEditEventDialog(context, event),
      onLongPress: () async {
        final confirm = await DialogUtils.openConfirm(
          context,
          title: 'Etkinliği Sil',
          message: '"${event.name}" etkinliğini silmek istiyor musunuz?',
        );
        if (confirm) {
          // Re-checked after the await: the widget may be gone by now.
          if (!mounted) return;
          final eventProvider =
              Provider.of<EventProvider>(context, listen: false);
          await eventProvider.deleteEvent(event.eventId);
          if (mounted) {
            _fetchAllAppointments();
            await _fetchEvents();
          }
        }
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        margin: const EdgeInsets.symmetric(
          horizontal: kCardHorizontalMargin,
          vertical: kCardVerticalMargin,
        ),
        padding: const EdgeInsets.all(kCardPadding),
        decoration: BoxDecoration(
          color: Colors.deepPurple.shade50,
          borderRadius: BorderRadius.circular(1),
          border: Border.all(
              color: Colors.deepPurple.shade200, width: kCardBorderWidth),
        ),
        child: _cardText(displayText, cardHeight),
      ),
    );
  }

  /// Generate test appointments for a given day
  List<AppointmentModel> _generateTestAppointments(DateTime day) {
    final List<AppointmentModel> testAppointments = [];
    const List<MeetingType> types = MeetingType.values;
    const List<AppointmentStatus> statuses = AppointmentStatus.values;

    // Create a test user
    final testUser = UserModel(
      userId: 'test_user_id',
      name: 'Test User',
      email: 'test@example.com',
      password: 'test_password',
      role: 'customer',
      createDate: DateTime.now(), surname: 'test surname',
    );

    // Generate 15 appointments with varying times between 9:00 and 18:30
    for (int i = 0; i < 15; i++) {
      final hour = 9 + (i ~/ 2); // Start from 9:00
      final minute = (i % 2) * 30; // Alternate between :00 and :30

      final appointmentTime = DateTime(day.year, day.month, day.day, hour, minute);

      if (hour > 18 || (hour == 18 && minute > 30)) continue;

      final appointment = AppointmentModel(
        appointmentId: 'test_appointment_$i',
        userId: testUser.userId,
        user: testUser,
        durationMinutes: 30,
        appointmentDateTime: appointmentTime,
        meetingType: types[i % types.length],
        status: statuses[i % statuses.length],
        createDate: DateTime.now(),
        updateDate: DateTime.now(),
        createUser: 'admin',
        updateUser: 'admin', appointmentType: AppointmentType.haftalik,
      );

      testAppointments.add(appointment);
    }

    return testAppointments;
  }

  /// Fetches appointments with user data
  /// Now uses Firebase-side filtering for better performance
  Future<List<AppointmentModel>> _fetchAppointmentsWithUsers() async {
    if (isTest) {
      if (startDate == null || endDate == null) return [];
      final List<AppointmentModel> allTestAppointments = [];
      for (var day = startDate!;
      day.isBefore(endDate!.add(const Duration(days: 1)));
      day = day.add(const Duration(days: 1))) {
        allTestAppointments.addAll(_generateTestAppointments(day));
      }
      // Apply client-side filters for test mode
      var filtered = allTestAppointments;
      
      // Filter by meeting type
      if (selectedMeetingType != null) {
        filtered = filtered.where((a) => a.meetingType == selectedMeetingType).toList();
      }
      
      // Filter by status
      if (selectedStatuses.isNotEmpty && selectedStatuses.length < AppointmentStatus.values.length) {
        filtered = filtered.where((a) => selectedStatuses.contains(a.status)).toList();
      }

      return _applySorting(filtered);
    }

    try {
      final appointmentManager = Provider.of<AppointmentManager>(context, listen: false);

      // Make sure admin-configured background colors are loaded before we
      // render appointment cards (no-op after the first call per session).
      try {
        await Provider.of<AppointmentColorsProvider>(context, listen: false)
            .fetchColors();
      } catch (e) {
      }

      // Apply filters on Firebase side for better performance
      final fetchedAppointments = await appointmentManager.fetchAppointmentsWithUsers(
        startDate: startDate,
        endDate: endDate,
        meetingTypeFilter: selectedMeetingType,
        statusesFilter: selectedStatuses,
      );

      // Only client-side sorting remains (Firebase doesn't support complex multi-field sorting)
      return _applySorting(fetchedAppointments);
    } catch (e) {
      return [];
    }
  }

  /// Show date range picker to select custom date range
  void _pickDateRange() async {
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
      initialDateRange:
      (startDate != null && endDate != null) ? DateTimeRange(start: startDate!, end: endDate!) : null,
    );

    if (pickedRange != null) {
      setState(() {
        startDate = DateTime(pickedRange.start.year, pickedRange.start.month, pickedRange.start.day);
        endDate = DateTime(pickedRange.end.year, pickedRange.end.month, pickedRange.end.day);
        _fetchAllAppointments();
        _fetchEvents();
      });
    }
  }

  /// Show dialog to add a new appointment
  void _showAddAppointmentDialog(BuildContext context, DateTime selectedDate) {
    showDialog(
      context: context,
      builder: (_) {
        return AddAppointmentDialog(
          selectedDate: selectedDate,
          hideDateSelection: true, // Date is already selected from the calendar
          onAppointmentAdded: () {
            setState(() => _fetchAllAppointments());
          },
        );
      },
    );
  }

  /// Show status filter dialog
  void _showStatusFilterDialog(BuildContext context) {
    final Set<AppointmentStatus> tempSelectedStatuses = Set.from(selectedStatuses);

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Randevu Durumları'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: AppointmentStatus.values.map((status) {
                    return CheckboxListTile(
                      title: Text(status.label),
                      value: tempSelectedStatuses.contains(status),
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            tempSelectedStatuses.add(status);
                          } else {
                            tempSelectedStatuses.remove(status);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      tempSelectedStatuses.clear();
                      tempSelectedStatuses.addAll(AppointmentStatus.values);
                    });
                  },
                  child: const Text('Tümünü Seç'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      tempSelectedStatuses.clear();
                    });
                  },
                  child: const Text('Tümünü Kaldır'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('İptal'),
                ),
                TextButton(
                  onPressed: () {
                    this.setState(() {
                      selectedStatuses = Set.from(tempSelectedStatuses);
                    });
                    Navigator.of(context).pop();
                    _fetchAllAppointments();
                  },
                  child: const Text('Tamam'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Apply client-side sorting to appointments (filtering now done on Firebase)
  /// Kept client-side because Firebase doesn't support complex multi-field sorting
  List<AppointmentModel> _applySorting(List<AppointmentModel> appointments) {
    // Sort appointments based on selected option
    // For postponed appointments, use postponedDate if exists
    appointments.sort((a, b) {
      switch (sortOption) {
        case 'Tarih Artan':
          return a.calendarDateTime.compareTo(b.calendarDateTime);
        case 'Tarih Azalan':
          return b.calendarDateTime.compareTo(a.calendarDateTime);
        case 'İsim A-Z':
          return (a.user?.fullName ?? '').compareTo(b.user?.fullName ?? '');
        case 'İsim Z-A':
          return (b.user?.fullName ?? '').compareTo(a.user?.fullName ?? '');
        default:
          return 0;
      }
    });

    return appointments;
  }

  /// Delete an appointment. Appointments are no longer cancelled — the record
  /// is either kept or removed for good.
  Future<void> _deleteAppointment(AppointmentModel appointment) async {
    final bool? returnRight =
        await PostponementNotices.askReturnRightOnDelete(context, appointment);
    if (returnRight == null || !mounted) return;
    try {
      final appointmentManager = Provider.of<AppointmentManager>(context, listen: false);
      final result = await appointmentManager.deleteAppointment(
        appointment.appointmentId,
        appointment.userId,
        deletedBy: 'Admin',
        returnPostponementRight: returnRight,
      );

      if (!mounted) return;
      if (result.deleted) {
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Randevu başarıyla silindi.'
              '${PostponementNotices.deleteResultNote(appointment, returned: result.rightReturned)}',
        );
        if (!mounted) return;
        _fetchAllAppointments();
        setState(() {}); // ensure FutureBuilder re-runs if needed
      } else {
        await DialogUtils.openError(context, title: 'Hata', message: 'Randevu bulunamadı, silinemedi.');
      }
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu silinirken bir hata oluştu: $e',
      );
    }
  }

  /// Confirm and delete an appointment. Same confirmation as the appointments
  /// tab uses.
  void _onDeleteClicked(AppointmentModel appt) async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Randevu Silme',
      message: '${_fullFmt.format(appt.appointmentDateTime)} '
          'tarihli randevuyu silmek istediğinizden emin misiniz?',
      confirmText: 'Evet, Sil',
      cancelText: 'İptal',
    );
    if (confirmed) {
      await _deleteAppointment(appt);
    }
  }

  /// Show dialog to edit an appointment
  void _showEditAppointmentDialog(BuildContext context, AppointmentModel appointment) {
    showDialog(
      context: context,
      builder: (_) {
        return EditAppointmentDialog(
          appointment: appointment,
          onAppointmentUpdated: () {
            setState(() => _fetchAllAppointments());
          },
        );
      },
    );
  }

  /// Show dialog to edit an event
  void _showEditEventDialog(BuildContext context, EventModel event) {
    showDialog(
      context: context,
      builder: (_) {
        return EditEventDialog(
          event: event,
          onEventUpdated: () {
            if (mounted) {
              _fetchAllAppointments();
              _fetchEvents();
            }
          },
        );
      },
    );
  }

  /// Check if date range is exactly 6 days (Monday to Saturday)
  bool get _isCorrectDateRange {
 return true;
  }

  /// Calculate the top position for an appointment based on its time
  double _getTopPositionForTime(DateTime dateTime) {
    final minutes = (dateTime.hour * 60 + dateTime.minute) - kGridStartMinutes;
    return minutes * kPixelsPerMinute;
  }

  /// Whether the given time falls within the visible grid window.
  bool _isWithinGrid(DateTime t) {
    final minutes = t.hour * 60 + t.minute;
    return minutes >= kGridStartMinutes && minutes < kGridEndMinutes;
  }

  void _startDrag(
    AppointmentModel appt,
    double cardHeight,
    Offset globalPosition,
    Offset localPosition, {
    required bool isClickCandidate,
  }) {
    if (_drag != null) return;
    final DateTime start = appt.calendarDateTime;
    _drag = _AppointmentDrag(
      appointment: appt,
      originalStart: DateTime(
          start.year, start.month, start.day, start.hour, start.minute),
      cardHeight: cardHeight,
      grabDy: localPosition.dy,
      pointer: globalPosition,
      isClickCandidate: isClickCandidate,
    );
    _draggedAppointmentId.value = appt.appointmentId;
    HardwareKeyboard.instance.addHandler(_onDragKey);
    _verticalCtrl.addListener(_updateDropTarget);
    HapticFeedback.mediumImpact();
    _updateDropTarget();
  }

  _AppointmentDrag? _dragOf(AppointmentModel appt) {
    final _AppointmentDrag? drag = _drag;
    return drag != null &&
            drag.appointment.appointmentId == appt.appointmentId
        ? drag
        : null;
  }

  void _moveDrag(AppointmentModel appt, Offset globalPosition) {
    final _AppointmentDrag? drag = _dragOf(appt);
    if (drag == null) return;
    drag.moveTo(globalPosition);
    _updateDropTarget();
    _autoScrollNearEdge();
  }

  void _updateDropTarget() {
    final _AppointmentDrag? drag = _drag;
    final RenderObject? grid = _gridKey.currentContext?.findRenderObject();
    if (drag == null || grid is! RenderBox || !grid.hasSize) return;
    final CalendarDropTarget target =
        _gridLayout.geometry(grid.size.width).dropTarget(
              pointer: grid.globalToLocal(drag.pointer),
              grabDy: drag.grabDy,
              originalMinutes: drag.originalMinutes,
              durationMinutes: drag.appointment.durationMinutes,
            );
    if (target == _dropTarget.value) return;
    if (_dropTarget.value != null) HapticFeedback.selectionClick();
    _dropTarget.value = target;
  }

  void _autoScrollNearEdge() {
    final _AppointmentDrag? drag = _drag;
    final ScrollableState? scrollable = _gridKey.currentContext
        ?.findAncestorStateOfType<ScrollableState>();
    final RenderObject? viewport = scrollable?.context.findRenderObject();
    if (drag == null ||
        scrollable == null ||
        viewport is! RenderBox ||
        !viewport.hasSize) {
      return;
    }
    _autoScroller ??= EdgeDraggingAutoScroller(
      scrollable,
      onScrollViewScrolled: _autoScrollNearEdge,
      velocityScalar: kDragAutoScrollVelocity,
    );
    _autoScroller!.startAutoScrollIfNecessary(Rect.fromCenter(
      center: drag.pointer,
      width: 1,
      height: math.min(2 * kDragAutoScrollEdge, viewport.size.height),
    ));
  }

  bool _onDragKey(KeyEvent event) {
    if (_drag == null ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    _clearDrag();
    return true;
  }

  void _clearDrag() {
    if (_drag == null) return;
    _drag = null;
    _autoScroller?.stopAutoScroll();
    _autoScroller = null;
    HardwareKeyboard.instance.removeHandler(_onDragKey);
    _verticalCtrl.removeListener(_updateDropTarget);
    _draggedAppointmentId.value = null;
    _dropTarget.value = null;
  }

  void _endDrag(AppointmentModel appt) {
    final _AppointmentDrag? drag = _dragOf(appt);
    if (drag == null) return;
    final CalendarDropTarget? target = _dropTarget.value;
    final _GridLayout layout = _gridLayout;
    _clearDrag();
    if (target == null || target.dayIndex >= layout.days.length) return;
    final DateTime newStart = target.onDay(layout.days[target.dayIndex]);
    if (newStart != drag.originalStart) {
      _rescheduleAppointment(drag.appointment, newStart);
    } else if (drag.isClickCandidate && drag.travelled <= kDragClickSlop) {
      _showEditAppointmentDialog(context, drag.appointment);
    }
  }

  Future<void> _rescheduleAppointment(
      AppointmentModel appt, DateTime newStart) async {
    final bool? deductRight = await showRescheduleAppointmentDialog(
      context,
      appointment: appt,
      newStart: newStart,
    );
    if (deductRight == null || !mounted) return;

    final AppointmentManager appointmentManager =
        Provider.of<AppointmentManager>(context, listen: false);
    final LoadingDialog loading =
        DialogUtils.openLoading(context, message: _reschedulingMessage);
    try {
      await appointmentManager.rescheduleAppointment(
        appt,
        newStart,
        deductPostponementRight: deductRight,
      );
      if (mounted) {
        setState(() {
          _refreshingInPlace = true;
          _fetchAllAppointments();
        });
        await _appointmentsFuture;
      }
      loading.close();
    } catch (e) {
      loading.close();
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: '$_rescheduleFailedMessage: $e',
        );
      }
    } finally {
      loading.close();
      _refreshingInPlace = false;
    }
  }

  void _explainNotDraggable(AppointmentModel appt) {
    DialogUtils.openInfo(
      context,
      title: _notDraggableTitle,
      message: '“${appt.status.label}” durumundaki randevular sürüklenerek '
          'taşınamaz. Tarihini ya da saatini değiştirmek için randevuya '
          'dokunup düzenleyin.',
    );
  }

  /// Lays out a day's meetings AND "Diğer" events with a Google-Calendar–style
  /// column-packing algorithm so overlapping items never cover each other:
  ///
  ///  * Items that overlap in time are split into side-by-side columns.
  ///  * Same-start items sit next to each other (equal columns).
  ///  * When one item's time span contains another, the longer/earlier item
  ///    takes the left column and the shorter one is offset to the right
  ///    (starting around the middle), so both stay readable.
  ///
  /// Items that don't overlap anything take the full column width.
  List<Widget> _buildPositionedItems(
      List<AppointmentModel> dayAppointments, DateTime day, double columnWidth) {
    final List<_PositionedEntry> entries = [];

    // Meetings (appointments).
    for (final appt in dayAppointments) {
      final start = appt.calendarDateTime;
      if (!_isWithinGrid(start)) continue;
      // "Tartım" visits keep their real (short) duration for overlap packing
      // but render at a taller minimum height so the label stays readable.
      final double height = _displayHeightForAppointment(appt);
      entries.add(_PositionedEntry(
        start: start,
        end: start.add(Duration(minutes: appt.durationMinutes)),
        displayHeight: height,
        card: _buildAppointmentCard(appt, height),
      ));
    }
    // "Diğer" events.
    for (final event in _eventsForDay(day)) {
      if (!_isWithinGrid(event.startDateTime)) continue;
      final double height = _getHeightForDuration(event.durationMinutes);
      entries.add(_PositionedEntry(
        start: event.startDateTime,
        end: event.endDateTime,
        displayHeight: height,
        card: _buildEventCard(event, height),
      ));
    }
    if (entries.isEmpty) return const <Widget>[];

    // Sort by start (asc); on a tie the longer item comes first so containers
    // take the left column.
    entries.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : b.end.compareTo(a.end);
    });

    // Assign every item to a column within its overlap cluster.
    final List<_PositionedEntry> cluster = [];
    final List<DateTime> columnEnds = []; // last end time per column
    DateTime? clusterEnd; // running max end of the current cluster

    void flush() {
      final n = columnEnds.length;
      for (final e in cluster) {
        e.columnCount = n;
      }
      cluster.clear();
      columnEnds.clear();
      clusterEnd = null;
    }

    for (final e in entries) {
      // A new cluster starts once an item begins at/after everything so far.
      if (clusterEnd != null && !e.start.isBefore(clusterEnd!)) {
        flush();
      }
      // Reuse the first column whose previous item has already ended.
      int col = -1;
      for (int i = 0; i < columnEnds.length; i++) {
        if (!e.start.isBefore(columnEnds[i])) {
          col = i;
          break;
        }
      }
      if (col == -1) {
        columnEnds.add(e.end);
        col = columnEnds.length - 1;
      } else {
        columnEnds[col] = e.end;
      }
      e.column = col;
      cluster.add(e);
      clusterEnd = (clusterEnd == null || e.end.isAfter(clusterEnd!))
          ? e.end
          : clusterEnd;
    }
    flush();

    // Build the positioned cards.
    final List<Widget> widgets = [];
    for (final e in entries) {
      final double w = columnWidth / e.columnCount;
      widgets.add(Positioned(
        top: _getTopPositionForTime(e.start),
        left: e.column * w,
        width: w,
        height: e.displayHeight,
        child: e.card,
      ));
    }
    return widgets;
  }

  /// Calculate the height for an appointment based on its duration
  double _getHeightForDuration(int durationMinutes) {
    return durationMinutes * kPixelsPerMinute;
  }

  /// Largest font size at which [lines] lines of text still fit inside a card
  /// of [cardHeight] pixels.
  ///
  /// The card's height is dictated by the appointment's duration and its width
  /// by how many appointments share the same slot, so a hand-picked font size
  /// cannot promise anything: two cards side by side halve the width, the label
  /// wraps onto a second line, and that second line has to be paid for out of a
  /// height nobody adjusted. Deriving the size from the real geometry is what
  /// makes "two lines fit" a fact rather than a hope.
  static double _cardFontSize(double cardHeight, {int lines = kCardMaxTextLines}) {
    final double usable = cardHeight -
        (2 * kCardVerticalMargin) -
        (2 * kCardPadding) -
        (2 * kCardBorderWidth);
    final double perLine = usable / lines;
    return (perLine / kCardTextLineHeight)
        .clamp(kCardMinFontSize, kCardMaxFontSize);
  }

  /// The label inside a calendar card, sized to fit [cardHeight].
  static Widget _cardText(String text, double cardHeight, {String marks = ''}) {
    final TextStyle style = TextStyle(
      fontSize: _cardFontSize(cardHeight),
      height: kCardTextLineHeight,
      fontWeight: FontWeight.bold,
    );
    if (marks.isEmpty) {
      return Text(
        text,
        style: style,
        overflow: TextOverflow.ellipsis,
        maxLines: kCardMaxTextLines,
      );
    }
    final TextStyle markStyle = style.copyWith(fontWeight: FontWeight.w900);
    final String suffix = ' $marks';
    return LayoutBuilder(
      builder: (context, constraints) {
        final String head = _fitBeforeSuffix(
            context, text, style, suffix, markStyle, constraints.maxWidth);
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: head, style: style),
              TextSpan(text: suffix, style: markStyle),
            ],
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: kCardMaxTextLines,
        );
      },
    );
  }

  static String _fitBeforeSuffix(
    BuildContext context,
    String text,
    TextStyle style,
    String suffix,
    TextStyle suffixStyle,
    double maxWidth,
  ) {
    final TextStyle baseStyle = DefaultTextStyle.of(context).style;
    final TextPainter painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: kCardMaxTextLines,
    );
    bool fits(String head) {
      painter.text = TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: head, style: style),
          TextSpan(text: suffix, style: suffixStyle),
        ],
      );
      painter.layout(maxWidth: maxWidth);
      return !painter.didExceedMaxLines;
    }

    final Characters chars = text.characters;
    String shortened(int length) =>
        '${chars.take(length).toString().trimRight()}…';

    try {
      if (fits(text)) return text;
      int low = 0;
      int high = chars.length - 1;
      while (low < high) {
        final int mid = (low + high + 1) ~/ 2;
        if (fits(shortened(mid))) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      return shortened(low);
    } finally {
      painter.dispose();
    }
  }

  /// Height of an appointment card. "Tartım" visits are very short (5 min), so
  /// their card is given a taller minimum height ([kTartimMinDisplayMinutes]) so
  /// the label stays readable, without changing the stored duration.
  double _displayHeightForAppointment(AppointmentModel appt) {
    final int minutes = appt.appointmentType == AppointmentType.tartim &&
            appt.durationMinutes < kTartimMinDisplayMinutes
        ? kTartimMinDisplayMinutes
        : appt.durationMinutes;
    return _getHeightForDuration(minutes);
  }

  /// Total height of the time grid area
  double get _timeGridHeight => kTotalGridHeight;

  Widget _buildAppointmentCard(AppointmentModel appt, double cardHeight) {
    final Widget face =
        _appointmentCardFace(appt, cardHeight, appt.calendarDateTime);
    if (!appt.isReschedulable) {
      return GestureDetector(
        onTap: () => _showEditAppointmentDialog(context, appt),
        onLongPress: () => _explainNotDraggable(appt),
        child: face,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Listener(
        onPointerCancel: (_) {
          if (_dragOf(appt) != null) _clearDrag();
        },
        child: GestureDetector(
          onTap: () => _showEditAppointmentDialog(context, appt),
          onLongPressStart: (LongPressStartDetails details) => _startDrag(
            appt,
            cardHeight,
            details.globalPosition,
            details.localPosition,
            isClickCandidate: false,
          ),
          onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) =>
              _moveDrag(appt, details.globalPosition),
          onLongPressEnd: (_) => _endDrag(appt),
          child: GestureDetector(
            supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.mouse},
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (DragStartDetails details) => _startDrag(
              appt,
              cardHeight,
              details.globalPosition,
              details.localPosition,
              isClickCandidate: true,
            ),
            onPanUpdate: (DragUpdateDetails details) =>
                _moveDrag(appt, details.globalPosition),
            onPanEnd: (_) => _endDrag(appt),
            child: ValueListenableBuilder<String?>(
              valueListenable: _draggedAppointmentId,
              builder: (BuildContext context, String? draggedId,
                      Widget? child) =>
                  Opacity(
                opacity:
                    draggedId == appt.appointmentId ? kDragSourceOpacity : 1,
                child: child,
              ),
              child: face,
            ),
          ),
        ),
      ),
    );
  }

  Widget _appointmentCardFace(
    AppointmentModel appt,
    double cardHeight,
    DateTime start, {
    bool lifted = false,
  }) {
    final DateTime endTime = start.add(Duration(minutes: appt.durationMinutes));
    final String timeRange =
        '${_timeFmt.format(start)}-${_timeFmt.format(endTime)}';

    // Box text: "{saat} {DosyaNo}-{Ad Soyad}". The meeting type is intentionally
    // NOT shown, and the file number + dash is omitted when the client has none.
    final String displayText =
        '$timeRange ${appt.user?.fileLabel ?? _unknownCustomer}';
    final String marks = [
      if (appt.wasPostponed) kPostponedMark,
      if (appt.status == AppointmentStatus.burned) kBurnedMark,
    ].join(' ');

    final Color cardColor = appt.appointmentType.getBgColor(appt.meetingType);
    final Color borderColor = appt.appointmentType.getBorderColor(appt.meetingType);
    return Container(
      width: double.infinity,
      height: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: kCardHorizontalMargin,
        vertical: kCardVerticalMargin,
      ),
      padding: const EdgeInsets.all(kCardPadding),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(1),
        border: Border.all(color: borderColor, width: kCardBorderWidth),
        boxShadow: lifted ? kElevationToShadow[8] : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cardText(displayText, cardHeight, marks: marks)),
        ],
      ),
    );
  }

  static String _clockLabel(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  Widget _buildTimeColumn({double? headerHeight}) {
    final double effectiveHeaderHeight = headerHeight ?? kDayHeaderHeight;
    final int firstLabel =
        ((kGridStartMinutes + kTimeLabelStepMinutes - 1) ~/
                kTimeLabelStepMinutes) *
            kTimeLabelStepMinutes;

    return SizedBox(
      width: kTimeColumnWidth,
      height: effectiveHeaderHeight + _timeGridHeight,
      child: Stack(
        children: [
          for (int minutes = firstLabel;
              minutes < kGridEndMinutes;
              minutes += kTimeLabelStepMinutes)
            Positioned(
              top: effectiveHeaderHeight +
                  (minutes - kGridStartMinutes) * kPixelsPerMinute,
              right: kTimeLabelRightPadding,
              child: Text(
                _clockLabel(minutes),
                style: minutes % 60 == 0
                    ? TextStyle(
                        fontSize: kHourLabelFontSize,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      )
                    : TextStyle(
                        fontSize: kHalfHourLabelFontSize,
                        color: Colors.grey[500],
                      ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build a day column with appointments positioned by time
  Widget _buildDayColumn(DateTime day, List<AppointmentModel> dayAppointments,
      double headerHeight) {
    final String dayTitle = _dayTitleFmt.format(day);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.grey[300]!, width: kDayDividerWidth),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Day header
          Container(
            height: headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: kMainMargin, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  dayTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: kDayTitleFontSize),
                  overflow: TextOverflow.ellipsis,
                ),
                for (final UserModel user in _birthdays.on(day))
                  BirthdayChip(user: user, day: day),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 22,
                        child: ElevatedButton.icon(
                          onPressed: () => _showAddAppointmentDialog(context, day),
                          icon: const Icon(Icons.add, size: 12),
                          label: const Text('Ekle', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SizedBox(
                        height: 22,
                        child: ElevatedButton.icon(
                          onPressed: () => _showAddEventDialog(day),
                          icon: const Icon(Icons.add, size: 12),
                          label: const Text('Diğer', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            backgroundColor: Colors.deepPurple.shade50,
                            foregroundColor: Colors.deepPurple,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Time grid with appointments
          _buildTimeGrid(day, dayAppointments),
        ],
      ),
    );
  }

  Widget _buildTimeGrid(DateTime day, List<AppointmentModel> dayAppointments) {
    return SizedBox(
      height: _timeGridHeight,
      child: CustomPaint(
        painter: _TimeGridPainter(
          hourColor: Colors.grey[400]!,
          halfHourColor: Colors.grey[300]!,
          minorColor: Colors.grey[200]!,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Meetings + events, laid out in side-by-side columns so that
            // overlapping/containing items never cover each other.
            return Stack(
              children: _buildPositionedItems(
                  dayAppointments, day, constraints.maxWidth),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScrollableGrid({
    required _GridLayout layout,
    required List<Widget> columns,
  }) {
    _gridLayout = layout;
    return Scrollbar(
      controller: _verticalCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        key: _kVerticalKey,
        controller: _verticalCtrl,
        padding: const EdgeInsets.only(right: kScrollbarGutter),
        child: SizedBox(
          height: layout.headerHeight + _timeGridHeight,
          child: Stack(
            key: _gridKey,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: columns,
              ),
              Positioned.fill(child: _buildDragOverlay(layout)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragOverlay(_GridLayout layout) {
    return ValueListenableBuilder<CalendarDropTarget?>(
      valueListenable: _dropTarget,
      builder: (BuildContext context, CalendarDropTarget? target, _) {
        final _AppointmentDrag? drag = _drag;
        if (target == null ||
            drag == null ||
            target.dayIndex >= layout.days.length) {
          return const SizedBox.shrink();
        }
        final ColorScheme colors = Theme.of(context).colorScheme;
        return MouseRegion(
          cursor: SystemMouseCursors.grabbing,
          opaque: false,
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final CalendarGridGeometry geometry =
                    layout.geometry(constraints.maxWidth);
                final double top = geometry.topOf(target.startMinutes);
                final double left = geometry.dayLeft(target.dayIndex);
                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: layout.headerHeight,
                      width: geometry.dayWidth,
                      height: _timeGridHeight,
                      child: ColoredBox(
                          color: colors.primary.withValues(alpha: 0.06)),
                    ),
                    Positioned(
                      left: kTimeColumnWidth,
                      right: 0,
                      top: top,
                      height: 1,
                      child: ColoredBox(color: colors.primary),
                    ),
                    Positioned(
                      left: 0,
                      top: top,
                      width: kTimeColumnWidth,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(4)),
                          ),
                          child: Text(
                            _clockLabel(target.startMinutes),
                            style: TextStyle(
                              fontSize: kHourLabelFontSize,
                              height: 1.2,
                              fontWeight: FontWeight.bold,
                              color: colors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: left,
                      top: top,
                      width: geometry.dayWidth - kDayDividerWidth,
                      height: drag.cardHeight,
                      child: _appointmentCardFace(
                        drag.appointment,
                        drag.cardHeight,
                        target.onDay(layout.days[target.dayIndex]),
                        lifted: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<EventModel> _eventsForDay(DateTime day) {
    final dayStart = _dateOnly(day);
    return _events.where((e) {
      final eDay = _dateOnly(e.startDateTime);
      return eDay == dayStart;
    }).toList();
  }

  // Utility: normalize a DateTime to Y/M/D (00:00) to use as a map key
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ==================== Mobile Daily Navigation ====================
  
  /// Build mobile daily navigation bar with prev/next day buttons
  Widget _buildMobileDayNavigation() {
    final String dayTitle = _dayTitleFmt.format(_selectedDay);
    final bool isToday = _dateOnly(_selectedDay) == _dateOnly(DateTime.now());
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Row(
        children: [
          // Previous day button
          LabeledActionButton(
            dense: true,
            icon: Icons.chevron_left,
            label: 'Önceki Gün',
            onPressed: () {
              setState(() {
                _selectedDay = _selectedDay.subtract(const Duration(days: 1));
                // Update date range to include this day for fetching
                _updateDateRangeForMobile();
              });
            },
          ),
          // Day title (centered, tappable to go to today)
          Expanded(
            child: GestureDetector(
              onTap: () {
                // Tap to go to today
                setState(() {
                  _selectedDay = _dateOnly(DateTime.now());
                  _updateDateRangeForMobile();
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dayTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (isToday)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Bugün',
                        style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.w600),
                      ),
                    ),
                  for (final UserModel user in _birthdays.on(_selectedDay))
                    BirthdayChip(user: user, day: _selectedDay),
                ],
              ),
            ),
          ),
          // Next day button
          LabeledActionButton(
            dense: true,
            icon: Icons.chevron_right,
            label: 'Sonraki Gün',
            onPressed: () {
              setState(() {
                _selectedDay = _selectedDay.add(const Duration(days: 1));
                _updateDateRangeForMobile();
              });
            },
          ),
        ],
      ),
    );
  }

  /// Update date range to cover selected day (for fetching appointments)
  void _updateDateRangeForMobile() {
    // Set date range to just the selected day for efficient fetching
    startDate = _selectedDay;
    endDate = _selectedDay;
    _fetchAllAppointments();
    _fetchEvents();
  }

  // ==================== Desktop Weekly Navigation ====================
  
  /// Build desktop weekly navigation bar with prev/next week buttons
  Widget _buildDesktopWeekNavigation() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth;
          final bool isNarrow = w < 480;
          final bool isMedium = w >= 480 && w < 760;

          void goPrev() {
            if (startDate != null && endDate != null) {
              setState(() {
                startDate = startDate!.subtract(const Duration(days: 7));
                endDate = endDate!.subtract(const Duration(days: 7));
                _fetchAllAppointments();
                _fetchEvents();
              });
            }
          }

          void goNext() {
            if (startDate != null && endDate != null) {
              setState(() {
                startDate = startDate!.add(const Duration(days: 7));
                endDate = endDate!.add(const Duration(days: 7));
                _fetchAllAppointments();
                _fetchEvents();
              });
            }
          }

          final prevIcon = const Icon(Icons.arrow_back_ios);
          final nextIcon = const Icon(Icons.arrow_forward_ios);

          final Widget prevBtn = isNarrow
              ? LabeledActionButton(
                  dense: true,
                  icon: Icons.arrow_back_ios,
                  label: 'Önceki Hafta',
                  onPressed: goPrev)
              : ElevatedButton.icon(
                  onPressed: goPrev,
                  icon: prevIcon,
                  label: Text(isMedium ? 'Önceki' : 'Önceki Hafta'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[100],
                    foregroundColor: Colors.blue[900],
                    visualDensity: VisualDensity.compact,
                  ),
                );

          final Widget nextBtn = isNarrow
              ? LabeledActionButton(
                  dense: true,
                  icon: Icons.arrow_forward_ios,
                  label: 'Sonraki Hafta',
                  onPressed: goNext)
              : ElevatedButton.icon(
                  onPressed: goNext,
                  icon: nextIcon,
                  label: Text(isMedium ? 'Sonraki' : 'Sonraki Hafta'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[100],
                    foregroundColor: Colors.blue[900],
                    visualDensity: VisualDensity.compact,
                  ),
                );

          final Widget dateLabel = (startDate != null && endDate != null)
              ? Text(
                  '${_rangeFmt.format(startDate!)} - ${_rangeFmt.format(endDate!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                )
              : const SizedBox.shrink();

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [prevBtn, nextBtn],
                ),
                const SizedBox(height: 4),
                Center(child: dateLabel),
              ],
            );
          } else {
            return Row(
              children: [
                prevBtn,
                SizedBox(width: isMedium ? 8 : 12),
                Expanded(child: Center(child: dateLabel)),
                SizedBox(width: isMedium ? 8 : 12),
                nextBtn,
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildMarkLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _markLegendEntry(kPostponedMark, kPostponedMarkMeaning),
            _markLegendEntry(kBurnedMark, kBurnedMarkMeaning),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.open_with, size: 14, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                Flexible(child: Text(kDragHint, style: _legendStyle)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _markLegendEntry(String mark, String meaning) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: mark,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          TextSpan(text: ' = $meaning'),
        ],
      ),
      style: _legendStyle,
    );
  }

  TextStyle get _legendStyle => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade700,
      );

  // ==================== Content Views ====================

  // Mobile header height constant (compact, just the add button)

  /// Build single day view for mobile (full-width, no redundant header)
  Widget _buildSingleDayView(Map<DateTime, List<AppointmentModel>> byDay) {
    final dayKey = _dateOnly(_selectedDay);
    final dayAppointments = byDay[dayKey] ?? const <AppointmentModel>[];

    return _buildScrollableGrid(
      layout: _GridLayout(
        days: <DateTime>[dayKey],
        headerHeight: kMobileDayHeaderHeight,
      ),
      columns: [
        _buildTimeColumn(headerHeight: kMobileDayHeaderHeight),
        // Full-width day content (no fixed width constraint)
        Expanded(
          child: _buildMobileDayContent(_selectedDay, dayAppointments),
        ),
      ],
    );
  }

  /// Build mobile day content (full-width, simplified header with just add button)
  Widget _buildMobileDayContent(DateTime day, List<AppointmentModel> dayAppointments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact header with just the add button (date is in navigation bar)
        Container(
          height: kMobileDayHeaderHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showAddAppointmentDialog(context, day),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Randevu Ekle'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showAddEventDialog(day),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Diğer'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: Colors.deepPurple.shade50,
                    foregroundColor: Colors.deepPurple,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Time grid with appointments + events (full width)
        _buildTimeGrid(day, dayAppointments),
      ],
    );
  }

  /// Build weekly view for desktop
  Widget _buildWeeklyView(Map<DateTime, List<AppointmentModel>> byDay) {
    final List<DateTime> weekDays = List.generate(kDaysToShow, (index) => startDate!.add(Duration(days: index)));
    final double headerHeight = _dayHeaderHeightFor(weekDays);

    return _buildScrollableGrid(
      layout: _GridLayout(days: weekDays, headerHeight: headerHeight),
      columns: [
        _buildTimeColumn(headerHeight: headerHeight),
        for (final DateTime day in weekDays)
          Expanded(
            child: _buildDayColumn(
              day,
              byDay[_dateOnly(day)] ?? const <AppointmentModel>[],
              headerHeight,
            ),
          ),
      ],
    );
  }

  /// Build fallback appointments list
  Widget _buildAppointmentsList(List<AppointmentModel> appointments) {
    return Scrollbar(
      controller: _verticalCtrl,
      child: ListView.builder(
        key: const PageStorageKey('admin_appts_list_all'),
        controller: _verticalCtrl,
        addAutomaticKeepAlives: false,
        itemCount: appointments.length,
        itemBuilder: (context, index) {
          final appointment = appointments[index];
          final bool isPostponed = appointment.status == AppointmentStatus.postponed && appointment.postponedDate != null;
          final DateTime effectiveDate = isPostponed ? appointment.postponedDate! : appointment.appointmentDateTime;
          return ListTile(
            title: Text('Tarih: ${_fullFmt.format(effectiveDate)}'),
            subtitle: Text(
              'Kullanıcı: ${appointment.user?.fullName ?? 'Bilinmiyor'}\n'
                  'Tür: ${appointment.meetingType.label}\n'
                  'Durum: ${appointment.status.label}'
                  '${isPostponed ? '\n${AppointmentDateLabels.firstDate}: ${_fullFmt.format(appointment.appointmentDateTime)}\n${AppointmentDateLabels.postponedDate}: ${_fullFmt.format(appointment.postponedDate!)}' : ''}',
            ),
            trailing: Wrap(
              alignment: WrapAlignment.end,
              children: [
                LabeledActionButton(
                  dense: true,
                  icon: Icons.edit,
                  label: 'Düzenle',
                  onPressed: () =>
                      _showEditAppointmentDialog(context, appointment),
                ),
                LabeledActionButton(
                  dense: true,
                  icon: Icons.delete_outline,
                  label: 'Sil',
                  tooltip: 'Randevuyu Sil',
                  foregroundColor: Colors.red,
                  onPressed: () => _onDeleteClicked(appointment),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBarWithBack(
        title: 'Danışan Randevuları',
        showHomeButton: true,
        actions: [
          LabeledActionButton(
            icon: Icons.refresh,
            label: 'Yenile',
            onPressed: () {
              setState(() => _fetchAllAppointments());
              _loadBirthdays(forceRefresh: true);
            },
          ),
          LabeledActionButton(
            icon: Icons.date_range,
            label: 'Tarih Aralığı',
            onPressed: _pickDateRange,
          ),
          DropdownButton<MeetingType?>(
            value: selectedMeetingType,
            hint: const Text('Görüşme Türü'),
            items: meetingTypes
                .map((type) => DropdownMenuItem<MeetingType?>(value: type, child: Text(type == null ? 'Tümü' : type.label)))
                .toList(),
            onChanged: (value) => setState(() {
              selectedMeetingType = value;
              _fetchAllAppointments();
            }),
          ),
          LabeledActionButton(
            icon: Icons.filter_list,
            // The count of hidden statuses used to be a red badge on a bare
            // icon; as a label it says the same thing in words.
            label: selectedStatuses.length == AppointmentStatus.values.length
                ? 'Filtrele'
                : 'Filtrele (${AppointmentStatus.values.length - selectedStatuses.length} gizli)',
            onPressed: () => _showStatusFilterDialog(context),
          ),
          DropdownButton<String>(
            value: sortOption,
            hint: const Text('Sırala'),
            items: sortOptions.map((option) => DropdownMenuItem<String>(value: option, child: Text(option))).toList(),
            onChanged: (value) => setState(() {
              sortOption = value;
              _fetchAllAppointments();
            }),
          ),
          if (selectedMeetingType != null ||
              selectedStatuses.length != AppointmentStatus.values.length)
            LabeledActionButton(
              icon: Icons.clear,
              label: 'Filtreleri Temizle',
              onPressed: () => setState(() {
                selectedMeetingType = null;
                selectedStatuses = Set.from(AppointmentStatus.values);
                _fetchAllAppointments();
              }),
            ),
        ],
          // backgroundColor:Color(0xFF673AB7),
          // foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isMobile = constraints.maxWidth < _kMobileBreakpoint;
          
            return Column(
              children: [
                // Navigation: Daily (mobile) or Weekly (desktop)
                isMobile
                    ? _buildMobileDayNavigation()
                    : _buildDesktopWeekNavigation(),
                _buildMarkLegend(),

                // Appointments display (expanded to fill remaining space)
                Expanded(
                  child: FutureBuilder<List<AppointmentModel>>(
                    future: _appointmentsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !(_refreshingInPlace && snapshot.hasData)) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(child: Text('Randevular getirilirken hata: ${snapshot.error}'));
                      } else {
                        final appointments = snapshot.data ?? [];

                        // Fast path: group once by day to avoid scanning the whole list per day
                        // Use effective date (postponedDate if exists for postponed appointments)
                        final Map<DateTime, List<AppointmentModel>> byDay = {};
                        for (final appt in appointments) {
                          final key = _dateOnly(appt.calendarDateTime);
                          (byDay[key] ??= <AppointmentModel>[]).add(appt);
                        }

                        // Mobile: single day view
                        if (isMobile) {
                          return _buildSingleDayView(byDay);
                        }

                        // Desktop: weekly view
                        if (_isCorrectDateRange) {
                          return _buildWeeklyView(byDay);
                        } else {
                          // Fallback: list all appointments (non 6-day range)
                          return _buildAppointmentsList(appointments);
                        }
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GridLayout {
  const _GridLayout({required this.days, required this.headerHeight});

  final List<DateTime> days;
  final double headerHeight;

  CalendarGridGeometry geometry(double contentWidth) => CalendarGridGeometry(
        contentWidth: contentWidth,
        timeColumnWidth: kTimeColumnWidth,
        headerHeight: headerHeight,
        dayCount: math.max(days.length, 1),
        gridStartMinutes: kGridStartMinutes,
        gridEndMinutes: kGridEndMinutes,
        pixelsPerMinute: kPixelsPerMinute,
        snapMinutes: kSnapMinutes,
      );
}

class _AppointmentDrag {
  _AppointmentDrag({
    required this.appointment,
    required this.originalStart,
    required this.cardHeight,
    required this.grabDy,
    required this.pointer,
    required this.isClickCandidate,
  }) : _origin = pointer;

  final AppointmentModel appointment;
  final DateTime originalStart;
  final double cardHeight;
  final double grabDy;
  final bool isClickCandidate;
  final Offset _origin;
  Offset pointer;
  double travelled = 0;

  int get originalMinutes => originalStart.hour * 60 + originalStart.minute;

  void moveTo(Offset position) {
    pointer = position;
    travelled = math.max(travelled, (position - _origin).distance);
  }
}

class _TimeGridPainter extends CustomPainter {
  const _TimeGridPainter({
    required this.hourColor,
    required this.halfHourColor,
    required this.minorColor,
  });

  final Color hourColor;
  final Color halfHourColor;
  final Color minorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    final int first = (kGridStartMinutes ~/ kSnapMinutes + 1) * kSnapMinutes;
    for (int minutes = first;
        minutes < kGridEndMinutes;
        minutes += kSnapMinutes) {
      paint.color = minutes % 60 == 0
          ? hourColor
          : minutes % kTimeLabelStepMinutes == 0
              ? halfHourColor
              : minorColor;
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          (minutes - kGridStartMinutes) * kPixelsPerMinute,
          size.width,
          1,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TimeGridPainter oldDelegate) =>
      oldDelegate.hourColor != hourColor ||
      oldDelegate.halfHourColor != halfHourColor ||
      oldDelegate.minorColor != minorColor;
}

/// One positioned calendar item (a meeting or a "Diğer" event) used by the
/// column-packing layout in [_AdminAppointmentsPageState._buildPositionedItems].
/// [column] and [columnCount] are filled in during layout.
class _PositionedEntry {
  _PositionedEntry({
    required this.start,
    required this.end,
    required this.displayHeight,
    required this.card,
  });

  final DateTime start;
  final DateTime end;
  // Pre-computed render height (px). Kept separate from [end] so "Tartım" visits
  // can pack by their real short duration yet render at a readable min height.
  final double displayHeight;
  final Widget card;
  int column = 0;
  int columnCount = 1;
}
