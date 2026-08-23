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
import '../utils/postponement_notices.dart';
import '../utils/time_picker_utils.dart';
import '../widgets/loading_overlay.dart';
import 'dialog_widgets.dart';

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
  // Time is entered via two inline boxes (SS:DD), not a dial picker.
  final _hourController = TextEditingController();
  final _minuteController = TextEditingController();
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
  
  // Track original status and who initiated the postponement.
  late AppointmentStatus _originalStatus;
  // Source of the postponement (user vs admin). Only user-originated
  // postponements consume the customer's postponement rights. Defaults to
  // "user" since that is the common case (the client requests a new date).
  PostponeSource _postponedBy = PostponeSource.user;
  
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
    _hourController.text =
        _appointmentDateTime.hour.toString().padLeft(2, '0');
    _minuteController.text =
        _appointmentDateTime.minute.toString().padLeft(2, '0');
    _postponedDate = widget.appointment.postponedDate;
    _postponedBy = widget.appointment.postponedBy ?? PostponeSource.user;
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
    _hourController.dispose();
    _minuteController.dispose();
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
  
  void _handleStatusChange(AppointmentStatus newStatus) {
    // The postponement source (user vs admin) is chosen inline via the
    // "Erteleme Kaynağı" selector shown while the status is "Ertelendi".
    setState(() {
      _appointmentStatus = newStatus;
    });
  }

  /// Whether the *stored* appointment is cancelled. Editing is restricted in
  /// that case: it may only stay cancelled, go back to "Planlandı", or be
  /// turned into a postponement.
  bool get _isCanceled => _originalStatus == AppointmentStatus.canceled;

  /// Whether the cancellation of the *stored* appointment spent one of the
  /// customer's postponement rights.
  bool get _canceledWithDeduction =>
      _isCanceled && widget.appointment.postponementDeducted == true;

  /// Statuses the admin may pick in this dialog.
  ///
  /// - A cancelled appointment may stay cancelled, go back to "Planlandı"
  ///   (which returns the right the cancellation spent), or become "Ertelendi"
  ///   with a new date (the already-spent right is not charged again).
  ///   "Yapıldı" / "Yakıldı" stay out: a cancelled visit did not happen.
  /// - "İptal Edildi" is never picked here: cancelling goes through the
  ///   "Randevuyu İptal Et" button so the erteleme-hakkı question is asked and
  ///   the cancellation is recorded on the appointment.
  List<AppointmentStatus> get _selectableStatuses {
    if (_isCanceled) {
      return const [
        AppointmentStatus.canceled,
        AppointmentStatus.scheduled,
        AppointmentStatus.postponed,
      ];
    }
    return AppointmentStatus.values
        .where((s) => s != AppointmentStatus.canceled)
        .toList();
  }

  /// Remaining postponement rights for the currently selected subscription,
  /// or null when no (valid) subscription is selected. Only user-originated
  /// postponements count against the right (admin's never do), via
  /// SubscriptionModel.remainingPostponements.
  int? get _remainingPostponements {
    if (_selectedSubscriptionId == null) return null;
    final matches = _availableSubscriptions
        .where((s) => s.subscriptionId == _selectedSubscriptionId);
    if (matches.isEmpty) return null;
    return matches.first.remainingPostponements;
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

    // Read the inline time boxes (SS:DD) and apply them to the appointment date.
    final TimeOfDay? enteredTime =
        parseHourMinute(_hourController, _minuteController);
    if (enteredTime == null) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Geçerli bir saat giriniz (SS:DD).',
      );
      return;
    }
    _appointmentDateTime = DateTime(
      _appointmentDateTime.year,
      _appointmentDateTime.month,
      _appointmentDateTime.day,
      enteredTime.hour,
      enteredTime.minute,
    );

    // A user-originated postponement that is newly applied (the appointment was
    // not already postponed). Only these consume the customer's postponement
    // rights; admin-originated postponements never do.
    // A cancelled appointment that already paid a right does not pay again when
    // it becomes a postponement: the same right simply changes owner.
    final bool rightAlreadySpent = _canceledWithDeduction;
    final bool isNewUserPostponement =
        _appointmentStatus == AppointmentStatus.postponed &&
        _originalStatus != AppointmentStatus.postponed &&
        _postponedBy == PostponeSource.user &&
        !rightAlreadySpent;

    // The mirror case: a user-originated postponement is taken back and the
    // appointment returns to "Planlandı", so the right it paid for is given
    // back. Both the source and the package are read from the *stored*
    // appointment, since that is where the right was taken from — the admin may
    // have changed either field in this very edit.
    final String? originalSubscriptionId = widget.appointment.subscriptionId;
    // A stored postponement carries a spent right either because the customer
    // asked for it, or because it inherited the flag from a cancellation that
    // was charged; both are returned when the appointment goes back to
    // "Planlandı".
    final bool storedPostponementSpentRight =
        widget.appointment.postponedBy == PostponeSource.user ||
        widget.appointment.postponementDeducted == true;
    final bool isPostponementReverted =
        _originalStatus == AppointmentStatus.postponed &&
        storedPostponementSpentRight &&
        _appointmentStatus == AppointmentStatus.scheduled &&
        (originalSubscriptionId?.isNotEmpty ?? false);

    // The same case for a cancellation: the appointment was cancelled with
    // "evet, düşülsün" and is now put back to "Planlandı", so the right that
    // cancellation spent is returned exactly like a taken-back postponement.
    final bool isCancellationReverted =
        _originalStatus == AppointmentStatus.canceled &&
        widget.appointment.postponementDeducted == true &&
        _appointmentStatus == AppointmentStatus.scheduled &&
        (originalSubscriptionId?.isNotEmpty ?? false);

    // Leaving "İptal Edildi" clears the cancellation record. The deduction flag
    // survives exactly one route: straight to "Ertelendi", where the right
    // stays spent and is from now on carried by the postponement.
    final bool leavingCanceled = _originalStatus == AppointmentStatus.canceled &&
        _appointmentStatus != AppointmentStatus.canceled;
    final bool carriesDeductionToPostponement = rightAlreadySpent &&
        _appointmentStatus == AppointmentStatus.postponed;

    // Warn the admin when a user-originated postponement is applied but the
    // customer has no postponement rights left.
    if (isNewUserPostponement && _selectedSubscriptionId != null) {
      final remaining = _remainingPostponements ?? 0;
      if (remaining <= 0) {
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
        canceledBy: leavingCanceled ? null : widget.appointment.canceledBy,
        canceledAt: leavingCanceled ? null : widget.appointment.canceledAt,
        // Carried over: toMap() writes every field, so dropping this here would
        // silently clear the record of a deducted postponement right. It is
        // cleared on purpose only when the appointment stops being cancelled.
        postponementDeducted: carriesDeductionToPostponement
            ? true
            : (leavingCanceled ? null : widget.appointment.postponementDeducted),
        postponedDate: _appointmentStatus == AppointmentStatus.postponed ? _postponedDate : null,
        postponedBy: _appointmentStatus == AppointmentStatus.postponed ? _postponedBy : null,
        durationMinutes: durationMinutes,
      );

      // Send update to Firestore
      await appointmentManager.updateAppointment(updatedAppointment);
      
      // Only user-originated postponements consume a postponement right, and
      // taking one back returns it. Both directions go through the same atomic
      // adjustment, which also keeps the counter at or above zero.
      if (!mounted) return;
      final subProvider = Provider.of<SubProvider>(context, listen: false);

      if (isNewUserPostponement && _selectedSubscriptionId != null) {
        await subProvider.adjustPostponementsUsed(
          userId: widget.appointment.userId,
          subscriptionId: _selectedSubscriptionId!,
          delta: 1,
        );
      }

      if (isPostponementReverted || isCancellationReverted) {
        await subProvider.adjustPostponementsUsed(
          userId: widget.appointment.userId,
          subscriptionId: originalSubscriptionId!,
          delta: -1,
        );
        if (!mounted) return;
        await PostponementNotices.informRightReturned(context);
        if (!mounted) return;
      }

      // Notify parent & close
      widget.onAppointmentUpdated();
      if (!mounted) return;
      Navigator.of(context).pop();
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'İşlem Başarılı.',
      );

      // Told last, so it is the message the admin leaves the dialog with.
      if (carriesDeductionToPostponement && mounted) {
        await PostponementNotices.informDeductionNotRepeated(context);
      }
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

  /// Cancels the appointment: the record stays as "İptal Edildi".
  ///
  /// The admin is asked whether the cancellation should spend one of the
  /// customer's postponement rights; the answer is stored on the appointment so
  /// a later delete can say what happened to that right.
  Future<void> _cancelAppointment() async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'İptal Onayı',
      message: 'Bu randevuyu iptal etmek istediğinizden emin misiniz?',
      confirmText: 'Evet, İptal Et',
      cancelText: 'Hayır',
    );
    if (!confirmed || !mounted) return;

    // null => the admin backed out at this second step; nothing is cancelled.
    final deduct = await PostponementNotices.askDeductOnCancel(
      context,
      remainingRights: _remainingPostponements,
    );
    if (deduct == null || !mounted) return;

    startLoading();
    try {
      final appointmentManager =
          Provider.of<AppointmentManager>(context, listen: false);

      final success = await appointmentManager.cancelAppointment(
        widget.appointment.appointmentId,
        widget.appointment.userId,
        canceledBy: 'admin',
        deductPostponement: deduct,
      );

      if (!mounted) return;
      if (!success) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Randevu iptal edilemedi.',
        );
        return;
      }

      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: deduct
            ? 'Randevu iptal edildi ve danışanın erteleme hakkından bir adet '
                'düşüldü.'
            : 'Randevu iptal edildi. Erteleme hakkından düşülmedi.',
      );
      if (!mounted) return;
      // A postponement right the *appointment* had already spent is not given
      // back by cancelling either.
      await PostponementNotices.warnRightKept(context, widget.appointment);
      if (!mounted) return;

      widget.onAppointmentUpdated();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu iptal edilirken bir hata oluştu: $e',
      );
    } finally {
      if (mounted) stopLoading();
    }
  }

  /// Deletes the appointment for good, after an explicit confirmation.
  ///
  /// AppointmentManager gives the package's meeting back in the same batch when
  /// the deleted appointment had consumed one (see deleteAppointment).
  Future<void> _deleteAppointment() async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Randevu Silme',
      message:
          '${DateFormatter.formatNumericDateTime(widget.appointment.appointmentDateTime)} '
          'tarihli randevuyu silmek istediğinizden emin misiniz?',
      confirmText: 'Evet, Sil',
      cancelText: 'İptal',
    );
    if (!confirmed || !mounted) return;

    startLoading();
    try {
      final appointmentManager =
          Provider.of<AppointmentManager>(context, listen: false);
      final deleted = await appointmentManager.deleteAppointment(
        widget.appointment.appointmentId,
        widget.appointment.userId,
        deletedBy: 'admin',
      );

      if (!mounted) return;
      if (!deleted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Randevu bulunamadı, silinemedi.',
        );
        return;
      }

      widget.onAppointmentUpdated();
      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Randevu silindi.',
      );
      if (!mounted) return;
      // Deleting does not give a spent postponement right back either.
      await PostponementNotices.warnRightKept(context, widget.appointment);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Randevu silinirken bir hata oluştu: $e',
      );
    } finally {
      if (mounted) stopLoading();
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
                    // Update duration if empty, or when switching to a type with
                    // a fixed default (haftalik depends on meeting type; Tartım
                    // is always its short 5 min default).
                    if (_durationController.text.isEmpty ||
                        newValue == AppointmentType.haftalik ||
                        newValue == AppointmentType.tartim) {
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
                items: _selectableStatuses
                    .map<DropdownMenuItem<AppointmentStatus>>(
                        (AppointmentStatus status) {
                  return DropdownMenuItem<AppointmentStatus>(
                    value: status,
                    child: Text(status.label),
                  );
                }).toList(),
              ),
              subtitle: _isCanceled
                  ? const Text(
                      'İptal edilmiş randevu yalnızca "Planlandı" veya '
                      '"Ertelendi" durumuna alınabilir. "Planlandı" seçilirse '
                      'iptalde düşülen erteleme hakkı iade edilir; '
                      '"Ertelendi" seçilirse hak tekrar düşülmez.',
                      style: TextStyle(fontSize: 12),
                    )
                  : null,
            ),
            
            // 2.4) Postponement source (shown only when status is Postponed).
            // Only user-originated postponements consume the customer's rights.
            if (_appointmentStatus == AppointmentStatus.postponed)
              ListTile(
                title: const Text('Erteleme Kaynağı'),
                subtitle: Text(
                  _postponedBy == PostponeSource.user
                      ? 'Kullanıcının erteleme hakkından düşülür'
                          '${_remainingPostponements != null ? ' • Kalan hak: $_remainingPostponements' : ''}'
                      : 'Erteleme hakkından düşülmez',
                ),
                trailing: DropdownButton<PostponeSource>(
                  value: _postponedBy,
                  onChanged: (PostponeSource? newValue) {
                    if (newValue != null) {
                      setState(() => _postponedBy = newValue);
                    }
                  },
                  items: PostponeSource.values
                      .map<DropdownMenuItem<PostponeSource>>(
                        (PostponeSource source) =>
                            DropdownMenuItem<PostponeSource>(
                          value: source,
                          child: Text(source.label),
                        ),
                      )
                      .toList(),
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
                    // Postponed date may also be in the past (no future-only limit).
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
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
            
            // 3) Subscription Dropdown. The dropdown sits *under* the label
            // rather than in `trailing`: a long package name claimed the whole
            // row width there, leaving the "Paket" label a few pixels and
            // wrapping it one letter per line on phones.
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
                  : DropdownButton<String?>(
                      value: _selectedSubscriptionId,
                      hint: const Text('Seçiniz'),
                      // Fills the row and ellipsizes long names instead of
                      // stretching the dropdown to fit them.
                      isExpanded: true,
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
            // 4) Date & Time — date via widget, time via two inline boxes,
            // stacked below the date. No past/future restriction.
            DatePickerFormField(
              selectedDate: _appointmentDateTime,
              onDateSelected: (picked) {
                setState(() {
                  _appointmentDateTime = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    _appointmentDateTime.hour,
                    _appointmentDateTime.minute,
                  );
                });
              },
              label: 'Tarih Seçin',
              selectedLabel: 'Tarih',
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            ),
            const SizedBox(height: 8),
            HourMinuteField(
              hourController: _hourController,
              minuteController: _minuteController,
            ),
            // 5) Cancel / delete. Cancelling keeps the record ("İptal Edildi"),
            // deleting removes it for good; both give the package's meeting back
            // when the appointment had consumed one.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!_isCanceled)
                  ElevatedButton(
                    onPressed: isLoading ? null : _cancelAppointment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Randevuyu İptal Et'),
                  ),
                OutlinedButton.icon(
                  onPressed: isLoading ? null : _deleteAppointment,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Randevuyu Sil'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ],
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
