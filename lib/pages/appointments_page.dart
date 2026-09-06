import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ngy_app/providers/timeslot_manager.dart';

import '../models/appointment_model.dart';
import '../models/logger.dart';
import '../models/subs_model.dart';
import '../providers/appointment_durations_provider.dart';
import '../providers/appointment_manager.dart';
import '../providers/sub_provider.dart';
import '../utils/diet_menu_parser.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';

final Logger logger = Logger.forClass(AppointmentsPage);

class AppointmentsPage extends StatefulWidget {
  final String userId;

  const AppointmentsPage({
    super.key,
    required this.userId,
  });

  @override
  createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  /// Minimum lead time (in days) before a user can book an appointment.
  /// Users can only see/select available slots starting this many days from
  /// today (e.g. if today is the 14th, the earliest selectable day is the 16th).
  static const int _minLeadDays = 2;

  /// Display format for the selected date, including the day-of-week name
  /// (e.g. "16.07.2026 Perşembe").
  static const String _dateWithDayFormat = 'dd.MM.yyyy EEEE';

  // ---- Per-appointment notice strings (user-facing, Turkish) ----
  /// Shown prominently on an active/weekly package's final scheduled
  /// appointment.
  static const String _lastApptNoticeTitle = 'Paketinizin Son Randevusu';
  static const String _lastApptNoticeSubtitle =
      'Bu randevu, paketinizdeki son görüşmenizdir.';

  /// Shown on a package's first appointment while its payment is incomplete.
  static const String _paymentReminderTitle =
      'Ödemenizi tamamlamanızı hatırlatır, teşekkür ederiz.';

  late DateTime _selectedDate;
  MeetingType _selectedMeetingType = MeetingType.f2f;
  AppointmentType _selectedAppointmentType = AppointmentType.diger;
  TimeOfDay? _selectedTime;
  late Future<List<TimeOfDay>> _availableTimesFuture;

  /// Upcoming appointments together with the user's subscriptions. Used to
  /// decide which per-appointment notices apply (last appointment of an
  /// active/weekly package / first appointment with an incomplete payment).
  /// Refreshed after booking or canceling so the notices stay in sync.
  late Future<_AppointmentsView> _userAppointmentsFuture;

  /// The earliest date a user is allowed to book, normalized to midnight.
  DateTime get _earliestSelectableDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .add(const Duration(days: _minLeadDays));
  }

  @override
  void initState() {
    super.initState();
    logger.debug('Initializing AppointmentsPage state.');
    // Default to the earliest bookable date (today + minimum lead time).
    _selectedDate = _earliestSelectableDate;
    _fetchAvailableTimes();
    // Load admin-configured default durations so the duration derived at
    // booking time reflects the values set in the Testing page.
    _preloadDurations();
  }

  /// Fire-and-forget load of the admin-configured default durations into the
  /// registry. Failures fall back to the built-in defaults.
  Future<void> _preloadDurations() async {
    try {
      await Provider.of<AppointmentDurationsProvider>(context, listen: false)
          .fetchDurations();
    } catch (_) {
      // Falls back to built-in defaults when the load fails.
    }
  }

  void _fetchAvailableTimes() {
    final timeslotManager =
        Provider.of<TimeslotManager>(context, listen: false);
    _availableTimesFuture =
        timeslotManager.getAvailableTimeSlotsForDate(_selectedDate);
    _userAppointmentsFuture = _loadAppointmentsView();
  }

  /// Loads all of the user's (non-deleted) appointments together with their
  /// subscriptions, keyed by id, so the per-appointment notices can be computed
  /// while building each card without additional lookups.
  Future<_AppointmentsView> _loadAppointmentsView() async {
    final appointmentManager =
        Provider.of<AppointmentManager>(context, listen: false);
    final subProvider = Provider.of<SubProvider>(context, listen: false);

    final appointments = await appointmentManager.fetchAppointments(
      null,
      showAllAppointments: true,
      userId: widget.userId,
    );
    final subscriptions = await subProvider.fetchSubscriptions(
      userId: widget.userId,
      showAllSubscriptions: true,
    );
    final subsById = <String, SubscriptionModel>{
      for (final sub in subscriptions) sub.subscriptionId: sub,
    };
    return _AppointmentsView(appointments: appointments, subsById: subsById);
  }

  Future<void> _bookAppointment() async {
    if (_selectedTime == null) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Lütfen bir saat seçin.',
      );
      return;
    }

    try {
      final appointmentManager =
          Provider.of<AppointmentManager>(context, listen: false);
      final subProvider =
          Provider.of<SubProvider>(context, listen: false);

      // Check if user already has an appointment this week
      final existingAppointments = await appointmentManager.fetchAppointments(
        null,
        showAllAppointments: true,
        userId: widget.userId,
      );
      
      // Calculate the week (Monday to Saturday) of the SELECTED appointment date
      // This ensures we check the week the user is trying to book into, not today's week
      final selectedWeekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
      final weekStartDate = DateTime(selectedWeekStart.year, selectedWeekStart.month, selectedWeekStart.day); // Monday 00:00
      final weekEndDate = weekStartDate.add(const Duration(days: 6)); // Sunday 00:00 (end of Saturday)
      
      logger.debug('Checking for existing appointments in week: {} to {}', 
        [weekStartDate, weekEndDate]);
      
      // Statuses that count as "having an appointment"
      const validStatuses = {
        AppointmentStatus.scheduled,
        AppointmentStatus.completed,
        AppointmentStatus.burned,
        AppointmentStatus.postponed,
      };
      
      // Check if there's an existing valid appointment this week (Mon-Sat)
      final hasAppointmentThisWeek = existingAppointments.any((appointment) {
        final appointmentDate = appointment.appointmentDateTime;
        final isValidStatus = validStatuses.contains(appointment.status);
        final isWithinWeek = !appointmentDate.isBefore(weekStartDate) && // >= Monday 00:00
                             appointmentDate.isBefore(weekEndDate);       // < Sunday 00:00 (i.e., up to Saturday 23:59)
        
        if (isValidStatus && isWithinWeek) {
          logger.debug('Found existing appointment this week: {} status={} date={}', 
            [appointment.appointmentId, appointment.status, appointmentDate]);
        }
        
        return isValidStatus && isWithinWeek;
      });
      
      if (!mounted) return;
      
      if (hasAppointmentThisWeek) {
        await DialogUtils.openError(
          context,
          title: 'Randevu Oluşturulamadı',
          message: 'Bu hafta için zaten bir randevunuz bulunmaktadır. Haftada yalnızca bir randevu alabilirsiniz.',
        );
        return;
      }

      // Fetch the latest active subscription
      final subscriptions = await subProvider.fetchSubscriptions(
        userId: widget.userId,
        showAllSubscriptions: true,
      );
      
      final activeSubscription = subscriptions
          .cast<SubscriptionModel?>()
          .firstWhere(
            (sub) => sub!.status.isActive,
            orElse: () => null,
          );

      if (!mounted) return;

      if (activeSubscription == null) {
        await DialogUtils.openError(
          context,
          title: 'Randevu Oluşturulamadı',
          message: 'Tanımlı bir paketiniz bulunamadı. Randevu alabilmeniz için lütfen ofis ile iletişime geçiniz.',
        );
        return;
      }

      // The active package must still have at least one remaining meeting
      // right before a new appointment can be booked.
      if (!activeSubscription.hasMeetingsLeft) {
        await DialogUtils.openError(
          context,
          title: 'Randevu Oluşturulamadı',
          message: 'Paketinizde kalan görüşme hakkınız bulunmamaktadır. Randevu alabilmeniz için lütfen ofis ile iletişime geçiniz.',
        );
        return;
      }

      DateTime appointmentDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      // Check if the selected time slot is still available
      final timeslotManager =
          Provider.of<TimeslotManager>(context, listen: false);

      List<TimeOfDay> availableTimes =
          await timeslotManager.getAvailableTimeSlotsForDate(_selectedDate);
      bool isAvailable = availableTimes.contains(_selectedTime);

      if (!mounted) return;
      if (!isAvailable) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Seçtiğiniz saat/tarih uygun değildir.',
        );
        return;
      }

      String appointmentId = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('appointments')
          .doc()
          .id;

      AppointmentModel appointment = AppointmentModel(
        appointmentId: appointmentId,
        userId: widget.userId,
        subscriptionId: activeSubscription.subscriptionId,
        meetingType: _selectedMeetingType,
        appointmentType: _selectedAppointmentType,
        durationMinutes: _selectedAppointmentType.getDurationForMeetingType(_selectedMeetingType),
        appointmentDateTime: appointmentDateTime,
        status: AppointmentStatus.scheduled,
        createDate: DateTime.now(),
        createUser: 'user', //TODO current session login kim yaptıysa o
      );

      await appointmentManager.addAppointment(appointment);

      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Randevunuz başarıyla oluşturuldu.',
      );
      if (!mounted) return;
      setState(() {
        _fetchAvailableTimes();
      });
      //bu onceki sfya götürüyor
      //Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu oluşturulurken bir hata oluştu: $e',
      );
    }
  }

  void _navigateToPastAppointments() {
    logger.debug('Navigating to past appointments page');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PastAppointmentsPage(userId: widget.userId),
      ),
    );
  }

  /// Appointments belonging to [subId], sorted by date ascending.
  List<AppointmentModel> _packageAppointments(
    _AppointmentsView view,
    String subId,
  ) {
    return view.appointments
        .where((a) => a.subscriptionId == subId)
        .toList()
      ..sort((a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime));
  }

  /// Whether [appt] is the final scheduled appointment of its active/weekly
  /// package. Upcoming scheduled slots are ordered by date; the one whose
  /// position lands exactly on the package's total meeting count is the last.
  bool _isLastAppointmentOfPackage(
    AppointmentModel appt,
    SubscriptionModel sub,
    List<AppointmentModel> packageAppointments,
  ) {
    if (sub.status != SubActiveStatus.activeWeekly) return false;

    final now = DateTime.now();
    final upcomingScheduled = packageAppointments
        .where((a) =>
            a.status == AppointmentStatus.scheduled &&
            a.appointmentDateTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime));

    final index = upcomingScheduled
        .indexWhere((a) => a.appointmentId == appt.appointmentId);
    if (index < 0) return false;

    final meetingsDone = sub.meetingsCompleted + sub.meetingsBurned;
    // 1-based meeting number this appointment represents once every earlier
    // upcoming slot has been held.
    final meetingNumber = meetingsDone + index + 1;
    return meetingNumber == sub.totalMeetings;
  }

  /// Whether [appt] is the package's very first appointment: no meeting has
  /// been held yet and this is the earliest appointment of the
  /// package.
  bool _isFirstAppointmentOfPackage(
    AppointmentModel appt,
    SubscriptionModel sub,
    List<AppointmentModel> packageAppointments,
  ) {
    final meetingsDone = sub.meetingsCompleted + sub.meetingsBurned;
    if (meetingsDone > 0) return false;
    if (packageAppointments.isEmpty) return false;
    return packageAppointments.first.appointmentId == appt.appointmentId;
  }

  /// Builds the prominent notices shown beneath [appt]'s card: "Paketinizin Son
  /// Randevusu" for an active/weekly package's final appointment and a payment
  /// reminder (with the outstanding amount) on the package's first appointment
  /// while its payment is incomplete. Returns an empty list when none apply.
  List<Widget> _buildAppointmentNotices(
    AppointmentModel appt,
    _AppointmentsView view,
  ) {
    final subId = appt.subscriptionId;
    if (subId == null || subId.isEmpty) return const [];
    final sub = view.subsById[subId];
    if (sub == null) return const [];

    final packageAppointments = _packageAppointments(view, subId);
    final notices = <Widget>[];

    if (_isLastAppointmentOfPackage(appt, sub, packageAppointments)) {
      notices.add(_buildProminentNotice(
        icon: Icons.flag_rounded,
        color: Colors.deepOrange.shade700,
        title: _lastApptNoticeTitle,
        subtitle: _lastApptNoticeSubtitle,
      ));
    }

    if (_isFirstAppointmentOfPackage(appt, sub, packageAppointments)) {
      final missing = sub.totalAmount - sub.amountPaid;
      if (missing > 0.001) {
        notices.add(_buildProminentNotice(
          icon: Icons.payments_rounded,
          color: Colors.red.shade700,
          title: _paymentReminderTitle,
          subtitle: 'Miktar: ${missing.toStringAsFixed(0)} TL',
        ));
      }
    }

    return notices;
  }

  /// A filled, high-contrast banner used to make a per-appointment notice stand
  /// out directly beneath its appointment card.
  Widget _buildProminentNotice({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    logger.info('Building AppointmentsPage');

    return Scaffold(
      appBar: const AppBarWithBack(
        title: 'Randevularım',
        //backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Meeting Type Selector
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.event_available,
                        color: Colors.deepPurple, size: 30),
                    const SizedBox(width: 8),
                    const Text(
                      'Görüşme Türü:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(width: 16),
                    DropdownButton<MeetingType>(
                      value: _selectedMeetingType,
                      onChanged: (MeetingType? newValue) {
                        setState(() {
                          _selectedMeetingType = newValue!;
                        });
                      },
                      items: MeetingType.values
                          .map<DropdownMenuItem<MeetingType>>(
                              (MeetingType value) {
                        return DropdownMenuItem<MeetingType>(
                          value: value,
                          child: Text(value.label),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Date Picker
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.calendar_today, color: Colors.blueAccent),
                title: Text(
                  DateFormat(_dateWithDayFormat, 'tr_TR').format(_selectedDate),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                trailing:
                    const Icon(Icons.edit_calendar, color: Colors.blueAccent),
                onTap: () async {
                  final earliest = _earliestSelectableDate;
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate:
                        _selectedDate.isBefore(earliest) ? earliest : _selectedDate,
                    firstDate: earliest,
                    lastDate: earliest.add(const Duration(days: 45)),
                    locale: const Locale('tr', 'TR'),
                  );
                  if (picked != null && picked != _selectedDate) {
                    setState(() {
                      _selectedDate = picked;
                      _selectedTime = null;
                    });
                    _fetchAvailableTimes();
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            // Available Time Slots
            const Text(
              'Uygun Saatler',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<TimeOfDay>>(
              future: _availableTimesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  logger.err(
                      'Error fetching available times: {}', [snapshot.error!]);
                  return Text(
                      'Zaman dilimleri alınırken bir hata oluştu.');
                } else {
                  List<TimeOfDay> availableTimes = snapshot.data ?? [];
                  // Sort the times
                  availableTimes.sort((a, b) {
                    if (a.hour != b.hour) {
                      return a.hour.compareTo(b.hour);
                    } else {
                      return a.minute.compareTo(b.minute);
                    }
                  });
                  if (availableTimes.isEmpty) {
                    return const Text(
                        'Seçilen tarih için uygun zaman dilimi yok.');
                  } else {
                    return Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: availableTimes.map((time) {
                        return ChoiceChip(
                          label: Text(
                            formatTimeOfDay24(time),
                            style: TextStyle(
                              color: _selectedTime == time
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                          selected: _selectedTime == time,
                          selectedColor: Colors.deepPurple,
                          backgroundColor: Colors.grey[200],
                          onSelected: (bool selected) {
                            setState(() {
                              _selectedTime = selected ? time : null;
                            });
                          },
                        );
                      }).toList(),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 16),
            // Book Appointment Button
            Center(
              child: ElevatedButton.icon(
                onPressed: _bookAppointment,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Randevu Al'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.green,
                  textStyle: const TextStyle(fontSize: 18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // User's Appointments
            const Text(
              'Randevularım',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple),
            ),
            const SizedBox(height: 8),
            FutureBuilder<_AppointmentsView>(
              future: _userAppointmentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  logger.err(
                      'Error fetching appointments: {}', [snapshot.error!]);
                  return Text(
                      'Randevular alınırken bir hata oluştu.');
                } else {
                  final view = snapshot.data ??
                      const _AppointmentsView(appointments: [], subsById: {});
                  return _buildAppointmentsList(view);
                }
              },
            ),
            
            // Navigate to Past Appointments Button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: _navigateToPastAppointments,
                  icon: const Icon(Icons.history),
                  label: const Text('Geçmiş Randevularım'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.deepPurple,
                    textStyle: const TextStyle(fontSize: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentsList(_AppointmentsView view) {
    final upcomingAppointments = view.appointments.where((appointment) {
      return appointment.appointmentDateTime.isAfter(DateTime.now());
    }).toList();

    if (upcomingAppointments.isEmpty) {
      return const Text('Gelecek randevunuz bulunmamaktadır.');
    }
    logger.info('Upcoming Appointments: {}', [upcomingAppointments]);
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: upcomingAppointments.length,
      itemBuilder: (context, index) {
        final AppointmentModel appointment = upcomingAppointments[index];
        final notices = _buildAppointmentNotices(appointment, view);
        final card = Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            // The subtitle now carries two lines, which a default ListTile is
            // not tall enough for.
            isThreeLine: true,
            leading: const Icon(Icons.event_note, color: Colors.deepPurple),
            title: Text(
              DateFormat('dd.MM.yyyy - HH:mm', 'tr_TR')
                  .format(appointment.appointmentDateTime),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Görüşme Türü: ${appointment.meetingType.label}'),
                const SizedBox(height: 6),
                // Appointments are no longer cancelled from the app. The icon
                // is only a marker for the notice next to it, not a button.
                Row(
                  children: [
                    Icon(Icons.cancel, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'İptal için ofisi arayınız.',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        if (notices.isEmpty) return card;
        // Attach the prominent notice(s) directly beneath their appointment
        // card so the association is unmistakable.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [card, ...notices],
        );
      },
    );
  }

}

/// Bundles the user's appointments with their subscriptions (keyed by id) so
/// the per-appointment notices can be derived while building each card without
/// extra per-item lookups.
class _AppointmentsView {
  const _AppointmentsView({required this.appointments, required this.subsById});

  /// All of the user's non-deleted appointments (any status).
  final List<AppointmentModel> appointments;

  /// The user's subscriptions keyed by [SubscriptionModel.subscriptionId].
  final Map<String, SubscriptionModel> subsById;
}

/// Page showing past appointments with pagination
class PastAppointmentsPage extends StatefulWidget {
  final String userId;

  const PastAppointmentsPage({
    super.key,
    required this.userId,
  });

  @override
  createState() => _PastAppointmentsPageState();
}

class _PastAppointmentsPageState extends State<PastAppointmentsPage> {
  List<AppointmentModel> _pastAppointments = [];
  bool _isLoading = true;
  int _currentPage = 0;
  final int _itemsPerPage = 5;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _loadPastAppointments();
  }

  Future<void> _loadPastAppointments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final appointmentManager = 
          Provider.of<AppointmentManager>(context, listen: false);
      
      final appointments = await appointmentManager.fetchAppointments(
        null,
        showAllAppointments: true,
        userId: widget.userId,
      );

      if (!mounted) return;

      final now = DateTime.now();
      final pastAppointments = appointments.where((appointment) {
        return appointment.appointmentDateTime.isBefore(now);
      }).toList();

      // Sort by date - most recent first
      pastAppointments.sort((a, b) => 
        b.appointmentDateTime.compareTo(a.appointmentDateTime));

      setState(() {
        _pastAppointments = pastAppointments;
        _totalPages = (pastAppointments.length / _itemsPerPage).ceil();
        _isLoading = false;
      });

      logger.info('Loaded ${pastAppointments.length} past appointments');
    } catch (e) {
      logger.err('Error loading past appointments: {}', [e]);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Geçmiş randevularınız yüklenirken bir hata oluştu: $e',
        );
      }
    }
  }

  List<AppointmentModel> _getPagedAppointments() {
    final startIndex = _currentPage * _itemsPerPage;
    int endIndex = startIndex + _itemsPerPage;
    
    if (endIndex > _pastAppointments.length) {
      endIndex = _pastAppointments.length;
    }
    
    if (startIndex >= _pastAppointments.length) {
      return [];
    }
    
    return _pastAppointments.sublist(startIndex, endIndex);
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      setState(() {
        _currentPage++;
      });
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pagedAppointments = _getPagedAppointments();
    
    return Scaffold(
      appBar: const AppBarWithBack(
        title: 'Geçmiş Randevularım',
       // backgroundColor: Colors.deepPurple,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(
            children: [
              Expanded(
                child: _pastAppointments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          const Text(
                            'Geçmiş randevunuz bulunmamaktadır.',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: pagedAppointments.length,
                      itemBuilder: (context, index) {
                        final appointment = pagedAppointments[index];
                        return Card(
                          elevation: 3,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: _getAppointmentStatusIcon(appointment.status),
                            title: Text(
                              DateFormat('dd.MM.yyyy - HH:mm', 'tr_TR')
                                .format(appointment.appointmentDateTime),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Görüşme Türü: ${appointment.meetingType.label}'),
                                const SizedBox(height: 2),
                                Text('Durum: ${_getStatusText(appointment.status)}',
                                  style: TextStyle(
                                    color: _getStatusColor(appointment.status),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
              if (_pastAppointments.isNotEmpty && _totalPages > 1)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _currentPage > 0 ? _prevPage : null,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(12),
                          backgroundColor: Colors.deepPurple,
                          disabledBackgroundColor:
                              Colors.grey.withValues(alpha: 0.3),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          '${_currentPage + 1} / $_totalPages',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _currentPage < _totalPages - 1 ? _nextPage : null,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(12),
                          backgroundColor: Colors.deepPurple,
                          disabledBackgroundColor:
                              Colors.grey.withValues(alpha: 0.3),
                        ),
                        child: const Icon(Icons.arrow_forward, color: Colors.white),
                      ),
                    ],
                  ),
                ),
            ],
          ),
    );
  }

  Widget _getAppointmentStatusIcon(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.completed:
      case AppointmentStatus.burned:
        return const CircleAvatar(
          backgroundColor: Colors.green,
          child: Icon(Icons.check, color: Colors.white),
        );
      case AppointmentStatus.scheduled:
        return const CircleAvatar(
          backgroundColor: Colors.blue,
          child: Icon(Icons.event_available, color: Colors.white),
        );
      default:
        return const CircleAvatar(
          backgroundColor: Colors.grey,
          child: Icon(Icons.help_outline, color: Colors.white),
        );
    }
  }

  String _getStatusText(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.completed:
        return 'Yapıldı';
      case AppointmentStatus.scheduled:
        return 'Planlandı';
      case AppointmentStatus.burned:
        return 'Yapıldı';
      case AppointmentStatus.postponed:
        return 'Ertelendi';
    }
  }

  Color _getStatusColor(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.completed:
      case AppointmentStatus.burned:
        return Colors.green;
      case AppointmentStatus.scheduled:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
