// dialogs/add_appointment_dialog.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/appointment_model.dart';
import '../models/user_model.dart';
import '../models/logger.dart';
import '../models/subs_model.dart';
import '../providers/appointment_manager.dart';
import '../providers/sub_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import 'package:intl/intl.dart';
import '../dialogs/dialog_widgets.dart'; // Import dialog widgets
import '../widgets/loading_overlay.dart';

final Logger logger = Logger.forClass(AddAppointmentDialog);

class AddAppointmentDialog extends StatefulWidget {
  final DateTime? selectedDate;
  final String? userId; // For customer scenario
  final VoidCallback onAppointmentAdded;
  final bool hideDateSelection; // Hide date picker when date is pre-selected (e.g., from admin page)

  const AddAppointmentDialog({
    super.key,
    this.selectedDate,
    this.userId,
    required this.onAppointmentAdded,
    this.hideDateSelection = false,
  });

  @override
  createState() => _AddAppointmentDialogState();
}

class _AddAppointmentDialogState extends State<AddAppointmentDialog> 
    with LoadingStateMixin {
  final _formKey = GlobalKey<FormState>();
  UserModel? _selectedUser;
  MeetingType _selectedMeetingType = MeetingType.f2f;
  AppointmentType _selectedAppointmentType = AppointmentType.haftalik;
  AppointmentStatus _selectedStatus = AppointmentStatus.scheduled;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  DateTime _selectedDate = DateTime.now();
  DateTime? _postponedDate;
  List<UserModel> _users = [];
  
  // Subscription related variables
  List<SubscriptionModel> _subscriptions = [];
  SubscriptionModel? _selectedSubscription;
  bool _isLoadingSubscriptions = false;
  
  // Notes controller
  final _notesController = TextEditingController();
  
  // Duration controller
  final _durationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.selectedDate != null) {
      _selectedDate = widget.selectedDate!;
    }
    
    // Initialize duration with selected appointment type's default (considering meeting type)
    _durationController.text = _selectedAppointmentType.getDurationForMeetingType(_selectedMeetingType).toString();
    
    if (widget.userId != null) {
      // If userId is provided, we're in customer scenario
      _loadUserDetails();
      // Also load subscriptions for this user
      _fetchSubscriptions(widget.userId!);
    } else {
      // If no userId, we're in admin scenario
      _loadUsers();
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserDetails() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = await userProvider.fetchUserDetails(userId: widget.userId!);

      if (user != null) {
        setState(() {
          _selectedUser = user;
        });
      } else {
        logger.err('User not found with ID: {}', [widget.userId]);
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Kullanıcı bulunamadı.',
          );
        }
      }
    } catch (e) {
      logger.err('Error loading user details: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Kullanıcı bilgileri yüklenirken bir hata oluştu: $e',
        );
      }
    }
  }

  Future<void> _fetchSubscriptions(String userId) async {
    setState(() {
      _isLoadingSubscriptions = true;
    });

    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final List<SubscriptionModel> activeSubscriptions =
      await subProvider.fetchSubscriptions(
        userId: userId,
        showAllSubscriptions: false, // Only active subscriptions
      );

      setState(() {
        _subscriptions = activeSubscriptions;
        _isLoadingSubscriptions = false;
        
        // Select the first subscription if available
        if (_subscriptions.isNotEmpty) {
          _selectedSubscription = _subscriptions.first;
        } else {
          _selectedSubscription = null;
        }
      });
      
      // Show error if no active subscriptions found
      if ((activeSubscriptions.isEmpty || _selectedSubscription == null)) {
        logger.err(
            'Error setting selectedSubscription. activeSubscriptions.isEmpty={}, _selectedSub==null={}',
            [activeSubscriptions.isEmpty, _selectedSubscription == null]);
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Uyarı',
            message:
                'Bu kullanıcının aktif aboneliği bulunmamaktadır. Randevu eklemek için önce bir abonelik eklemelisiniz.',
          );
        }
      }
    } catch (e) {
      logger.err('Error fetching subscriptions: {}', [e]);
      setState(() {
        _isLoadingSubscriptions = false;
      });
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Abonelikler yüklenirken bir hata oluştu: $e',
        );
      }
    }
  }

  Future<void> _loadUsers() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final users = await userProvider.fetchAllCustomers();

      setState(() {
        _users = users;
      });
    } catch (e) {
      logger.err('Error loading users: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Kullanıcılar yüklenirken bir hata oluştu: $e',
        );
      }
    }
  }

  // Modified to use the DatePickerFormField
  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    logger.info('Selected date: {}', [date]);
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _saveAppointment() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Additional validation for required subscription
    if (_selectedSubscription == null) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Lütfen bir abonelik seçin.',
      );
      return;
    }
    
    // Validate postponed date if status is "Ertelendi"
    if (_selectedStatus == AppointmentStatus.postponed && _postponedDate == null) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Lütfen ertelenen tarih için bir tarih seçiniz.',
      );
      return;
    }

    // Show confirmation dialog
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Randevu Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Aşağıdaki randevuyu eklemek istediğinizden emin misiniz?'),
              const SizedBox(height: 16),
              Text('Kullanıcı: ${_selectedUser!.name}'),
              Text('Tarih: ${DateFormat('d MMMM yyyy', 'tr_TR').format(_selectedDate)}'),
              Text('Saat: ${_selectedTime.format(context)}'),
              Text('Görüşme Tipi: ${_selectedMeetingType.label}'),
              Text('Randevu Türü: ${_selectedAppointmentType.lbl}'),
              Text('Görüşme Süresi: ${_durationController.text.isNotEmpty ? _durationController.text : _selectedAppointmentType.getDurationForMeetingType(_selectedMeetingType)} dk'),
              Text('Durum: ${_selectedStatus.label}'),
              if (_selectedStatus == AppointmentStatus.postponed && _postponedDate != null)
                Text(
                  'Ertelenen Tarih: ${DateFormat('d MMMM yyyy, HH:mm', 'tr_TR').format(_postponedDate!)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              Text('Abonelik: ${_selectedSubscription!.packageName}'),
              if (_notesController.text.isNotEmpty)
                Text('Notlar: ${_notesController.text}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Evet'),
            ),
          ],
        );
      },
    );
  logger.info('shouldSave={}',[shouldSave]);
    if (shouldSave != true) return;

    startLoading();

    try {
      final appointmentManager =
          Provider.of<AppointmentManager>(context, listen: false);
      final durationMinutes = int.tryParse(_durationController.text) ?? _selectedAppointmentType.getDurationForMeetingType(_selectedMeetingType);
      final appointment = AppointmentModel(
        appointmentId: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: widget.userId ?? _selectedUser!.userId,
        subscriptionId: _selectedSubscription!.subscriptionId,
        appointmentDateTime: DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          _selectedTime.hour,
          _selectedTime.minute,
        ),
        meetingType: _selectedMeetingType,
        appointmentType: _selectedAppointmentType,
        status: _selectedStatus,
        createDate: DateTime.now(),
        createUser: widget.userId != null ? 'user' : 'admin',
        notes: _notesController.text,
        postponedDate: _selectedStatus == AppointmentStatus.postponed ? _postponedDate : null,
        durationMinutes: durationMinutes,
      );

        await appointmentManager.addAppointment(appointment);
        widget.onAppointmentAdded();

      if (mounted) {
        Navigator.of(context).pop();
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Randevu detayları:\n\n'
              'Kullanıcı: ${widget.userId != null ? _selectedUser!.name : _selectedUser!.name}\n'
              'Tarih: ${DateFormat('d MMMM yyyy', 'tr_TR').format(_selectedDate)}\n'
              'Saat: ${_selectedTime.format(context)}\n'
              'Görüşme Tipi: ${_selectedMeetingType.label}\n'
              'Randevu Türü: ${_selectedAppointmentType.lbl}\n'
              'Görüşme Süresi: $durationMinutes dk\n'
              'Durum: ${_selectedStatus.label}\n'
              '${_selectedStatus == AppointmentStatus.postponed && _postponedDate != null ? 'Ertelenen Tarih: ${DateFormat('d MMMM yyyy, HH:mm', 'tr_TR').format(_postponedDate!)}\n' : ''}'
              'Abonelik: ${_selectedSubscription!.packageName}'
              '${_notesController.text.isNotEmpty ? '\nNotlar: ${_notesController.text}' : ''}',
        );
      }
    } catch (e) {
      logger.err('Error adding appointment: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Randevu eklenirken bir hata oluştu. Lütfen tekrar deneyin.',
        );
      }
    } finally {
      stopLoading();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Create maps for dropdown options
    final Map<MeetingType, String> meetingTypeOptions = {
      for (var type in MeetingType.values) type: type.label
    };
    
    final Map<AppointmentType, String> appointmentTypeOptions = {
      for (var type in AppointmentType.values) type: type.lbl
    };
    
    final Map<AppointmentStatus, String> statusOptions = {
      for (var status in AppointmentStatus.values) status: status.label
    };

    return Stack(
      children: [
        AlertDialog(
          title: const Text('Yeni Randevu Ekle'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.userId == null) ...[
                DropdownButtonFormField<UserModel>(
                  value: _selectedUser,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı',
                    border: OutlineInputBorder(),
                  ),
                  items: _users.map((user) {
                    return DropdownMenuItem<UserModel>(
                      value: user,
                      child: Text(user.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedUser = value;
                      // When user changes, fetch their subscriptions
                      if (value != null) {
                        _fetchSubscriptions(value.userId);
                      } else {
                        _subscriptions = [];
                        _selectedSubscription = null;
                      }
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Lütfen bir kullanıcı seçin';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              
              // Subscription dropdown
              if (_isLoadingSubscriptions)
                const Center(child: CircularProgressIndicator())
              else
                DropdownButtonFormField<SubscriptionModel>(
                  value: _selectedSubscription,
                  decoration: const InputDecoration(
                    labelText: 'Abonelik *',
                    border: OutlineInputBorder(),
                    hintText: 'Abonelik seçin',
                  ),
                  items: _subscriptions.map((sub) {
                    return DropdownMenuItem<SubscriptionModel>(
                      value: sub,
                      child: Text(
                        '${sub.packageName} (Kalan: ${sub.totalMeetings - sub.meetingsCompleted - sub.meetingsBurned}/${sub.totalMeetings})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedSubscription = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Lütfen bir abonelik seçin';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 16),
              
              // Meeting type dropdown
              StatusDropdown<MeetingType>(
                selectedStatus: _selectedMeetingType,
                onStatusChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedMeetingType = value;
                      // For haftalik, duration depends on meeting type - always update
                      if (_selectedAppointmentType == AppointmentType.haftalik) {
                        _durationController.text = _selectedAppointmentType.getDurationForMeetingType(value).toString();
                      }
                    });
                  }
                },
                statusOptions: meetingTypeOptions,
                label: 'Görüşme Türü',
              ),
              const SizedBox(height: 16),
              
              // Appointment type dropdown
              StatusDropdown<AppointmentType>(
                selectedStatus: _selectedAppointmentType,
                onStatusChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedAppointmentType = value;
                      // Update duration if empty or if switching to/from haftalik
                      if (_durationController.text.isEmpty || value == AppointmentType.haftalik) {
                        _durationController.text = value.getDurationForMeetingType(_selectedMeetingType).toString();
                      }
                    });
                  }
                },
                statusOptions: appointmentTypeOptions,
                label: 'Randevu Türü',
              ),
              const SizedBox(height: 16),
              
              // Duration input
              Row(
                children: [
                  const Text('Görüşme Süresi: '),
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _durationController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('dk'),
                ],
              ),
              const SizedBox(height: 16),
              
              // Appointment status dropdown
              StatusDropdown<AppointmentStatus>(
                selectedStatus: _selectedStatus,
                onStatusChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedStatus = value;
                    });
                  }
                },
                statusOptions: statusOptions,
                label: 'Randevu Durumu',
              ),
              const SizedBox(height: 16),
              
              // Postponed date picker (shown only when status is Postponed)
              if (_selectedStatus == AppointmentStatus.postponed)
                ListTile(
                  title: const Text(
                    'Ertelenen Tarih',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: _postponedDate != null
                      ? Text(
                    DateFormat('d MMMM , HH:mm', 'tr_TR').format(_postponedDate!),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        )
                      : const Text('Tarih seçilmedi'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: _postponedDate ?? DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (pickedDate != null && mounted) {
                      final TimeOfDay? pickedTime = await showTimePicker(
                        context: context,
                        initialTime: _postponedDate != null
                            ? TimeOfDay.fromDateTime(_postponedDate!)
                            : const TimeOfDay(hour: 9, minute: 0),
                        builder: (context, child) {
                          return MediaQuery(
                            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          );
                        },
                      );
                      if (pickedTime != null && mounted) {
                        setState(() {
                          _postponedDate = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                        });
                      }
                    }
                  },
                ),
              if (_selectedStatus == AppointmentStatus.postponed)
                const SizedBox(height: 16),
              // Show date picker only if not hidden (e.g., when called from admin page with pre-selected date)
              if (!widget.hideDateSelection) ...[
                DatePickerFormField(
                  selectedDate: _selectedDate,
                  onDateSelected: _onDateSelected,
                  label: 'Tarih Seçin',
                  selectedLabel: 'Tarih',
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                ),
              ] else ...[
                // Show selected date as read-only when date is pre-selected
                ListTile(
                  title: const Text('Tarih'),
                  subtitle: Text(
                    DateFormat('d MMMM yyyy, EEEE', 'tr_TR').format(_selectedDate),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  leading: const Icon(Icons.calendar_today),
                ),
              ],
              ListTile(
                title: const Text('Saat'),
                subtitle: Text(
                  '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                trailing: const Icon(Icons.access_time),
                onTap: _selectTime,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notlar',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : _saveAppointment,
              child: const Text('Kaydet'),
            ),
          ],
        ),
        if (isLoading) const LoadingOverlay(message: 'Randevu kaydediliyor...'),
      ],
    );
  }
}
