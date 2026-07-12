import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/appointment_model.dart';
import '../models/subs_model.dart';
import '../providers/appointment_durations_provider.dart';
import '../providers/appointment_manager.dart';
import '../providers/sub_provider.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/date_formatter.dart';
import '../widgets/loading_overlay.dart';

class EditAppointmentDialog extends StatefulWidget {
  final AppointmentModel appointment;
  final Function onAppointmentUpdated;

  const EditAppointmentDialog({
    super.key,
    required this.appointment,
    required this.onAppointmentUpdated,
  });

  @override
  State<EditAppointmentDialog> createState() => _EditAppointmentDialogState();
}

class _EditAppointmentDialogState extends State<EditAppointmentDialog> 
    with LoadingStateMixin {
  late MeetingType _meetingType;
  late AppointmentType _appointmentType;
  late AppointmentStatus _appointmentStatus;
  late DateTime _appointmentDateTime;
  DateTime? _postponedDate;
  final _notesController = TextEditingController();
  final _durationController = TextEditingController();
  // For subscription selection
  String? _selectedSubscriptionId;
  List<SubscriptionModel> _availableSubscriptions = [];
  bool _isLoadingSubscriptions = true; // Start as true to prevent dropdown render before data loads

  /// Active packages plus the currently-linked one (even if passive) so the
  /// dropdown value stays valid. Passive packages cannot be newly assigned.
  List<SubscriptionModel> get _selectableSubscriptions =>
      _availableSubscriptions
          .where((s) =>
              s.status.isActive || s.subscriptionId == _selectedSubscriptionId)
          .toList();
  
  // Track original status and postponement deduction decision
  late AppointmentStatus _originalStatus;
  bool _shouldDeductPostponement = false;
  
  // User name display
  String? _userName;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _meetingType = widget.appointment.meetingType;
    _appointmentType = widget.appointment.appointmentType;
    _appointmentStatus = widget.appointment.status;
    _originalStatus = widget.appointment.status;
    _appointmentDateTime = widget.appointment.appointmentDateTime;
    _postponedDate = widget.appointment.postponedDate;
    _notesController.text = widget.appointment.notes ?? '';
    _durationController.text = widget.appointment.durationMinutes.toString();
    _selectedSubscriptionId = widget.appointment.subscriptionId;

    // Preload admin-configured default durations so that changing the
    // appointment/meeting type re-derives the duration from the admin values.
    // The stored duration above is left untouched.
    _preloadDurations();
    
    // Fetch all subscriptions for the user
    _fetchAvailableSubscriptions();
    
    // Fetch user details for display
    _fetchUserDetails();
  }
  
  @override
  void dispose() {
    _notesController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  /// Loads the admin-configured default durations into the registry so a later
  /// appointment/meeting-type change re-derives the duration from the admin
  /// values. Fire-and-forget; failures fall back to the built-in defaults.
  Future<void> _preloadDurations() async {
    try {
      await Provider.of<AppointmentDurationsProvider>(context, listen: false)
          .fetchDurations();
    } catch (_) {
      // Falls back to built-in defaults when the load fails.
    }
  }

  Future<void> _fetchUserDetails() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = await userProvider.fetchUserDetails(userId: widget.appointment.userId);
      
      if (mounted && user != null) {
        setState(() {
          _userName = '${user.name} ${user.surname}'.trim();
          _isLoadingUser = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching user details: $e');
      if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
    }
  }
  
  Future<void> _fetchAvailableSubscriptions() async {
    setState(() {
      _isLoadingSubscriptions = true;
    });
    
    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final subscriptions = await subProvider.fetchSubscriptions(
        userId: widget.appointment.userId,
        showAllSubscriptions: true,
      );
      
      if (mounted) {
        setState(() {
          _availableSubscriptions = subscriptions;
          _isLoadingSubscriptions = false;
          
          // Validate that selected subscription exists in the list
          // If not, reset to null to avoid dropdown error
          if (_selectedSubscriptionId != null) {
            final exists = subscriptions.any((s) => s.subscriptionId == _selectedSubscriptionId);
            if (!exists) {
              _selectedSubscriptionId = null;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching subscriptions: $e');
      if (mounted) {
        setState(() {
          _isLoadingSubscriptions = false;
        });
      }
    }
  }
  
  Future<void> _handleStatusChange(AppointmentStatus newStatus) async {
    // Reset postponement deduction flag
    _shouldDeductPostponement = false;
    
    // If status changed to "Ertelendi" and it wasn't already "Ertelendi"
    if (newStatus == AppointmentStatus.postponed && 
        _originalStatus != AppointmentStatus.postponed) {
      // Ask user if postponement should be deducted
      final shouldDeduct = await DialogUtils.openConfirm(
        context,
        title: 'Erteleme Hakkı',
        message: 'Danışanın erteleme hakkından düşülsün mü?',
        confirmText: 'Evet',
        cancelText: 'Hayır',
      );
      
      if (shouldDeduct) {
        _shouldDeductPostponement = true;
      }
    }
    
    setState(() {
      _appointmentStatus = newStatus;
    });
  }

  Future<void> _updateAppointment() async {
    // Validate postponed date if status is "Ertelendi"
    if (_appointmentStatus == AppointmentStatus.postponed && _postponedDate == null) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Lütfen ertelenen tarih için bir tarih seçiniz.',
      );
      return;
    }
    
    // Check if status is being changed to "Ertelendi" and subscription has no remaining rights
    if (_appointmentStatus == AppointmentStatus.postponed && 
        _originalStatus != AppointmentStatus.postponed &&
        _selectedSubscriptionId != null) {
      // Find the selected subscription
      final selectedSubscription = _availableSubscriptions.firstWhere(
        (s) => s.subscriptionId == _selectedSubscriptionId,
        orElse: () => SubscriptionModel(
          subscriptionId: '',
          userId: '',
          packageName: 'Tanımsız',
          startDate: DateTime.now(),
          totalMeetings: 0,
          allowedPostponements: 0,
          totalAmount: 0,
          meetingType: SubsMeetingType.faceToFace,
        ),
      );
      
      // Check if no postponement rights remain
      final remainingPostponements = selectedSubscription.allowedPostponements - 
                                     selectedSubscription.postponementsUsed;
      
      if (remainingPostponements <= 0) {
        // Show warning dialog
        final proceedAnyway = await DialogUtils.openConfirm(
          context,
          title: 'Erteleme Hakkı Yok',
          message: 'Danışanın erteleme hakkı bulunmamaktadır. Yine de bu randevuyu ertelemek istediğinize emin misiniz?',
          confirmText: 'Evet',
          cancelText: 'Hayır',
        );
        
        if (!proceedAnyway) return;
      }
    }
    
    // Get the selected subscription name for display ("Paketsiz" when none).
    final selectedSubName = _selectedSubscriptionId == null
        ? 'Paketsiz'
        : _availableSubscriptions
            .firstWhere(
              (s) => s.subscriptionId == _selectedSubscriptionId,
              orElse: () => SubscriptionModel(
                subscriptionId: '',
                userId: '',
                packageName: 'Silinmiş Paket',
                startDate: DateTime.now(),
                totalMeetings: 0,
                allowedPostponements: 0,
                totalAmount: 0,
                meetingType: SubsMeetingType.faceToFace,
              ),
            )
            .packageName;
    
    // Show confirmation dialog
    final shouldUpdate = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Randevu Güncelle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Aşağıdaki değişiklikleri yapmak istediğinizden emin misiniz?'),
              const SizedBox(height: 16),
              Text('Görüşme Tipi: ${_meetingType.label}'),
              Text('Randevu Türü: ${_appointmentType.lbl}'),
              Text('Görüşme Süresi: ${_durationController.text.isNotEmpty ? _durationController.text : _appointmentType.getDurationForMeetingType(_meetingType)} dk'),
              Text('Durum: ${_appointmentStatus.label}'),
              if (_appointmentStatus == AppointmentStatus.postponed && _postponedDate != null)
                Text(
                  'Ertelenen Tarih: ${DateFormatter.formatNumericDateTime(_postponedDate!)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Paket: '),
                  Expanded(
                    child: Text(
                      selectedSubName,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                ],
              ),
              Text(
                  'Tarih: ${DateFormatter.formatNumericDateTime(_appointmentDateTime)}'),
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

    if (shouldUpdate != true) return;

    startLoading();

    try {
      final appointmentManager =
          Provider.of<AppointmentManager>(context, listen: false);

      // Build the updated appointment object
      final durationMinutes = int.tryParse(_durationController.text) ?? _appointmentType.getDurationForMeetingType(_meetingType);
      AppointmentModel updatedAppointment = AppointmentModel(
        appointmentId: widget.appointment.appointmentId,
        userId: widget.appointment.userId,
        subscriptionId: _selectedSubscriptionId,
        meetingType: _meetingType,
        appointmentType: _appointmentType,
        appointmentDateTime: _appointmentDateTime,
        status: _appointmentStatus,
        notes: _notesController.text,
        createDate: widget.appointment.createDate,
        updateDate: DateTime.now(),
        createUser: widget.appointment.createUser,
        updateUser: 'admin', // Assuming admin is updating
        canceledBy: widget.appointment.canceledBy,
        canceledAt: widget.appointment.canceledAt,
        postponedDate: _appointmentStatus == AppointmentStatus.postponed ? _postponedDate : null,
        durationMinutes: durationMinutes,
      );

      // Send update to Firestore
      await appointmentManager.updateAppointment(updatedAppointment);
      
      // If user agreed to deduct postponement, update the subscription
      if (_shouldDeductPostponement && _selectedSubscriptionId != null) {
        try {
          final subProvider = Provider.of<SubProvider>(context, listen: false);
          
          // Get the current subscription to check its current values
          final subscriptions = await subProvider.fetchSubscriptions(
            userId: widget.appointment.userId,
            showAllSubscriptions: true,
          );
          
          final subscription = subscriptions.firstWhere(
            (s) => s.subscriptionId == _selectedSubscriptionId,
            orElse: () => throw Exception('Paket bulunamadı'),
          );
          
          // Increment postponementsUsed by 1
          final newPostponementsUsed = subscription.postponementsUsed + 1;
          
          await subProvider.updateSubscription(
            userId: widget.appointment.userId,
            subscriptionId: _selectedSubscriptionId!,
            updateData: {
              'postponementsUsed': newPostponementsUsed,
              'updateDate': Timestamp.fromDate(DateTime.now()),
              'updateUser': 'admin',
            },
          );
        } catch (e) {
          debugPrint('Error updating postponement: $e');
          // Continue even if postponement update fails
        }
      }

      // Notify parent & close
      widget.onAppointmentUpdated();
      if (!mounted) return;
      Navigator.of(context).pop();
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Randevu başarıyla güncellendi.',
      );
    } catch (e) {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Randevu güncellenirken bir hata oluştu: $e',
        );
      }
    } finally {
      stopLoading();
    }
  }

  Future<void> _cancelAppointment() async {
    // Ask the user to confirm cancellation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('İptal Onayı'),
          content: const Text(
              'Bu randevuyu iptal etmek istediğinizden emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hayır'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Evet, İptal Et'),
            ),
          ],
        );
      },
    );

    // If user confirmed, proceed
    if (confirm == true) {
      startLoading();
      
      try {
        final appointmentManager =
            Provider.of<AppointmentManager>(context, listen: false);

        // Indicate who canceled it. Adjust as needed ("user", "admin", etc.).
        final success = await appointmentManager.cancelAppointment(
          widget.appointment.appointmentId,
          widget.appointment.userId,
          canceledBy: 'User',
        );

        if (!mounted) return;
        if (success) {
          await DialogUtils.openInfo(
            context,
            title: 'Başarılı',
            message: 'Randevu başarıyla iptal edildi.',
          );
          widget.onAppointmentUpdated();
          Navigator.of(context).pop();
        } else {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Randevu iptal edilemedi.',
          );
        }
      } catch (e) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Randevu iptal edilirken bir hata oluştu: $e',
        );
      } finally {
        stopLoading();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AlertDialog(
          title: const Text('Randevu Düzenle'),
          content: SingleChildScrollView(
        child: Column(
          children: [
            // 0) User Name (read-only)
            ListTile(
              title: const Text('Kullanıcı'),
              trailing: _isLoadingUser
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _userName ?? 'Bilinmiyor',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
            ),
            // 1) Meeting Type
            ListTile(
              title: const Text('Görüşme Türü'),
              trailing: DropdownButton<MeetingType>(
                value: _meetingType,
                onChanged: (MeetingType? newValue) {
                  setState(() {
                    _meetingType = newValue!;
                    // For haftalik, duration depends on meeting type - always update
                    if (_appointmentType == AppointmentType.haftalik) {
                      _durationController.text = _appointmentType.getDurationForMeetingType(newValue).toString();
                    }
                  });
                },
                items: MeetingType.values.map<DropdownMenuItem<MeetingType>>(
                  (MeetingType type) {
                    return DropdownMenuItem<MeetingType>(
                      value: type,
                      child: Text(type.label),
                    );
                  },
                ).toList(),
              ),
            ),
            // Appointment Type
            ListTile(
              title: const Text('Randevu Türü'),
              trailing: DropdownButton<AppointmentType>(
                value: _appointmentType,
                onChanged: (AppointmentType? newValue) {
                  setState(() {
                    _appointmentType = newValue!;
                    // Update duration if empty or if switching to/from haftalik
                    if (_durationController.text.isEmpty || newValue == AppointmentType.haftalik) {
                      _durationController.text = newValue.getDurationForMeetingType(_meetingType).toString();
                    }
                  });
                },
                items: AppointmentType.values.map<DropdownMenuItem<AppointmentType>>(
                  (AppointmentType type) {
                    return DropdownMenuItem<AppointmentType>(
                      value: type,
                      child: Text(type.lbl),
                    );
                  },
                ).toList(),
              ),
            ),
            // Duration input
            ListTile(
              title: Row(
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
            ),
            // 2) Appointment Status
            ListTile(
              title: const Text('Randevu Durumu'),
              trailing: DropdownButton<AppointmentStatus>(
                value: _appointmentStatus,
                onChanged: (AppointmentStatus? newValue) {
                  if (newValue != null) {
                    _handleStatusChange(newValue);
                  }
                },
                items: AppointmentStatus.values
                    .map<DropdownMenuItem<AppointmentStatus>>(
                        (AppointmentStatus status) {
                  return DropdownMenuItem<AppointmentStatus>(
                    value: status,
                    child: Text(status.label),
                  );
                }).toList(),
              ),
            ),
            
            // 2.5) Postponed Date Picker (shown only when status is Postponed)
            if (_appointmentStatus == AppointmentStatus.postponed)
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
            
            // 3) Subscription Dropdown
            ListTile(
              title: const Text('Paket'),
              subtitle: _isLoadingSubscriptions
                  ? const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Yükleniyor...'),
                      ],
                    )
                  : null,
              trailing: _isLoadingSubscriptions
                  ? null
                  : DropdownButton<String?>(
                      value: _selectedSubscriptionId,
                      hint: const Text('Seçiniz'),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedSubscriptionId = newValue;
                        });
                      },
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Paketsiz'),
                        ),
                        ..._selectableSubscriptions.map<DropdownMenuItem<String?>>(
                          (SubscriptionModel sub) {
                            return DropdownMenuItem<String?>(
                              value: sub.subscriptionId,
                              child: Text(
                                sub.packageName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
            ),
            // 4) Date & Time
            ListTile(
              title: Text(
                'Tarih: ${DateFormatter.formatNumericDateTime(_appointmentDateTime)}',
                style: const TextStyle(fontSize: 18,fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: _appointmentDateTime,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (pickedDate != null) {
                  if (!context.mounted) return;
                  final TimeOfDay? pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_appointmentDateTime),
                  );
                  if (pickedTime != null) {
                    setState(() {
                      _appointmentDateTime = DateTime(
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
            // 5) Cancel Button
            ElevatedButton(
              onPressed: _cancelAppointment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Randevuyu İptal Et'),
            ),
            // 6) Notes
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notlar'),
              maxLines: 3,
            ),
          ],
        ),
      ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : _updateAppointment,
              child: const Text('Kaydet'),
            ),
          ],
        ),
        if (isLoading) const LoadingOverlay(message: 'İşlem yapılıyor...'),
      ],
    );
  }
}
