import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/appointment_model.dart';
import '../models/logger.dart';
import '../utils/dialog_utils.dart';
import '../providers/appointment_manager.dart';
import 'package:provider/provider.dart';
import '../widgets/app_bar_with_back.dart';

final Logger logger = Logger.forClass(PastAppointmentsPage);

class PastAppointmentsPage extends StatefulWidget {
  final String userId;

  const PastAppointmentsPage({super.key, required this.userId});

  @override
  createState() => _PastAppointmentsPageState();
}

class _PastAppointmentsPageState extends State<PastAppointmentsPage> {
  static const int _pageSize = 5; // Number of items per page
  int _currentPage = 1; // Current page index
  int _totalPages = 1; // Total number of pages
  List<AppointmentModel> _allAppointments = []; // All fetched appointments
  List<AppointmentModel> _filteredAppointments = []; // Filtered appointments
  List<AppointmentModel> _currentAppointments =
      []; // Appointments for the current page
  bool _isLoading = false;

  // Filters
  AppointmentStatus? _selectedStatus;
  DateTimeRange? _selectedDateRange;
  /// Newest first by default: the most recent appointment belongs at the top.
  bool _isDateAscending = false;

  late final AppointmentManager _appointmentService;

  @override
  void initState() {
    super.initState();
    _appointmentService =
        Provider.of<AppointmentManager>(context, listen: false);
    _fetchAllAppointments();
  }

  /// Fetch all past appointments and initialize pagination.
  Future<void> _fetchAllAppointments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      logger.info('Fetching all past appointments for user ${widget.userId}...');
      
      // Use the appointment manager to fetch appointments
      List<AppointmentModel> appointments = await _appointmentService.fetchAppointments(
        null,
        showAllAppointments: true,
        userId: widget.userId,
      );
      
      // Filter to past appointments only
      final now = DateTime.now();
      _allAppointments = appointments
          .where((appointment) => appointment.appointmentDateTime.isBefore(now))
          .toList();

      _applyFilters();
    } catch (e) {
      logger.err('Error fetching all past appointments: $e');
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevular alınırken bir hata oluştu: $e',
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Apply filters and sorting to the appointments list.
  void _applyFilters() {
    List<AppointmentModel> filtered = List.from(_allAppointments);

    // Apply status filter
    if (_selectedStatus != null) {
      filtered = filtered
          .where((appointment) => appointment.status == _selectedStatus)
          .toList();
    }

    // Apply date filter
    if (_selectedDateRange != null) {
      filtered = filtered.where((appointment) {
        DateTime date = appointment.appointmentDateTime;
        return date.isAfter(
                _selectedDateRange!.start.subtract(const Duration(days: 1))) &&
            date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      if (_isDateAscending) {
        return a.appointmentDateTime.compareTo(b.appointmentDateTime);
      } else {
        return b.appointmentDateTime.compareTo(a.appointmentDateTime);
      }
    });

    setState(() {
      _filteredAppointments = filtered;
      _totalPages = (_filteredAppointments.length / _pageSize).ceil();
      if (_totalPages == 0) _totalPages = 1;
      _currentPage = 1; // Reset to first page
      _setCurrentPageAppointments();
    });
  }

  /// Set the appointments for the current page by slicing the _filteredAppointments list.
  void _setCurrentPageAppointments() {
    setState(() {
      int startIndex = (_currentPage - 1) * _pageSize;
      int endIndex = startIndex + _pageSize;
      if (endIndex > _filteredAppointments.length) {
        endIndex = _filteredAppointments.length;
      }
      _currentAppointments =
          _filteredAppointments.sublist(startIndex, endIndex);
      logger.info(
          'Displaying appointments for page $_currentPage: $_currentAppointments');
    });
  }

  /// Handle page changes by updating _currentPage and setting the current appointments.
  void _changePage(int page) {
    if (page != _currentPage && page >= 1 && page <= _totalPages) {
      logger.info('Switching to page $page...');
      setState(() {
        _currentPage = page;
      });
      _setCurrentPageAppointments();
    }
  }

  Future<void> _selectDateRange() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _applyFilters();
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = null;
      _selectedDateRange = null;
      _isDateAscending = false;
    });
    _applyFilters();
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        AppointmentStatus? tempStatus = _selectedStatus;
        DateTimeRange? tempDateRange = _selectedDateRange;

        return AlertDialog(
          title: const Text('Filtrele'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<AppointmentStatus>(
                  value: tempStatus,
                  decoration: const InputDecoration(
                    labelText: 'Durum',
                  ),
                  items:
                      AppointmentStatus.values.map((AppointmentStatus status) {
                    return DropdownMenuItem<AppointmentStatus>(
                      value: status,
                      child: Text(status.label),
                    );
                  }).toList(),
                  onChanged: (AppointmentStatus? newValue) {
                    tempStatus = newValue;
                  },
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () async {
                    DateTimeRange? picked = await showDateRangePicker(
                      context: context,
                      initialDateRange: tempDateRange ??
                          DateTimeRange(
                            start: DateTime.now()
                                .subtract(const Duration(days: 30)),
                            end: DateTime.now(),
                          ),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      locale: const Locale('tr', 'TR'),
                    );
                    if (picked != null) {
                      setState(() {
                        tempDateRange = picked;
                      });
                    }
                  },
                  child: Text(
                    tempDateRange == null
                        ? 'Tarih Seçiniz'
                        : 'Seçilen Tarih: ${DateFormat('dd.MM.yyyy').format(tempDateRange.start)} - ${DateFormat('dd.MM.yyyy').format(tempDateRange.end)}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('İptal'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Uygula'),
              onPressed: () {
                setState(() {
                  _selectedStatus = tempStatus;
                  _selectedDateRange = tempDateRange;
                });
                _applyFilters();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _toggleDateSorting() {
    setState(() {
      _isDateAscending = !_isDateAscending;
      _applyFilters();
    });
  }

  Future<void> _cancelAppointment(AppointmentModel appointment) async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _appointmentService.cancelAppointment(
          appointment.appointmentId, appointment.userId,
          canceledBy: 'user');

      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Randevu başarıyla iptal edildi.',
      );
      _fetchAllAppointments();
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu iptal edilirken bir hata oluştu: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBarWithBack(
        title: 'Geçmiş Randevular',
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: Icon(
                _isDateAscending ? Icons.arrow_downward : Icons.arrow_upward),
            onPressed: _toggleDateSorting,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_selectedStatus != null || _selectedDateRange != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  if (_selectedStatus != null)
                    Chip(
                      label: Text('Durum: ${_selectedStatus!.label}'),
                      onDeleted: () {
                        setState(() {
                          _selectedStatus = null;
                        });
                        _applyFilters();
                      },
                    ),
                  if (_selectedDateRange != null)
                    Chip(
                      label: Text(
                          'Tarih: ${DateFormat('dd.MM.yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd.MM.yyyy').format(_selectedDateRange!.end)}'),
                      onDeleted: () {
                        setState(() {
                          _selectedDateRange = null;
                        });
                        _applyFilters();
                      },
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Filtreleri Temizle'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredAppointments.isEmpty
                    ? const Center(
                        child: Text('Geçmiş randevunuz bulunmamaktadır.'))
                    : ListView.builder(
                        itemCount: _currentAppointments.length,
                        itemBuilder: (context, index) {
                          final appointment = _currentAppointments[index];
                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  Icons.calendar_today,
                                  color: theme.primaryColor,
                                  size: 40,
                                ),
                                title: Text(
                                  DateFormat('dd MMMM yyyy - HH:mm', 'tr_TR')
                                      .format(appointment.appointmentDateTime),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 5),
                                    Text(
                                      'Durum: ${appointment.status.label}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      'Görüşme Türü: ${appointment.meetingType.label}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios,
                                  color: theme.primaryColor,
                                ),
                                onTap: () {
                                  // Handle tap if needed
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_totalPages > 1)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: PaginationControls(
                currentPage: _currentPage,
                totalPages: _totalPages,
                onPageChanged: _changePage,
              ),
            ),
        ],
      ),
    );
  }
}

class PaginationControls extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final Function(int) onPageChanged;

  const PaginationControls({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed:
              currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
          icon: const Icon(Icons.arrow_back_ios),
          color: theme.primaryColor,
        ),
        Text(
          '$currentPage / $totalPages',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        IconButton(
          onPressed: currentPage < totalPages
              ? () => onPageChanged(currentPage + 1)
              : null,
          icon: const Icon(Icons.arrow_forward_ios),
          color: theme.primaryColor,
        ),
      ],
    );
  }
}
