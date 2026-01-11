import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ngy_app/providers/timeslot_manager.dart';

import '../models/appointment_model.dart';
import '../models/logger.dart';
import '../models/subs_model.dart';
import '../providers/appointment_manager.dart';
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
  DateTime _selectedDate = DateTime.now();
  MeetingType _selectedMeetingType = MeetingType.f2f;
  AppointmentType _selectedAppointmentType = AppointmentType.diger;
  TimeOfDay? _selectedTime;
  late Future<List<TimeOfDay>> _availableTimesFuture;
  late Future<List<AppointmentModel>> _userAppointmentsFuture;

  @override
  void initState() {
    super.initState();
    logger.debug('Initializing AppointmentsPage state.');
    _fetchAvailableTimes();
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
      
      // Find the latest created subscription with status == 'active'
      // Subscriptions are already ordered by startDate descending
      final activeSubscription = subscriptions.firstWhere(
        (sub) => sub.status == SubActiveStatus.active,
        orElse: () => throw Exception('Aktif paketiniz bulunmamaktadır. Lütfen önce bir paket satın alın.'),
      );

      if (!mounted) return;

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
      setState(() {
        _fetchAvailableTimes();
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

  @override
  Widget build(BuildContext context) {
    logger.info('Building AppointmentsPage');

    return Scaffold(
      appBar: const AppBarWithBack(
        title: 'Randevularım',
        backgroundColor: Colors.deepPurple,
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
                  DateFormat('dd MMMM yyyy', 'tr_TR').format(_selectedDate),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                trailing:
                    const Icon(Icons.edit_calendar, color: Colors.blueAccent),
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 45)),
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
              DateFormat('dd MMMM yyyy - HH:mm', 'tr_TR')
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
        backgroundColor: Colors.deepPurple,
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
                              DateFormat('dd MMMM yyyy - HH:mm', 'tr_TR')
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
      case AppointmentStatus.canceled:
        return 'İptal Edildi';
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
