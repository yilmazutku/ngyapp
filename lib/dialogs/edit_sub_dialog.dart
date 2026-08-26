import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/amount_input_utils.dart';
import '../utils/dialog_utils.dart';
import '../utils/date_formatter.dart';
import '../utils/date_input_utils.dart';

class EditSubscriptionDialog extends StatefulWidget {
  final SubscriptionModel subscription;
  final VoidCallback onSubscriptionUpdated;

  const EditSubscriptionDialog({
    super.key,
    required this.subscription,
    required this.onSubscriptionUpdated,
  });

  @override
  createState() => _EditSubscriptionDialogState();
}

class _EditSubscriptionDialogState extends State<EditSubscriptionDialog> {
  /// "Ödenmiş Miktar" salt okunur: tutar yalnızca gerçek ödeme kayıtlarından
  /// hesaplanmalı, elle yazılmamalı.
  static const String _amountPaidNote =
      'Bu alan düzenlenemez. Değiştirmek için Ödemeler sekmesinden ödeme '
      'ekleyin veya düzenleyin.';

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _packageNameController;
  late TextEditingController _notesController;
  late TextEditingController _totalMeetingsController;
  late TextEditingController _totalAmountController;
  late TextEditingController _amountPaidController;
  late TextEditingController _onlineMeetingsController;
  late TextEditingController _faceToFaceMeetingsController;
  late TextEditingController _postponementsUsedController;
  late TextEditingController _allowedPostponementsController;
  DateTime? _startDate;
  // Freeze date is only relevant when the package type is "Donduruldu".
  DateTime? _freezeDate;
  bool _isLoading = false;
  late SubActiveStatus _status;
  // Package duration type (1 Aylık / 3 Aylık). Changing it auto-fills the
  // suggested meeting count; the admin can still edit it afterwards.
  SubsPackageType? _packageType;
  late SubsMeetingType _meetingType;
  bool _isPaymentIncomplete = false;

  // Tracks whether the admin has manually overridden the auto-calculated
  // allowed postponements. Once true, we stop auto-updating that field.
  bool _allowedPostponementsEditedManually = false;

  // Weight-tracking packages have no payment; payment widgets are hidden.
  bool get _isWeightTracking =>
      _status == SubActiveStatus.activeWeightTracking;

  final Logger _logger = Logger.forClass(EditSubscriptionDialog);

  // Payment type of the payment(s) linked to this subscription.
  // Null = unspecified (PaymentType.na). Loaded from the linked payment so the
  // admin can review/change it; changes are propagated back to the payment(s).
  PaymentType? _paymentType;
  PaymentType? _originalPaymentType;
  bool _loadingPaymentType = true;

  // Whether a payment has been received for this package. Controls the payment
  // detail fields (amount paid + type) and, on save, whether the linked payment
  // record is created, kept in sync, or deleted.
  bool _isPaymentReceived = false;

  // Completed payment records currently linked to this subscription (loaded
  // once). Used to decide between creating, syncing, or deleting the payment
  // on save.
  List<PaymentModel> _completedPayments = [];

  // Planned ("Ödeme Alınacak") payment records linked to this subscription.
  // When one exists, only its planned date is editable here; the record itself
  // is managed from the payments tab. While a planned payment exists, the
  // package cannot be switched to "Ödeme Alındı" (Tamamlandı) from this dialog.
  bool _isPaymentPlanned = false;
  List<PaymentModel> _plannedPayments = [];
  final TextEditingController _plannedDateController =
      TextEditingController(text: MaskedDateInputFormatter.emptyMask);

  @override
  void initState() {
    super.initState();
    _packageNameController =
        TextEditingController(text: widget.subscription.packageName);
    _notesController =
        TextEditingController(text: widget.subscription.notes ?? '');
    _totalMeetingsController = TextEditingController(
        text: widget.subscription.totalMeetings.toString());
    // Tutarlar tam liradır: alanlarda "7200.0" değil "7200" gösterilir.
    _totalAmountController = TextEditingController(
        text: formatWholeLira(widget.subscription.totalAmount));
    _amountPaidController = TextEditingController(
        text: formatWholeLira(widget.subscription.amountPaid));
    _onlineMeetingsController = TextEditingController(
        text: widget.subscription.onlineMeetings?.toString() ?? "0");
    _faceToFaceMeetingsController = TextEditingController(
        text: widget.subscription.faceToFaceMeetings?.toString() ?? "0");
    _postponementsUsedController = TextEditingController(
        text: widget.subscription.postponementsUsed.toString());
    _allowedPostponementsController = TextEditingController(
        text: widget.subscription.allowedPostponements.toString());
    _startDate = widget.subscription.startDate;
    _freezeDate = widget.subscription.freezeDate;
    _status = widget.subscription.status;
    _packageType = widget.subscription.packageType;
    _meetingType = widget.subscription.meetingType;
    
    // Check if payment is incomplete
    _isPaymentIncomplete = widget.subscription.amountPaid < widget.subscription.totalAmount;

    // Consider payment received when some amount has been paid; refined once the
    // linked payment record(s) are loaded.
    _isPaymentReceived = widget.subscription.amountPaid > 0;
    
    // Add listeners to update payment status
    _totalAmountController.addListener(_updatePaymentStatus);
    _amountPaidController.addListener(_updatePaymentStatus);
    
    // Add listener to update allowed postponements when total meetings changes
    _totalMeetingsController.addListener(_updateState);

    _loadLinkedPaymentType();
  }

  /// Loads the payment type from the payment(s) linked to this subscription so
  /// the dropdown reflects the current value. Uses the most recent payment.
  Future<void> _loadLinkedPaymentType() async {
    try {
      final paymentProvider =
          Provider.of<PaymentProvider>(context, listen: false);
      final payments = await paymentProvider.fetchPayments(
        widget.subscription.subscriptionId,
        userId: widget.subscription.userId,
        showAllPayments: false,
      );

      final completed = payments
          .where((p) => p.status == PaymentStatus.completed)
          .toList();
      final planned =
          payments.where((p) => p.status == PaymentStatus.planned).toList();

      PaymentType? type;
      if (completed.isNotEmpty &&
          completed.first.paymentType != PaymentType.na) {
        type = completed.first.paymentType;
      }

      if (mounted) {
        setState(() {
          _completedPayments = completed;
          _plannedPayments = planned;
          _paymentType = type;
          _originalPaymentType = type;
          // Payment is "received" when a completed record exists or an amount
          // was paid. Planned payments do NOT count as received.
          _isPaymentReceived =
              completed.isNotEmpty || widget.subscription.amountPaid > 0;
          _isPaymentPlanned = planned.isNotEmpty;
          if (planned.isNotEmpty && planned.first.dueDate != null) {
            _plannedDateController.text =
                DateFormatter.formatNumericDate(planned.first.dueDate!);
          }
          _loadingPaymentType = false;
        });
      }
    } catch (e) {
      _logger.err('Error loading linked payment type: {}', [e]);
      if (mounted) {
        setState(() => _loadingPaymentType = false);
      }
    }
  }
  
  void _updatePaymentStatus() {
    final totalAmount = parseWholeLiraOrNull(_totalAmountController.text) ?? 0;
    final amountPaid = parseWholeLiraOrNull(_amountPaidController.text) ?? 0;
    
    setState(() {
      _isPaymentIncomplete = amountPaid < totalAmount;
    });
  }

  void _updateState() {
    // Keep the allowed-postponements field in sync with the auto-calculated
    // value while the admin has not manually edited it.
    if (!_allowedPostponementsEditedManually) {
      final total = int.tryParse(_totalMeetingsController.text) ?? 0;
      final suggested =
          SubscriptionModel.calculateAllowedPostponements(total).toString();
      if (_allowedPostponementsController.text != suggested) {
        _allowedPostponementsController.text = suggested;
      }
    }
    // This will refresh the UI, updating the helper text for postponements
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paket Düzenle'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: ListBody(
            children: [
              const SizedBox(height: 16),
              // Package status (topmost). Selecting Aktif/Kilo Takip hides the
              // payment widgets.
              DropdownButtonFormField<SubActiveStatus>(
                value: _status,
                items: SubActiveStatus.values.map((SubActiveStatus status) {
                  return DropdownMenuItem<SubActiveStatus>(
                    value: status,
                    child: Text(status.displayName),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    _status = newValue!;
                    // Keep the package type valid for the new status (Aktif/Kilo
                    // Takip → only "6 Aylık"; other statuses → 1/3 Aylık). When a
                    // status leaves exactly one option, pre-select it.
                    if (_packageType == null ||
                        !_packageType!.isAvailableFor(_status)) {
                      final options = SubsPackageType.availableFor(_status);
                      _packageType =
                          options.length == 1 ? options.first : null;
                      if (_packageType != null) {
                        _totalMeetingsController.text =
                            _packageType!.defaultMeetings.toString();
                      }
                    }
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Paket Durumu',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Package duration type. Changing it auto-fills the suggested
              // meeting count (still editable by the admin below).
              DropdownButtonFormField<SubsPackageType>(
                value: _packageType,
                isExpanded: true,
                // Offer the durations valid for the current status, but always
                // keep the already-saved type in the list so an existing
                // "6 Aylık" package (whose status may since have changed) still
                // shows and never breaks the dropdown.
                items: <SubsPackageType>{
                  ...SubsPackageType.availableFor(_status),
                  if (_packageType != null) _packageType!,
                }.map((SubsPackageType type) {
                  return DropdownMenuItem<SubsPackageType>(
                    value: type,
                    child: Text(
                      '${type.label} (${type.defaultMeetings} görüşme)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                // A "Kilo Takip" package is fixed to "6 Aylık", so its type is
                // locked (not editable) here; other statuses stay editable
                // within their allowed durations.
                onChanged: _status == SubActiveStatus.activeWeightTracking
                    ? null
                    : (newValue) {
                        setState(() {
                          _packageType = newValue;
                          if (newValue != null) {
                            _totalMeetingsController.text =
                                newValue.defaultMeetings.toString();
                          }
                        });
                      },
                decoration: InputDecoration(
                  labelText: _status == SubActiveStatus.activeWeightTracking
                      ? 'Paket Tipi (Kilo Takip: değiştirilemez)'
                      : 'Paket Tipi',
                  hintText: 'Paket süresini seçin',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Freeze date (shown/editable only when the package is frozen).
              if (_status == SubActiveStatus.frozen) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _freezeDate == null
                        ? 'Dondurulma Tarihi Seçimi'
                        : 'Dondurulma Tarihi: ${DateFormatter.formatNumericDate(_freezeDate!)}',
                    style: _freezeDate != null
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null,
                  ),
                  trailing: const Icon(Icons.ac_unit),
                  onTap: () async {
                    final DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: _freezeDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2050),
                    );
                    if (pickedDate != null) {
                      setState(() => _freezeDate = pickedDate);
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _packageNameController,
                decoration: const InputDecoration(
                  labelText: 'Paket İsmi',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Lütfen paket ismini giriniz./n(ör: 1 ay,ekim-kasım)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notlar',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _totalMeetingsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Toplam Görüşme Sayısı',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Toplam görüşme sayısını giriniz.';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Geçersiz görüşme sayısı. Lütfen girdiğiniz sayıyı kontrol ediniz.';
                  }
                  return null;
                },
              ),
              // Fee + payment widgets are hidden entirely for free
              // weight-tracking packages.
              if (!_isWeightTracking) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _totalAmountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: wholeLiraInputFormatters,
                  decoration: const InputDecoration(
                    labelText: 'Toplam Ücret (TL)',
                    border: OutlineInputBorder(),
                    helperText: 'Tam lira; kuruş girilmez.',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Lütfen toplam ödeme miktarını giriniz.';
                    }
                    if (parseWholeLiraOrNull(value) == null) {
                      return 'Geçersiz ödeme miktarı. Lütfen kontrol ediniz.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Ödenmiş miktar her zaman görünür ama salt okunur.
                TextFormField(
                  controller: _amountPaidController,
                  // Salt okunur: değer ödeme kayıtlarından gelir. Elle
                  // yazılabildiğinde paketin ödenen tutarı gerçek ödemelerden
                  // kopabiliyordu.
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Ödenmiş Miktar (TL)',
                    border: const OutlineInputBorder(),
                    helperText: _amountPaidNote,
                    helperMaxLines: 3,
                    filled: _isPaymentIncomplete,
                    fillColor:
                        _isPaymentIncomplete ? Colors.red.shade100 : null,
                    labelStyle: _isPaymentIncomplete
                        ? TextStyle(color: Colors.red.shade800)
                        : null,
                  ),
                  style: _isPaymentIncomplete
                      ? TextStyle(
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.bold)
                      : null,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Lütfen ödenmiş miktarı giriniz.';
                    }
                    if (parseWholeLiraOrNull(value) == null) {
                      return 'Geçerli bir miktar girin.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // Whether a payment has been received. Checking it (when none
                // exists) creates a payment record on save. Unchecking is
                // disabled so a linked payment can never be deleted from here.
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ödeme Alındı mı?'),
                  // Unchecking is intentionally disabled: it would silently
                  // delete the linked payment record. To remove/adjust a
                  // payment, use the Ödeme (payments) tab instead. Likewise a
                  // planned (Planlandı) payment cannot be switched to
                  // Tamamlandı from here.
                  subtitle: _isPaymentPlanned
                      ? Text(
                          'Planlanmış ödeme varken Tamamlandı olarak işaretlenemez. Ödeme sekmesini kullanın.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        )
                      : _isPaymentReceived
                          ? Text(
                              'Ödeme kaydını kaldırmak/düzenlemek için Ödeme sekmesini kullanın.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            )
                          : null,
                  value: _isPaymentReceived,
                  onChanged: (val) {
                    // Only allow turning payment ON; ignore attempts to uncheck.
                    if (val != true) return;
                    // A planned payment cannot be marked as completed here.
                    if (_isPaymentPlanned) return;
                    // Default the amount to the package total and pick a real
                    // payment type when turning payment on.
                    final paid =
                        parseWholeLiraOrNull(_amountPaidController.text) ?? 0;
                    if (paid <= 0) {
                      _amountPaidController.text = _totalAmountController.text;
                    }
                    _paymentType ??= PaymentType.nakit;
                    setState(() => _isPaymentReceived = true);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                // Payment type is only relevant when a payment was received.
                if (_isPaymentReceived) ...[
                  const SizedBox(height: 8),
                  // Payment type of the linked payment (Nakit / Pos / Iban).
                  // Changing it updates the corresponding payment record(s).
                  if (_loadingPaymentType)
                    const Center(child: CircularProgressIndicator())
                  else
                    DropdownButtonFormField<PaymentType>(
                      value: _paymentType,
                      hint: const Text('Belirtilmemiş'),
                      items:
                          PaymentType.selectableValues.map((PaymentType type) {
                        return DropdownMenuItem<PaymentType>(
                          value: type,
                          child: Text(type.label),
                        );
                      }).toList(),
                      onChanged: (newValue) =>
                          setState(() => _paymentType = newValue),
                      decoration: const InputDecoration(
                        labelText: 'Ödeme Türü',
                        border: OutlineInputBorder(),
                        helperText: 'Bağlı ödeme kaydına uygulanır',
                      ),
                    ),
                  // Received payment date — shown read-only (not editable here;
                  // the date is managed from the payments tab). Only visible
                  // while "Ödeme Alındı" is checked.
                  if (!_loadingPaymentType) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ödeme Alınan Tarih'),
                      subtitle: Text(
                        _completedPayments.isNotEmpty &&
                                _completedPayments.first.paymentDate != null
                            ? DateFormatter.formatNumericDate(
                                _completedPayments.first.paymentDate!)
                            : 'Belirtilmemiş',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: const Icon(Icons.lock_outline, size: 18),
                    ),
                  ],
                ],

                // Planned payment ("Ödeme Alınacak"): reflects the linked
                // planned payment record. The checkbox itself is read-only
                // here (the record is managed from the payments tab); only the
                // planned date can be changed, which is applied to the linked
                // payment record on save.
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ödeme Alınacak mı?'),
                  subtitle: _isPaymentPlanned
                      ? Text(
                          'Planlanan ödeme kaydını kaldırmak için Ödeme sekmesini kullanın.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        )
                      : null,
                  value: _isPaymentPlanned,
                  onChanged: null,
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                // Planned payment date (editable; applied to the linked
                // payment record on save).
                if (_isPaymentPlanned) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _plannedDateController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [MaskedDateInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Ödemenin Alınacağı Tarih',
                      helperText:
                          'gg.aa.yyyy — değişiklik bağlı ödeme kaydına uygulanır.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.event),
                    ),
                    validator: (v) {
                      if (!_isPaymentPlanned) return null;
                      if (v == null || parseDayMonthYear(v) == null) {
                        return 'Geçerli bir tarih girin (gg.aa.yyyy).';
                      }
                      return null;
                    },
                  ),
                ],
              ],
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _startDate == null
                      ? 'Başlangıç Tarihi Seçimi'
                      : 'Başlangıç Tarihi: ${DateFormatter.formatNumericDate(_startDate!)}',
                  style: _startDate != null
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null,
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  DateTime? pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  // Keep the previously selected date if the user cancels.
                  if (pickedDate != null) {
                    setState(() {
                      _startDate = pickedDate;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              // Meeting Type Selection
              const Text('Görüşme Türü', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ToggleButtons(
                direction: Axis.horizontal,
                onPressed: (int index) {
                  setState(() {
                    _meetingType = SubsMeetingType.values[index];
                  });
                },
                constraints: const BoxConstraints(
                  minHeight: 40.0,
                  minWidth: 100.0,
                ),
                borderRadius: BorderRadius.circular(8),
                isSelected: [
                  _meetingType == SubsMeetingType.online,
                  _meetingType == SubsMeetingType.faceToFace,
                  _meetingType == SubsMeetingType.hybrid,
                ],
                children: const <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Online'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Yüz Yüze'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Online+Yüz Yüze'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Online and Face to Face Meeting inputs for hybrid
              if (_meetingType == SubsMeetingType.hybrid)
                Column(
                  children: [
                    TextFormField(
                      controller: _onlineMeetingsController,
                      decoration: const InputDecoration(
                        labelText: 'Online Görüşme Sayısı',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Lütfen online görüşme sayısını girin.';
                        }
                        if (int.tryParse(value) == null) {
                          return 'Geçerli bir sayı girin.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _faceToFaceMeetingsController,
                      decoration: const InputDecoration(
                        labelText: 'Yüz Yüze Görüşme Sayısı',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Lütfen yüz yüze görüşme sayısını girin.';
                        }
                        if (int.tryParse(value) == null) {
                          return 'Geçerli bir sayı girin.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              const SizedBox(height: 16),

              // Allowed Postponements (auto-calculated, editable)
              TextFormField(
                controller: _allowedPostponementsController,
                decoration: const InputDecoration(
                  labelText: 'Toplam İzin Verilen Erteleme Sayısı',
                  border: OutlineInputBorder(),
                  helperText: 'Görüşme sayısına göre otomatik hesaplanır, değiştirilebilir.',
                  helperStyle: TextStyle(fontStyle: FontStyle.italic),
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => _allowedPostponementsEditedManually = true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Lütfen izin verilen erteleme sayısını girin.';
                  }
                  final parsed = int.tryParse(value);
                  if (parsed == null) {
                    return 'Geçerli bir sayı girin.';
                  }
                  if (parsed < 0) {
                    return 'Erteleme sayısı negatif olamaz.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // Postponements Used field
              TextFormField(
                controller: _postponementsUsedController,
                decoration: const InputDecoration(
                  labelText: 'Kullanılan Erteleme Sayısı',
                  border: OutlineInputBorder(),
                  hintText: 'Müşteri tarafından kullanılan erteleme sayısı',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Lütfen kullanılan erteleme sayısını girin.';
                  }
                  
                  final postponements = int.tryParse(value);
                  if (postponements == null) {
                    return 'Geçerli bir sayı girin.';
                  }
                  
                  // Max is the admin-editable allowed postponements value above
                  final allowedPostponements =
                      int.tryParse(_allowedPostponementsController.text) ?? 0;
                  
                  if (postponements < 0) {
                    return 'Erteleme sayısı negatif olamaz.';
                  }
                  
                  if (postponements > allowedPostponements) {
                    return 'Erteleme sayısı izin verilen maksimum değeri ($allowedPostponements) aşamaz.';
                  }
                  
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          // Disabled while the linked payment is still loading so we never
          // create a duplicate payment record by acting on stale data.
          onPressed:
              (_isLoading || _loadingPaymentType) ? null : _updateSubscription,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Paket Güncelle'),
        ),
      ],
    );
  }

  Future<void> _updateSubscription() async {
    if (_formKey.currentState!.validate()) {
      if (_status == SubActiveStatus.frozen && _freezeDate == null) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Paket donduruldu olarak işaretlendi. Lütfen dondurulma tarihini seçin.',
        );
        return;
      }

      if (_meetingType == SubsMeetingType.hybrid) {
        int online = int.tryParse(_onlineMeetingsController.text) ?? 0;
        int faceToFace = int.tryParse(_faceToFaceMeetingsController.text) ?? 0;
        int total = int.tryParse(_totalMeetingsController.text) ?? 0;
        
        if (online + faceToFace != total) {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Online ve yüz yüze görüşme sayıları toplamı, toplam görüşme sayısına eşit olmalıdır.',
          );
          return;
        }
      }

      try {
        setState(() {
          _isLoading = true;
        });

        final userId = widget.subscription.userId;
        final subscriptionId = widget.subscription.subscriptionId;
        final totalMeetings = int.parse(_totalMeetingsController.text);
        
        // Admin-editable allowed postponements (pre-filled with the auto-calculated value)
        final allowedPostponements = int.parse(_allowedPostponementsController.text);

        // Weight-tracking packages are free: no fee and no payment. When the
        // admin marks the payment as not received, nothing is considered paid.
        // Alanlar tam lira; modeldeki double'a yalnızca yazarken çevrilir.
        final double totalAmount = _isWeightTracking
            ? 0.0
            : parseWholeLiraOrNull(_totalAmountController.text)!.toDouble();
        final double amountPaid = (_isWeightTracking || !_isPaymentReceived)
            ? 0.0
            : parseWholeLiraOrNull(_amountPaidController.text)!.toDouble();
        
        final String notes = _notesController.text.trim();

        // Create an update map with raw data - no subscription model objects
        final Map<String, dynamic> updateData = {
          'packageName': _packageNameController.text,
          'packageType': _packageType?.label,
          'notes': notes.isNotEmpty ? notes : null,
          'startDate': _startDate!,
          'totalMeetings': totalMeetings,
          'allowedPostponements': allowedPostponements,
          'postponementsUsed': int.parse(_postponementsUsedController.text),
          'totalAmount': totalAmount,
          'amountPaid': amountPaid,
          'status': _status.label,
          'meetingType': _meetingType.label,
          // Store the freeze date for frozen packages; clear it otherwise so a
          // package that gets unfrozen doesn't keep a stale freeze date.
          'freezeDate': _status == SubActiveStatus.frozen ? _freezeDate : null,
          'updateDate': DateTime.now(),
          'updateUser': null, // TODO: Add current user ID if available
        };
        
        // Add hybrid meeting details if applicable
        if (_meetingType == SubsMeetingType.hybrid) {
          updateData['onlineMeetings'] = int.parse(_onlineMeetingsController.text);
          updateData['faceToFaceMeetings'] = int.parse(_faceToFaceMeetingsController.text);
        } else {
          // Set these to null if not hybrid
          updateData['onlineMeetings'] = null;
          updateData['faceToFaceMeetings'] = null;
        }

        // Acquire providers before awaits to avoid context issues
        final subProvider = Provider.of<SubProvider>(context, listen: false);
        final paymentProvider =
            Provider.of<PaymentProvider>(context, listen: false);

        final double oldTotalAmount = widget.subscription.totalAmount;
        final double newTotalAmount = totalAmount;

        // Use the SubProvider to update the subscription
        await subProvider.updateSubscription(
          userId: userId,
          subscriptionId: subscriptionId,
          updateData: updateData,
        );

        // Reconcile the linked payment record with the "Ödeme Alındı mı?"
        // selection: create one when payment is now received but none exists,
        // keep it in sync when it already exists, or delete it when payment is
        // no longer received. Weight-tracking packages never carry a payment.
        if (!_isWeightTracking) {
          if (_isPaymentReceived) {
            if (_completedPayments.isEmpty) {
              await paymentProvider.addPayment(
                userId: userId,
                subscription: SubscriptionModel(
                  subscriptionId: subscriptionId,
                  userId: userId,
                  packageName: _packageNameController.text,
                  startDate: _startDate!,
                  totalMeetings: totalMeetings,
                  allowedPostponements: allowedPostponements,
                  totalAmount: totalAmount,
                  meetingType: _meetingType,
                ),
                amount: amountPaid,
                paymentDate: _startDate,
                status: PaymentStatus.completed,
                paymentType: _paymentType ?? PaymentType.nakit,
                notes: 'Paket ödemesi: ${_packageNameController.text}',
              );
            } else {
              // Only send a new payment type when the admin actually changed it.
              final PaymentType? changedPaymentType =
                  (_paymentType != null && _paymentType != _originalPaymentType)
                      ? _paymentType
                      : null;
              await paymentProvider.syncSubscriptionLinkedPayments(
                userId: userId,
                subscriptionId: subscriptionId,
                newPaymentType: changedPaymentType,
                oldAmount: oldTotalAmount,
                newAmount: newTotalAmount,
              );
            }
          } else {
            // Payment no longer received: remove the linked completed
            // record(s). Planned payments are never deleted from here; they
            // are managed from the payments tab.
            for (final payment in _completedPayments) {
              // This dialog has already written the package's amountPaid above,
              // so the delete must not subtract the amount a second time.
              await paymentProvider.deletePayment(
                payment.paymentId,
                userId,
                adjustSubscriptionTotal: false,
              );
            }
          }

          // Apply a changed planned date to the linked planned payment
          // record(s) so the payment stays in sync with this dialog.
          if (_isPaymentPlanned && _plannedPayments.isNotEmpty) {
            final DateTime? newPlannedDate =
                parseDayMonthYear(_plannedDateController.text);
            if (newPlannedDate != null) {
              for (final payment in _plannedPayments) {
                final DateTime? currentDueDate = payment.dueDate;
                if (currentDueDate == null ||
                    !DateUtils.isSameDay(currentDueDate, newPlannedDate)) {
                  await paymentProvider.updatePaymentDueDate(
                    userId: userId,
                    paymentId: payment.paymentId,
                    dueDate: newPlannedDate,
                  );
                }
              }
            }
            // Keep the planned payment's amount mirroring the package total
            // when it changed (no-op if the amounts already match).
            if (!_isPaymentReceived) {
              await paymentProvider.syncSubscriptionLinkedPayments(
                userId: userId,
                subscriptionId: subscriptionId,
                oldAmount: oldTotalAmount,
                newAmount: newTotalAmount,
              );
            }
          }
        }

        if (!mounted) return;
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Paket başarıyla güncellendi.',
        );
        
        // Close dialog first, then notify parent about the update
        // Re-checked after the await: the widget may be gone by now.
        if (!mounted) return;
        Navigator.of(context).pop();
        
        // Call the update callback after dialog is closed
        widget.onSubscriptionUpdated();
      } catch (e) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Paket güncellenirken bir hata oluştu: $e',
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    // Remove listeners
    _totalAmountController.removeListener(_updatePaymentStatus);
    _amountPaidController.removeListener(_updatePaymentStatus);
    _totalMeetingsController.removeListener(_updateState);
    
    // Dispose controllers
    _packageNameController.dispose();
    _notesController.dispose();
    _totalMeetingsController.dispose();
    _totalAmountController.dispose();
    _amountPaidController.dispose();
    _onlineMeetingsController.dispose();
    _faceToFaceMeetingsController.dispose();
    _postponementsUsedController.dispose();
    _allowedPostponementsController.dispose();
    _plannedDateController.dispose();
    super.dispose();
  }
}
