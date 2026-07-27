import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ngy_app/providers/timeslot_manager.dart';

import '../models/appointment_model.dart';
import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../providers/appointment_durations_provider.dart';
import '../providers/appointment_manager.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';
import 'meal_upload_page.dart';

final Logger logger = Logger.forClass(AppointmentsPage);

class AppointmentsPage extends StatefulWidget {
  final String userId;
  final String subscriptionId;
  final VoidCallback onAppointmentAdded;

  const AppointmentsPage({
    super.key,
    required this.userId,
    required this.subscriptionId,
    required this.onAppointmentAdded,
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

  // ---- Passive info-banner strings/formats (user-facing, Turkish) ----
  static const String _lastApptTitle = 'Son Randevu Bilgisi';
  static const String _lastApptWillBeText =
      'Bu, paketinizdeki son randevunuz olacaktır.';
  static const String _plannedPaymentTitle = 'Bekleyen Ödeme';
  static const String _plannedPaymentText =
      'Bekleyen/planlanan bir ödemeniz bulunmaktadır.';
  static const String _bannerDateTimeFormat = 'dd.MM.yyyy HH:mm';
  static const String _bannerDateFormat = 'dd.MM.yyyy';

  late DateTime _selectedDate;
  MeetingType _selectedMeetingType = MeetingType.f2f;
  AppointmentType _selectedAppointmentType = AppointmentType.diger;
  TimeOfDay? _selectedTime;
  late Future<List<TimeOfDay>> _availableTimesFuture;
  late Future<List<AppointmentModel>> _userAppointmentsFuture;

  /// Loads the passive info banners shown at the top of the page (last
  /// appointment of the package / pending planned payment). Refreshed after
  /// booking or canceling so the notices stay in sync.
  late Future<_BookingNotices> _noticesFuture;

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
    _noticesFuture = _loadBookingNotices();
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
    final appointmentManager =
        Provider.of<AppointmentManager>(context, listen: false);
    final timeslotManager =
    Provider.of<TimeslotManager>(context, listen: false);
    _availableTimesFuture =
        timeslotManager.getAvailableTimeSlotsForDate(_selectedDate);
    _userAppointmentsFuture = appointmentManager.fetchAppointments(null,
        showAllAppointments: true, userId: widget.userId);
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
      
      // Statuses that count as "having an appointment" (exclude only canceled)
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
        _refreshBookingNotices();
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

  Future<void> _cancelAppointment(AppointmentModel appointment) async {
    try {
      final appointmentManager =
          Provider.of<AppointmentManager>(context, listen: false);

      if (await appointmentManager.cancelAppointment(
          appointment.appointmentId, appointment.userId,
          canceledBy: 'user')) {
        if (!mounted) return;
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Randevu başarıyla iptal edildi.',
        );
      }
      if (!mounted) return;
      setState(() {
        _fetchAvailableTimes();
        _refreshBookingNotices();
      });
    } catch (e, stackTrace) {
      logger.err('Error canceling appointment: {}, stack trace: {}', [e,stackTrace]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu iptal edilirken bir hata oluştu: $e',
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

  /// Re-runs the notice load so the top-of-page banners reflect the latest
  /// appointment/payment state. Call inside setState.
  void _refreshBookingNotices() {
    _noticesFuture = _loadBookingNotices();
  }

  /// Loads the data needed for the passive top-of-page banners: the active
  /// subscription (if any), its appointments, and the user's planned payments.
  /// All Firebase access goes through the existing providers.
  Future<_BookingNotices> _loadBookingNotices() async {
    // Capture providers before awaiting so context isn't used across gaps.
    final subProvider = Provider.of<SubProvider>(context, listen: false);
    final appointmentManager =
        Provider.of<AppointmentManager>(context, listen: false);
    final paymentProvider =
        Provider.of<PaymentProvider>(context, listen: false);

    // The pending-payment notice is independent of the active package, so it is
    // resolved regardless of whether an active subscription exists.
    final plannedPayment = await _findPlannedPayment(paymentProvider);

    // Active subscription, using the same selection rule as _bookAppointment.
    final subscriptions = await subProvider.fetchSubscriptions(
      userId: widget.userId,
      showAllSubscriptions: true,
    );
    final activeSub = subscriptions.cast<SubscriptionModel?>().firstWhere(
          (sub) => sub!.status.isActive,
          orElse: () => null,
        );

    if (activeSub == null) {
      return _BookingNotices(plannedPayment: plannedPayment);
    }

    final appointments = await appointmentManager.fetchAppointments(
      activeSub.subscriptionId,
      showAllAppointments: false,
      userId: widget.userId,
    );

    return _BookingNotices(
      lastAppointment: _computeLastAppointmentNotice(activeSub, appointments),
      plannedPayment: plannedPayment,
    );
  }

  /// Computes the "last appointment of the package" notice for [activeSub].
  ///
  /// A scheduled upcoming appointment does not reduce
  /// [SubscriptionModel.remainingMeetings] until it becomes completed/burned, so
  /// the number of slots still bookable is
  /// `remainingMeetings - upcomingScheduled.length`:
  ///  * if every remaining slot is already booked, the latest upcoming
  ///    scheduled appointment is the package's final one (date variant);
  ///  * if exactly one slot is still bookable, the next booking will be the last.
  /// Otherwise no last-appointment banner applies.
  _LastAppointmentNotice? _computeLastAppointmentNotice(
    SubscriptionModel activeSub,
    List<AppointmentModel> appointments,
  ) {
    final now = DateTime.now();
    final upcomingScheduled = appointments
        .where((a) =>
            a.status == AppointmentStatus.scheduled &&
            a.appointmentDateTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime));

    final bookableLeft = activeSub.remainingMeetings - upcomingScheduled.length;

    if (upcomingScheduled.isNotEmpty && bookableLeft <= 0) {
      // All remaining slots are booked → the latest one is the package's last.
      return _LastAppointmentNotice.scheduled(
          upcomingScheduled.last.appointmentDateTime);
    }
    if (bookableLeft == 1) {
      // Exactly one slot remains → the appointment about to be booked is last.
      return const _LastAppointmentNotice.willBeLast();
    }
    return null;
  }

  /// Returns the most urgent planned (pending) payment for the user, or null
  /// when there is none. Uses [PaymentProvider.fetchPayments] and filters by
  /// [PaymentStatus.planned]; the earliest [PaymentModel.dueDate] wins (payments
  /// without a due date are treated as least urgent).
  Future<PaymentModel?> _findPlannedPayment(
      PaymentProvider paymentProvider) async {
    final payments = await paymentProvider.fetchPayments(
      null,
      userId: widget.userId,
      showAllPayments: true,
    );
    final planned =
        payments.where((p) => p.status == PaymentStatus.planned).toList()
          ..sort((a, b) {
            final aDate = a.dueDate;
            final bDate = b.dueDate;
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return aDate.compareTo(bDate);
          });
    return planned.isEmpty ? null : planned.first;
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
            // Passive info banners (last appointment of package / pending
            // payment). Rendered only once their data is ready.
            FutureBuilder<_BookingNotices>(
              future: _noticesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done ||
                    !snapshot.hasData ||
                    !snapshot.data!.hasAny) {
                  // Nothing while loading, on error, or when no notice applies
                  // (avoids layout jank before the data is available).
                  return const SizedBox.shrink();
                }
                return _buildNoticesSection(snapshot.data!);
              },
            ),
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
                            MealUploadPage.formatTimeOfDay24(time),
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
            FutureBuilder<List<AppointmentModel>>(
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
                  List<AppointmentModel> appointments = snapshot.data ?? [];
                  return _buildAppointmentsList(appointments);
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

  Widget _buildAppointmentsList(List<AppointmentModel> appointments) {
    final upcomingAppointments = appointments.where((appointment) {
      return appointment.appointmentDateTime.isAfter(DateTime.now()) &&
          appointment.status != AppointmentStatus.canceled /*&&
          !(appointment.isDeleted ?? false)*/;
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
        AppointmentModel appointment = upcomingAppointments[index];
        return Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.event_note, color: Colors.deepPurple),
            title: Text(
              DateFormat('dd.MM.yyyy - HH:mm', 'tr_TR')
                  .format(appointment.appointmentDateTime),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Görüşme Türü: ${appointment.meetingType.label}'),
            trailing: IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              onPressed: () async {
                bool? confirmCancel = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text("Randevuyu İptal Et"),
                      content: const Text(
                          "Bu randevuyu iptal etmek istediğinize emin misiniz?"),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                          child: const Text("Hayır"),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                          },
                          child: const Text("Evet"),
                        ),
                      ],
                    );
                  },
                );

                if (confirmCancel == true) {
                  await _cancelAppointment(appointment);
                }
              },
            ),
          ),
        );
      },
    );
  }

  // ---- Passive info-banner builders --------------------------------------

  /// Builds the stacked info-banner section shown at the top of the page.
  Widget _buildNoticesSection(_BookingNotices notices) {
    final banners = <Widget>[
      if (notices.lastAppointment != null)
        _buildLastAppointmentBanner(notices.lastAppointment!),
      if (notices.plannedPayment != null)
        _buildPlannedPaymentBanner(notices.plannedPayment!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < banners.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          banners[i],
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  /// Amber notice telling the user this is (or will be) the package's last
  /// appointment. Shows the scheduled date when the last slot is already booked.
  Widget _buildLastAppointmentBanner(_LastAppointmentNotice notice) {
    final message = notice.isAlreadyScheduled
        ? 'Paketinizdeki son randevunuz '
            '${DateFormat(_bannerDateTimeFormat, 'tr_TR').format(notice.scheduledDate!)} '
            'tarihinde planlanmıştır.'
        : _lastApptWillBeText;
    return _buildNoticeCard(
      icon: Icons.event_note,
      color: Colors.orange.shade800,
      title: _lastApptTitle,
      message: message,
    );
  }

  /// Red notice about a pending (planned) payment, including its amount and,
  /// when available, its due date.
  Widget _buildPlannedPaymentBanner(PaymentModel payment) {
    final buffer = StringBuffer(_plannedPaymentText)
      ..write('\nTutar: ${payment.amount.toStringAsFixed(2)} ₺');
    if (payment.dueDate != null) {
      buffer.write(' • Son Tarih: '
          '${DateFormat(_bannerDateFormat, 'tr_TR').format(payment.dueDate!)}');
    }
    return _buildNoticeCard(
      icon: Icons.payments_outlined,
      color: Colors.red.shade700,
      title: _plannedPaymentTitle,
      message: buffer.toString(),
    );
  }

  /// Shared Material 3 styled info card used by the passive banners.
  Widget _buildNoticeCard({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Card(
      elevation: 2,
      color: color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Immutable view-model for the passive info banners shown at the top of the
/// booking page (see [_AppointmentsPageState]). Built once from the active
/// subscription, its appointments, and the user's planned payments.
class _BookingNotices {
  const _BookingNotices({this.lastAppointment, this.plannedPayment});

  /// Notice about the active package's last appointment, or null when it does
  /// not currently apply.
  final _LastAppointmentNotice? lastAppointment;

  /// The most urgent planned (pending) payment, or null when the user has none.
  final PaymentModel? plannedPayment;

  /// Whether at least one banner should be shown.
  bool get hasAny => lastAppointment != null || plannedPayment != null;
}

/// Describes the "last appointment of the package" notice: either the package's
/// final slot is already booked ([_LastAppointmentNotice.scheduled], carrying
/// its [scheduledDate]) or the next booking will become the last one
/// ([_LastAppointmentNotice.willBeLast]).
class _LastAppointmentNotice {
  const _LastAppointmentNotice.scheduled(DateTime this.scheduledDate)
      : isAlreadyScheduled = true;

  const _LastAppointmentNotice.willBeLast()
      : isAlreadyScheduled = false,
        scheduledDate = null;

  /// Whether the package's last appointment is already booked/scheduled.
  final bool isAlreadyScheduled;

  /// Date of the already-scheduled last appointment; non-null only when
  /// [isAlreadyScheduled] is true.
  final DateTime? scheduledDate;
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

      // Filter past appointments including canceled ones
      final now = DateTime.now();
      final pastAppointments = appointments.where((appointment) {
        return appointment.appointmentDateTime.isBefore(now) ||
            appointment.status == AppointmentStatus.canceled;
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
                          disabledBackgroundColor: Colors.grey.withOpacity(0.3),
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
                          disabledBackgroundColor: Colors.grey.withOpacity(0.3),
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
      case AppointmentStatus.canceled:
        return const CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.close, color: Colors.white),
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
      case AppointmentStatus.canceled:
        return 'İptal Edildi';
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
      case AppointmentStatus.canceled:
        return Colors.red;
      case AppointmentStatus.scheduled:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
