// dialogs/add_appointment_dialog.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/appointment_model.dart';
import '../models/user_model.dart';
import '../models/logger.dart';
import '../models/subs_model.dart';
import '../providers/appointment_durations_provider.dart';
import '../providers/appointment_manager.dart';
import '../providers/sub_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/date_formatter.dart';
import '../utils/time_picker_utils.dart';
import '../dialogs/dialog_widgets.dart'; // Import dialog widgets
import '../dialogs/overlap_warning_dialog.dart';
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
  // Source of the postponement (user vs admin). Only user-originated
  // postponements consume the customer's postponement rights.
  PostponeSource _postponedBy = PostponeSource.user;
  List<UserModel> _users = [];

  // User search (admin scenario only)
  final TextEditingController _userSearchController = TextEditingController();
  List<UserModel> _filteredUsers = [];
  bool _showUserDropdown = false;
  String? _userFieldError;

  // Subscription related variables
  List<SubscriptionModel> _subscriptions = [];
  SubscriptionModel? _selectedSubscription;
  bool _isLoadingSubscriptions = false;
  
  // Notes controller
  final _notesController = TextEditingController();
  
  // Duration controller
  final _durationController = TextEditingController();
  // Whether the admin has manually edited the duration field. Once touched we
  // never overwrite it with a recomputed default.
  bool _durationTouched = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedDate != null) {
      _selectedDate = widget.selectedDate!;
    }
    
    // Initialize duration with selected appointment type's default (considering meeting type)
    _durationController.text = _selectedAppointmentType.getDurationForMeetingType(_selectedMeetingType).toString();
    // Ensure admin-configured default durations are loaded, then refresh the
    // pre-filled value (unless the admin already changed it). No-op after the
    // first call per session.
    _ensureDurationsLoaded();
    
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
    _userSearchController.dispose();
    super.dispose();
  }

  /// Loads the admin-configured default durations and, if the admin has not
  /// manually edited the field yet, refreshes the pre-filled value so it
  /// reflects the durations set in the Testing page.
  Future<void> _ensureDurationsLoaded() async {
    try {
      await Provider.of<AppointmentDurationsProvider>(context, listen: false)
          .fetchDurations();
    } catch (_) {
      // Failures fall back to built-in default durations; nothing to do.
      return;
    }
    if (!mounted || _durationTouched) return;
    setState(() {
      _durationController.text = _selectedAppointmentType
          .getDurationForMeetingType(_selectedMeetingType)
          .toString();
    });
  }

  /// Filters [_users] using the entered query (matches name, surname, full
  /// name, or email — same rules used in the admin payment dialog).
  void _filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _users;
      } else {
        final searchQuery = query.toLowerCase();
        _filteredUsers = _users.where((user) {
          final name = user.name.toLowerCase();
          final surname = user.surname.toLowerCase();
          final fullName = '$name $surname'.trim();
          final email = user.email.toLowerCase();
          return name.contains(searchQuery) ||
              surname.contains(searchQuery) ||
              fullName.contains(searchQuery) ||
              email.contains(searchQuery);
        }).toList();
      }
    });
  }

  void _onUserSelectedFromSearch(UserModel user) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedUser = user;
      _userSearchController.text = '${user.name} ${user.surname}'.trim();
      _showUserDropdown = false;
      _userFieldError = null;
    });
    _fetchSubscriptions(user.userId);
  }

  void _clearSelectedUser() {
    setState(() {
      _selectedUser = null;
      _userSearchController.clear();
      _filteredUsers = _users;
      _subscriptions = [];
      _selectedSubscription = null;
      _showUserDropdown = false;
    });
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

  /// Picks the default appointment type from the (selected) subscription:
  /// Aktif/Kilo Takip -> Kilo Takip, Aktif/Haftalık -> Haftalık Görüşme,
  /// no package -> Ön Görüşme (the only type allowed without a package).
  /// Also refreshes the duration to match. Call inside a setState block.
  void _applyAppointmentTypeForSubscription(SubscriptionModel? sub) {
    _selectedAppointmentType = switch (sub?.status) {
      SubActiveStatus.activeWeightTracking => AppointmentType.kgtakip,
      SubActiveStatus.activeWeekly => AppointmentType.haftalik,
      _ => AppointmentType.og,
    };
    _durationController.text = _selectedAppointmentType
        .getDurationForMeetingType(_selectedMeetingType)
        .toString();
  }

  Future<void> _fetchSubscriptions(String userId) async {
    setState(() {
      _isLoadingSubscriptions = true;
    });

    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final fetched = await subProvider.fetchSubscriptions(
        userId: userId,
        showAllSubscriptions: false,
      );
      // Only active packages (weekly / weight-tracking) can receive new
      // appointments; frozen or completed packages are excluded.
      final List<SubscriptionModel> activeSubscriptions =
          fetched.where((s) => s.status.isActive).toList();

      setState(() {
        _subscriptions = activeSubscriptions;
        _isLoadingSubscriptions = false;
        _selectedSubscription =
            _subscriptions.isNotEmpty ? _subscriptions.first : null;
        _applyAppointmentTypeForSubscription(_selectedSubscription);
      });
      
      // Warn (but still allow) when the user has no active package: only an
      // "Ön Görüşme" or "Program Başlangıcı" appointment may be added without
      // a package.
      if (activeSubscriptions.isEmpty || _selectedSubscription == null) {
        if (mounted) {
          await DialogUtils.openInfo(
            context,
            title: 'Uyarı',
            message:
                'Kullanıcının aktif paketi bulunmuyor. Bu yüzden sadece ÖN GÖRÜŞME veya PROGRAM BAŞLANGICI randevusu ekleyiniz, veya bir paket ekleyip sonrasında randevu ekleyiniz.',
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
          message: 'Paketler yüklenirken bir hata oluştu: $e',
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
        _filteredUsers = users;
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
    final TimeOfDay? picked = await TimePickerUtils.pickTime(
      context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _saveAppointment() async {
    if (!_formKey.currentState!.validate()) return;

    // Manual user validation (admin scenario only) — kept out of the Form
    // validator because the user picker is a TextField + custom result list
    // rather than a FormField, to avoid the input decoration relayout crashes
    // we hit when toggling readOnly / FormField rebuilds while focused.
    if (widget.userId == null && _selectedUser == null) {
      setState(() => _userFieldError = 'Lütfen bir kullanıcı seçin');
      return;
    }

    // A package is required unless this is an "Ön Görüşme" or "Program
    // Başlangıcı" appointment, which may be added without one (e.g. when the
    // user has no active package yet).
    if (_selectedSubscription == null &&
        !_selectedAppointmentType.allowedWithoutPackage) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message:
            'Paketsiz randevu yalnızca ÖN GÖRÜŞME veya PROGRAM BAŞLANGICI türünde eklenebilir. Lütfen bir paket seçin veya randevu türünü Ön Görüşme ya da Program Başlangıcı yapın.',
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

    // A user-originated postponement consumes a postponement right; admin-
    // originated ones do not. Warn the admin when a user-originated
    // postponement is recorded but the customer has no rights left.
    final bool isUserPostponement =
        _selectedStatus == AppointmentStatus.postponed &&
        _postponedBy == PostponeSource.user;
    if (isUserPostponement && _selectedSubscription != null) {
      if (!_selectedSubscription!.hasPostponementsLeft) {
        final proceedAnyway = await DialogUtils.openConfirm(
          context,
          title: 'Erteleme Hakkı Yok',
          message:
              'Danışanın erteleme hakkı bulunmamaktadır. Yine de bu randevuyu ertelemek istediğinize emin misiniz?',
          confirmText: 'Evet',
          cancelText: 'Hayır',
        );
        if (!proceedAnyway) return;
      }
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
              Text('Tarih: ${DateFormatter.formatNumericDate(_selectedDate)}'),
              Text('Saat: ${_selectedTime.format(context)}'),
              Text('Görüşme Tipi: ${_selectedMeetingType.label}'),
              Text('Randevu Türü: ${_selectedAppointmentType.lbl}'),
              Text('Görüşme Süresi: ${_durationController.text.isNotEmpty ? _durationController.text : _selectedAppointmentType.getDurationForMeetingType(_selectedMeetingType)} dk'),
              Text('Durum: ${_selectedStatus.label}'),
              if (_selectedStatus == AppointmentStatus.postponed && _postponedDate != null)
                Text(
                  'Ertelenen Tarih: ${DateFormatter.formatNumericDateTime(_postponedDate!)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (_selectedStatus == AppointmentStatus.postponed)
                Text('Erteleme Kaynağı: ${_postponedBy.label}'),
              Text('Paket: ${_selectedSubscription?.packageName ?? 'Paketsiz (Ön Görüşme)'}'),
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

    final appointmentManager =
        Provider.of<AppointmentManager>(context, listen: false);
    final durationMinutes = int.tryParse(_durationController.text) ??
        _selectedAppointmentType.getDurationForMeetingType(_selectedMeetingType);
    final newStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    // Non-blocking overlap warning: if this time clashes with existing
    // meeting(s), inform the admin and let them decide whether to proceed.
    final conflicts = await appointmentManager.findOverlappingAppointments(
      start: newStart,
      durationMinutes: durationMinutes,
    );
    if (conflicts.isNotEmpty) {
      if (!mounted) return;
      final proceed =
          await showOverlapWarningDialog(context, conflicts: conflicts);
      if (!proceed) return;
    }

    startLoading();

    try {
      final appointment = AppointmentModel(
        appointmentId: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: widget.userId ?? _selectedUser!.userId,
        subscriptionId: _selectedSubscription?.subscriptionId,
        appointmentDateTime: newStart,
        meetingType: _selectedMeetingType,
        appointmentType: _selectedAppointmentType,
        status: _selectedStatus,
        createDate: DateTime.now(),
        createUser: widget.userId != null ? 'user' : 'admin',
        notes: _notesController.text,
        postponedDate: _selectedStatus == AppointmentStatus.postponed ? _postponedDate : null,
        postponedBy: _selectedStatus == AppointmentStatus.postponed ? _postponedBy : null,
        durationMinutes: durationMinutes,
      );

        await appointmentManager.addAppointment(appointment);

        // Only user-originated postponements consume a postponement right. Use
        // an atomic increment so concurrent edits can't clobber the counter.
        if (isUserPostponement && _selectedSubscription != null) {
          try {
            final subProvider =
                Provider.of<SubProvider>(context, listen: false);
            await subProvider.updateSubscription(
              userId: appointment.userId,
              subscriptionId: _selectedSubscription!.subscriptionId,
              updateData: {
                'postponementsUsed': FieldValue.increment(1),
                'updateDate': Timestamp.fromDate(DateTime.now()),
                'updateUser': 'admin',
              },
            );
          } catch (e) {
            logger.err('Error updating postponement: {}', [e]);
          }
        }

        widget.onAppointmentAdded();

      if (mounted) {
        Navigator.of(context).pop();
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Randevu detayları:\n\n'
              'Kullanıcı: ${widget.userId != null ? _selectedUser!.name : _selectedUser!.name}\n'
              'Tarih: ${DateFormatter.formatNumericDate(_selectedDate)}\n'
              'Saat: ${_selectedTime.format(context)}\n'
              'Görüşme Tipi: ${_selectedMeetingType.label}\n'
              'Randevu Türü: ${_selectedAppointmentType.lbl}\n'
              'Görüşme Süresi: $durationMinutes dk\n'
              'Durum: ${_selectedStatus.label}\n'
              '${_selectedStatus == AppointmentStatus.postponed && _postponedDate != null ? 'Ertelenen Tarih: ${DateFormatter.formatNumericDateTime(_postponedDate!)}\n' : ''}'
              'Paket: ${_selectedSubscription?.packageName ?? 'Paketsiz (Ön Görüşme)'}'
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
              // AlertDialog computes the intrinsic width of its content; the
              // ListView.builder used in the user search dropdown can't be
              // intrinsically measured, so we pin a fixed width here so the
              // dialog never traverses into it for sizing.
              child: SizedBox(
                width: 450,
                child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.userId == null) ...[
                TextField(
                  controller: _userSearchController,
                  decoration: InputDecoration(
                    labelText: 'Kullanıcı',
                    hintText: 'Kullanıcı ara...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person_search),
                    suffixIcon: _selectedUser != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _clearSelectedUser,
                          )
                        : null,
                    errorText: _userFieldError,
                  ),
                  onTap: () => setState(() => _showUserDropdown = true),
                  onChanged: (value) {
                    if (_selectedUser != null) {
                      setState(() => _selectedUser = null);
                    }
                    _filterUsers(value);
                    setState(() {
                      _showUserDropdown = true;
                      _userFieldError = null;
                    });
                  },
                ),
                if (_showUserDropdown && _selectedUser == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _filteredUsers.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Kullanıcı bulunamadı'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _filteredUsers.length,
                              itemBuilder: (context, index) {
                                final user = _filteredUsers[index];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    child: Text(user.name.isNotEmpty
                                        ? user.name[0].toUpperCase()
                                        : '?'),
                                  ),
                                  title: Text(
                                      '${user.name} ${user.surname}'.trim()),
                                  subtitle: Text(user.email,
                                      style: const TextStyle(fontSize: 12)),
                                  onTap: () => _onUserSelectedFromSearch(user),
                                );
                              },
                            ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              
              // Subscription dropdown
              if (_isLoadingSubscriptions)
                const Center(child: CircularProgressIndicator())
              else
                DropdownButtonFormField<SubscriptionModel>(
                  value: _selectedSubscription,
                  decoration: InputDecoration(
                    labelText: 'Paket',
                    border: const OutlineInputBorder(),
                    hintText: 'Paket seçin',
                    helperText: _subscriptions.isEmpty
                        ? 'Aktif paket yok — sadece Ön Görüşme veya Program Başlangıcı eklenebilir'
                        : null,
                  ),
                  items: _subscriptions.map((sub) {
                    return DropdownMenuItem<SubscriptionModel>(
                      value: sub,
                      child: Text(
                        '${sub.packageName} (Kalan: ${sub.remainingMeetings}/${sub.totalMeetings})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedSubscription = value;
                      // Keep the appointment type in sync with the chosen package.
                      _applyAppointmentTypeForSubscription(value);
                    });
                  },
                  validator: (value) {
                    if (value == null &&
                        !_selectedAppointmentType.allowedWithoutPackage) {
                      return 'Lütfen bir paket seçin veya türü Ön Görüşme ya da Program Başlangıcı yapın';
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
                      onChanged: (_) => _durationTouched = true,
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
              
              // Postponement source (shown only when status is Postponed).
              // Only user-originated postponements consume the customer's rights.
              if (_selectedStatus == AppointmentStatus.postponed) ...[
                StatusDropdown<PostponeSource>(
                  selectedStatus: _postponedBy,
                  onStatusChanged: (value) {
                    if (value != null) {
                      setState(() => _postponedBy = value);
                    }
                  },
                  statusOptions: {
                    for (final source in PostponeSource.values)
                      source: source.label
                  },
                  label: 'Erteleme Kaynağı',
                ),
                const SizedBox(height: 16),
              ],

              // Postponed date picker (shown only when status is Postponed)
              if (_selectedStatus == AppointmentStatus.postponed)
                ListTile(
                  title: const Text(
                    'Ertelenen Tarih',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: _postponedDate != null
                      ? Text(
                    DateFormatter.formatNumericDateTime(_postponedDate!),
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
                      // Postponed date may also be in the past (no future-only limit).
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (pickedDate != null && mounted) {
                      final TimeOfDay? pickedTime = await TimePickerUtils.pickTime(
                        context,
                        initialTime: _postponedDate != null
                            ? TimeOfDay.fromDateTime(_postponedDate!)
                            : const TimeOfDay(hour: 9, minute: 0),
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
                  // Allow selecting past dates (e.g. logging a missed/late
                  // appointment). Lower bound kept wide; default selected date
                  // is today, which stays within [firstDate, lastDate].
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                ),
              ] else ...[
                // Show selected date as read-only when date is pre-selected
                ListTile(
                  title: const Text('Tarih'),
                  subtitle: Text(
                    DateFormatter.formatNumericDate(_selectedDate),
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
