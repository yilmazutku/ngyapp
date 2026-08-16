import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../dialogs/add_appointment_dialog.dart';
import '../models/appointment_model.dart';
import '../models/event_model.dart';
import '../models/logger.dart';
import '../models/user_model.dart';
import '../providers/appointment_colors_provider.dart';
import '../providers/appointment_manager.dart';
import '../providers/event_provider.dart';
import '../dialogs/edit_appointment_dialog.dart';
import '../dialogs/edit_event_dialog.dart';
import '../dialogs/overlap_warning_dialog.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';

final Logger logger = Logger.forClass(AdminAppointmentsPage);

// Configuration constants
const bool kIsScrollable = true; // horizontal scrolling
const double kMainMargin = 4.0; // Margin around the day columns
const double kDayTitleFontSize = 14.0; // Font size for the day header
const int kDaysToShow = 7; // Monday to Sunday (7 days)

// Time grid constants
const int kStartHour = 8; // grid starts at 08:30 (see kStartMinute)
const int kStartMinute = 30; // minute-of-hour the grid starts at
const int kEndHour = 20; // grid ends at 20:00
// Grid boundaries expressed in minutes-from-midnight.
const int kGridStartMinutes = kStartHour * 60 + kStartMinute; // 510 (08:30)
const int kGridEndMinutes = kEndHour * 60; // 1200 (20:00)
// First full-hour label/line at or after the grid start (09:00 when 08:30).
const int kFirstFullHour = kStartMinute == 0 ? kStartHour : kStartHour + 1;
const double kTotalGridHeight = 900; // Total height for the time grid (adjust to fit more/less on screen)
/*1320:big
660 → 1 px/min, fits twice as much, smaller cards
990 → 1.5 px/min, good balance
1980 → 3 px/min, larger cards, more scrolling*/

const double kTimeColumnWidth = 50.0; // Width of the time labels column
const double kDayHeaderHeight = 54.0; // Height for day title + add button
const double kDayDividerWidth = 1; // Width of vertical dividing lines between days (editable)

const double kCanceledCardHeight = 26.0;
const double kCanceledDividerHeight = 8.0;

// Calculated: pixels per minute based on total height and hours
// 11 hours (9-20) = 660 minutes, so kTotalGridHeight / 660 = pixels per minute
const double kPixelsPerMinute =
    kTotalGridHeight / (kGridEndMinutes - kGridStartMinutes);

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
  bool hideCanceled = false; // Toggle for hiding canceled appointments

  MeetingType? selectedMeetingType;
  Set<AppointmentStatus> selectedStatuses = Set.from(AppointmentStatus.values);
  String? sortOption = 'Tarih Artan';

  final List<MeetingType?> meetingTypes = [null, ...MeetingType.values];
  final List<AppointmentStatus?> meetingStatuses = [null, ...AppointmentStatus.values];
  final List<String> sortOptions = ['Tarih Artan', 'Tarih Azalan', 'İsim A-Z', 'İsim Z-A'];

  late Future<List<AppointmentModel>> _appointmentsFuture;
  List<EventModel> _events = [];

  // Scroll controllers + keys (avoid "no ScrollPosition" and preserve positions)
  late final ScrollController _verticalCtrl;
  late final ScrollController _horizontalCtrl;

  static const _kVerticalKey = PageStorageKey('admin_appts_vertical');
  static const _kHorizontalKey = PageStorageKey('admin_appts_horizontal');

  // Mobile daily view: selected day for single-day display
  late DateTime _selectedDay;

  // Threshold for mobile view (single day) vs desktop view (weekly)
  static const double _kMobileBreakpoint = 600.0;

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
    _horizontalCtrl = ScrollController();

    _fetchAllAppointments();
    _fetchEvents();
  }

  @override
  void dispose() {
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    super.dispose();
  }

  /// Initiates fetching of all appointments
  void _fetchAllAppointments() {
    _appointmentsFuture = _fetchAppointmentsWithUsers();
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
      logger.err('Error fetching events: {}', [e]);
    }
  }

  void _showAddEventDialog(BuildContext context, DateTime selectedDate) {
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
                Navigator.pop(dialogContext);
                try {
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

  Widget _buildEventCard(EventModel event) {
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
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.deepPurple.shade50,
          borderRadius: BorderRadius.circular(1),
          border: Border.all(color: Colors.deepPurple.shade200, width: 1),
        ),
        child: Text(
          displayText,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
          maxLines: 3,
        ),
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
      
      // Filter canceled if needed
      if (hideCanceled) {
        filtered = filtered.where((a) => a.status != AppointmentStatus.canceled).toList();
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
        logger.err('Failed to load appointment colors: {}', [e]);
      }

      // Apply filters on Firebase side for better performance
      final fetchedAppointments = await appointmentManager.fetchAppointmentsWithUsers(
        startDate: startDate,
        endDate: endDate,
        meetingTypeFilter: selectedMeetingType,
        statusesFilter: hideCanceled 
            ? selectedStatuses.where((s) => s != AppointmentStatus.canceled).toSet()
            : selectedStatuses,
      );

      // Only client-side sorting remains (Firebase doesn't support complex multi-field sorting)
      return _applySorting(fetchedAppointments);
    } catch (e) {
      logger.err('Randevular getirilirken hata oluştu: {}', [e]);
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

  /// Get the effective date for sorting/grouping (postponedDate if exists, otherwise appointmentDateTime)
  DateTime _getEffectiveDate(AppointmentModel appt) {
    return (appt.status == AppointmentStatus.postponed && appt.postponedDate != null)
        ? appt.postponedDate!
        : appt.appointmentDateTime;
  }

  /// Apply client-side sorting to appointments (filtering now done on Firebase)
  /// Kept client-side because Firebase doesn't support complex multi-field sorting
  List<AppointmentModel> _applySorting(List<AppointmentModel> appointments) {
    // Sort appointments based on selected option
    // For postponed appointments, use postponedDate if exists
    appointments.sort((a, b) {
      switch (sortOption) {
        case 'Tarih Artan':
          return _getEffectiveDate(a).compareTo(_getEffectiveDate(b));
        case 'Tarih Azalan':
          return _getEffectiveDate(b).compareTo(_getEffectiveDate(a));
        case 'İsim A-Z':
          return (a.user?.name ?? '').compareTo(b.user?.name ?? '');
        case 'İsim Z-A':
          return (b.user?.name ?? '').compareTo(a.user?.name ?? '');
        default:
          return 0;
      }
    });

    logger.info('Sorted {} appointments by: {}', [appointments.length, sortOption]);
    return appointments;
  }

  /// Cancel an appointment
  Future<void> _cancelAppointment(AppointmentModel appointment) async {
    try {
      final appointmentManager = Provider.of<AppointmentManager>(context, listen: false);
      final success = await appointmentManager.cancelAppointment(
        appointment.appointmentId,
        appointment.userId,
        canceledBy: 'Admin',
      );

      if (!mounted) return;
      if (success) {
        await DialogUtils.openInfo(context, title: 'Başarılı', message: 'Randevu başarıyla iptal edildi.');
        _fetchAllAppointments();
        setState(() {}); // ensure FutureBuilder re-runs if needed
      } else {
        await DialogUtils.openError(context, title: 'Hata', message: 'Randevu iptal edilemedi.');
      }
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu iptal edilirken bir hata oluştu: $e',
      );
    }
  }

  /// Confirm and delete an appointment
  void _onDeleteClicked(AppointmentModel appt) async {
    final confirmDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Randevu İptali"),
          content: const Text("Bu randevuyu iptal etmek istediğinizden emin misiniz?"),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Hayır")),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Evet")),
          ],
        );
      },
    );
    if (confirmDelete == true) {
      await _cancelAppointment(appt);
    }
  }

  /// Show dialog to edit an appointment
  void _showEditAppointmentDialog(BuildContext context, AppointmentModel appointment) {
    logger.info('opening edit appt dialog for apptId:{}',[appointment.appointmentId]);
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
    logger.info('opening edit event dialog for eventId:{}', [event.eventId]);
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

  /// Effective start time of an appointment (postponed date wins when set).
  DateTime _effectiveTime(AppointmentModel appt) =>
      (appt.status == AppointmentStatus.postponed && appt.postponedDate != null)
          ? appt.postponedDate!
          : appt.appointmentDateTime;

  /// Whether the given time falls within the visible grid window.
  bool _isWithinGrid(DateTime t) {
    final minutes = t.hour * 60 + t.minute;
    return minutes >= kGridStartMinutes && minutes < kGridEndMinutes;
  }

  /// Builds the positioned appointment cards for a day. Appointments that START
  /// at the exact same time are split into equal side-by-side columns so they
  /// don't cover each other (e.g. two 09:30 meetings). Appointments that merely
  /// overlap — a long meeting spanning shorter ones with different start times —
  /// are intentionally left full-width; each start-time group is laid out on its
  /// own, so those cases are not disturbed.
  List<Widget> _buildPositionedAppointments(
      List<AppointmentModel> dayAppointments, double columnWidth) {
    // Visible (in-grid, non-canceled) appointments only.
    final visible = dayAppointments
        .where((appt) =>
            appt.status != AppointmentStatus.canceled &&
            _isWithinGrid(_effectiveTime(appt)))
        .toList();

    // Group appointments by identical start time (hour:minute).
    final Map<int, List<AppointmentModel>> sameStart = {};
    for (final appt in visible) {
      final eff = _effectiveTime(appt);
      final key = eff.hour * 60 + eff.minute;
      (sameStart[key] ??= <AppointmentModel>[]).add(appt);
    }

    final List<Widget> widgets = [];
    for (final group in sameStart.values) {
      final int n = group.length;
      for (int i = 0; i < n; i++) {
        final appt = group[i];
        final eff = _effectiveTime(appt);
        final top = _getTopPositionForTime(eff);
        final height = _getHeightForDuration(appt.durationMinutes);
        if (n == 1) {
          // Lone meeting: full column width.
          widgets.add(Positioned(
            top: top,
            left: 0,
            right: 0,
            height: height,
            child: _buildAppointmentCard(appt),
          ));
        } else {
          // Same-start group: equal side-by-side columns.
          final double w = columnWidth / n;
          widgets.add(Positioned(
            top: top,
            left: i * w,
            width: w,
            height: height,
            child: _buildAppointmentCard(appt),
          ));
        }
      }
    }
    return widgets;
  }

  /// Calculate the height for an appointment based on its duration
  double _getHeightForDuration(int durationMinutes) {
    return durationMinutes * kPixelsPerMinute;
  }

  /// Total height of the time grid area
  double get _timeGridHeight => kTotalGridHeight;

  /// Appointment card (lightweight build) - now fills its positioned container
  Widget _buildAppointmentCard(AppointmentModel appt) {
    final bool isPostponed = appt.status == AppointmentStatus.postponed && appt.postponedDate != null;
    final DateTime effectiveTime = isPostponed ? appt.postponedDate! : appt.appointmentDateTime;
    
    // Calculate end time
    final DateTime endTime = effectiveTime.add(Duration(minutes: appt.durationMinutes));
    final String timeRange = '${_timeFmt.format(effectiveTime)}-${_timeFmt.format(endTime)}';

    // Box text: "{saat} {DosyaNo}-{Ad Soyad}". The meeting type is intentionally
    // NOT shown, and the file number + dash is omitted when the client has none.
    final String nameSurname = '${appt.user!.name} ${appt.user!.surname}';
    final String? dosyaNo = appt.user!.dosyaNo?.trim();
    final String namePart = (dosyaNo != null && dosyaNo.isNotEmpty)
        ? '$dosyaNo-$nameSurname'
        : nameSurname;
    final String displayText = '$timeRange $namePart';

    final Color cardColor = appt.appointmentType.getBgColor(appt.meetingType);
    final Color borderColor = appt.appointmentType.getBorderColor(appt.meetingType);
      double fontSize=appt.durationMinutes>29?11:10;
    return GestureDetector(
      onTap: () => _showEditAppointmentDialog(context, appt),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(1),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold/*fontSize==11?FontWeight.bold:FontWeight.normal*/),
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
            ),
            // Show canceled indicator
            if (appt.status == AppointmentStatus.canceled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'İptal',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanceledCard(AppointmentModel appt) {
    final String name =
        '${appt.user?.name ?? ''} ${appt.user?.surname ?? ''}'.trim();
    final String notes = appt.notes?.trim() ?? '';
    return GestureDetector(
      onTap: () => _showEditAppointmentDialog(context, appt),
      child: Container(
        height: kCanceledCardHeight,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(1),
          border: Border.all(color: Colors.grey.shade400, width: 1),
        ),
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              decoration: TextDecoration.lineThrough,
            ),
            children: [
              TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (notes.isNotEmpty) TextSpan(text: ' - ($notes)'),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildCanceledSection(List<AppointmentModel> canceled) {
    if (canceled.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 2,
          margin: const EdgeInsets.symmetric(vertical: (kCanceledDividerHeight - 2) / 2),
          color: Colors.grey.shade500,
        ),
        ...canceled.map(_buildCanceledCard),
      ],
    );
  }

  double _canceledSectionHeight(int count) =>
      count > 0 ? kCanceledDividerHeight + count * kCanceledCardHeight : 0;

  int _maxCanceledCount(Map<DateTime, List<AppointmentModel>> byDay) {
    int maxCount = 0;
    byDay.forEach((_, list) {
      final c = list.where((a) => a.status == AppointmentStatus.canceled).length;
      if (c > maxCount) maxCount = c;
    });
    return maxCount;
  }

  List<AppointmentModel> _canceledOf(List<AppointmentModel> list) =>
      list.where((a) => a.status == AppointmentStatus.canceled).toList();

  /// Build the time column on the left side
  /// [headerHeight] allows adjusting the top spacer to align with different header sizes
  Widget _buildTimeColumn({double? headerHeight}) {
    final effectiveHeaderHeight = headerHeight ?? kDayHeaderHeight;
    // Full-hour labels from the first full hour (09:00 when the grid starts at
    // 08:30) up to and including kEndHour.
    final hours =
        List.generate(kEndHour - kFirstFullHour + 1, (i) => kFirstFullHour + i);

    Widget label(String text, double height) {
      return SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, top: 0),
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: kTimeColumnWidth,
      child: Column(
        children: [
          // Header spacer to align with day headers
          SizedBox(height: effectiveHeaderHeight),
          // Partial first slot label (e.g. 08:30) when the grid doesn't start
          // on a full hour.
          if (kStartMinute != 0)
            label(
              '${kStartHour.toString().padLeft(2, '0')}:${kStartMinute.toString().padLeft(2, '0')}',
              (60 - kStartMinute) * kPixelsPerMinute,
            ),
          // Full-hour labels.
          ...hours.map((hour) => label(
                '${hour.toString().padLeft(2, '0')}:00',
                hour < kEndHour ? 60 * kPixelsPerMinute : 0,
              )),
        ],
      ),
    );
  }

  /// Build a day column with appointments positioned by time
  Widget _buildDayColumn(DateTime day, List<AppointmentModel> dayAppointments, double columnWidth) {
    final String dayTitle = _dayTitleFmt.format(day);
    
    return Container(
      width: columnWidth,
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
            height: kDayHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: kMainMargin, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  dayTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: kDayTitleFontSize),
                  overflow: TextOverflow.ellipsis,
                ),
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
                          onPressed: () => _showAddEventDialog(context, day),
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
          SizedBox(
            height: _timeGridHeight,
            child: Stack(
              children: [
                // Hour grid lines (aligned to full hours; grid starts at 08:30)
                ...List.generate(kEndHour - kFirstFullHour, (i) {
                  final hour = kFirstFullHour + i;
                  final top =
                      (hour * 60 - kGridStartMinutes) * kPixelsPerMinute;
                  return Positioned(
                    top: top,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 1,
                      color: Colors.grey[300],
                    ),
                  );
                }),
                // Appointments — meetings that START at the same time are placed
                // side by side so they don't cover each other.
                ..._buildPositionedAppointments(dayAppointments, columnWidth),
                // Events
                ..._eventsForDay(day).map((event) {
                  if (!_isWithinGrid(event.startDateTime)) {
                    return const SizedBox.shrink();
                  }
                  final top = _getTopPositionForTime(event.startDateTime);
                  final height =
                      _getHeightForDuration(event.durationMinutes);
                  return Positioned(
                    top: top,
                    left: 0,
                    right: 0,
                    height: height,
                    child: _buildEventCard(event),
                  );
                }),
              ],
            ),
          ),
          _buildCanceledSection(_canceledOf(dayAppointments)),
        ],
      ),
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
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            tooltip: 'Önceki Gün',
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
                ],
              ),
            ),
          ),
          // Next day button
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 28),
            tooltip: 'Sonraki Gün',
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
              ? IconButton(icon: prevIcon, tooltip: 'Önceki Hafta', onPressed: goPrev)
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
              ? IconButton(icon: nextIcon, tooltip: 'Sonraki Hafta', onPressed: goNext)
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

  // ==================== Content Views ====================

  // Mobile header height constant (compact, just the add button)
  static const double _kMobileHeaderHeight = 36.0;

  /// Build single day view for mobile (full-width, no redundant header)
  Widget _buildSingleDayView(Map<DateTime, List<AppointmentModel>> byDay) {
    final dayKey = _dateOnly(_selectedDay);
    final dayAppointments = byDay[dayKey] ?? const <AppointmentModel>[];
    
    final totalHeight = _kMobileHeaderHeight +
        _timeGridHeight +
        _canceledSectionHeight(_canceledOf(dayAppointments).length);

    Widget gridContent = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTimeColumn(headerHeight: _kMobileHeaderHeight),
        // Full-width day content (no fixed width constraint)
        Expanded(
          child: _buildMobileDayContent(_selectedDay, dayAppointments),
        ),
      ],
    );

    return Scrollbar(
      controller: _verticalCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        key: _kVerticalKey,
        controller: _verticalCtrl,
        child: SizedBox(
          height: totalHeight,
          child: gridContent,
        ),
      ),
    );
  }

  /// Build mobile day content (full-width, simplified header with just add button)
  Widget _buildMobileDayContent(DateTime day, List<AppointmentModel> dayAppointments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact header with just the add button (date is in navigation bar)
        Container(
          height: _kMobileHeaderHeight,
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
                  onPressed: () => _showAddEventDialog(context, day),
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
        SizedBox(
          height: _timeGridHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // Hour grid lines (aligned to full hours; grid starts at 08:30)
                  ...List.generate(kEndHour - kFirstFullHour, (i) {
                    final hour = kFirstFullHour + i;
                    final top =
                        (hour * 60 - kGridStartMinutes) * kPixelsPerMinute;
                    return Positioned(
                      top: top,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 1,
                        color: Colors.grey[300],
                      ),
                    );
                  }),
                  // Appointments — same-start meetings shown side by side.
                  ..._buildPositionedAppointments(
                      dayAppointments, constraints.maxWidth),
                  // Events
                  ..._eventsForDay(day).map((event) {
                    if (!_isWithinGrid(event.startDateTime)) {
                      return const SizedBox.shrink();
                    }
                    final top = _getTopPositionForTime(event.startDateTime);
                    final height =
                        _getHeightForDuration(event.durationMinutes);
                    return Positioned(
                      top: top,
                      left: 0,
                      right: 0,
                      height: height,
                      child: _buildEventCard(event),
                    );
                  }),
                ],
              );
            },
          ),
        ),
        _buildCanceledSection(_canceledOf(dayAppointments)),
      ],
    );
  }

  /// Build weekly view for desktop
  Widget _buildWeeklyView(Map<DateTime, List<AppointmentModel>> byDay, double screenWidth) {
    final columnWidth = screenWidth / kDaysToShow;
    final List<DateTime> weekDays = List.generate(kDaysToShow, (index) => startDate!.add(Duration(days: index)));
    final totalHeight = kDayHeaderHeight +
        _timeGridHeight +
        _canceledSectionHeight(_maxCanceledCount(byDay));

    Widget dayColumnsRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: weekDays.map((day) {
        final dayKey = _dateOnly(day);
        final dayAppointments = byDay[dayKey] ?? const <AppointmentModel>[];
        return _buildDayColumn(day, dayAppointments, columnWidth);
      }).toList(),
    );

    Widget scrollableDayColumns = SingleChildScrollView(
      key: _kHorizontalKey,
      controller: _horizontalCtrl,
      scrollDirection: Axis.horizontal,
      child: dayColumnsRow,
    );

    Widget gridContent = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTimeColumn(),
        Expanded(child: scrollableDayColumns),
      ],
    );

    return Scrollbar(
      controller: _verticalCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        key: _kVerticalKey,
        controller: _verticalCtrl,
        child: SizedBox(
          height: totalHeight,
          child: gridContent,
        ),
      ),
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
              'Kullanıcı: ${appointment.user?.name ?? 'Bilinmiyor'}\n'
                  'Tür: ${appointment.meetingType.label}\n'
                  'Durum: ${appointment.status.label}\n'
                  '${isPostponed ? 'Orijinal: ${_fullFmt.format(appointment.appointmentDateTime)}\nErtelenen: ${_fullFmt.format(appointment.postponedDate!)}\n' : ''}'
                  'İptal Eden: ${appointment.canceledBy ?? 'Yok'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showEditAppointmentDialog(context, appointment),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red),
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
        title: 'Admin Randevuları',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() => _fetchAllAppointments())),
          IconButton(icon: const Icon(Icons.date_range), onPressed: _pickDateRange),
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
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.filter_list),
                if (selectedStatuses.length != AppointmentStatus.values.length)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                      constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                      child: Text(
                        '${AppointmentStatus.values.length - selectedStatuses.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 8),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
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
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Filtreleri Temizle',
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isMobile = constraints.maxWidth < _kMobileBreakpoint;
          
          return Column(
            children: [
              // Navigation: Daily (mobile) or Weekly (desktop)
              isMobile
                  ? _buildMobileDayNavigation()
                  : _buildDesktopWeekNavigation(),

              // Appointments display (expanded to fill remaining space)
              Expanded(
                child: FutureBuilder<List<AppointmentModel>>(
                  future: _appointmentsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      logger.err('Randevular getirilirken hata: {}', [snapshot.error ?? '']);
                      return Center(child: Text('Randevular getirilirken hata: ${snapshot.error}'));
                    } else {
                      final appointments = snapshot.data ?? [];

                      // Fast path: group once by day to avoid scanning the whole list per day
                      // Use effective date (postponedDate if exists for postponed appointments)
                      final Map<DateTime, List<AppointmentModel>> byDay = {};
                      for (final appt in appointments) {
                        final key = _dateOnly(_getEffectiveDate(appt));
                        (byDay[key] ??= <AppointmentModel>[]).add(appt);
                      }

                      // Mobile: single day view
                      if (isMobile) {
                        return _buildSingleDayView(byDay);
                      }

                      // Desktop: weekly view
                      if (_isCorrectDateRange) {
                        return _buildWeeklyView(byDay, constraints.maxWidth);
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
    );
  }
}
