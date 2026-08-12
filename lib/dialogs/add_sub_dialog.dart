import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/date_formatter.dart';

final Logger logger = Logger.forClass(AddSubscriptionDialog);

class AddSubscriptionDialog extends StatefulWidget {
  final String userId;
  final Function onSubscriptionAdded;

  const AddSubscriptionDialog({
    super.key,
    required this.userId,
    required this.onSubscriptionAdded,
  });

  @override
  createState() => _AddSubscriptionDialogState();
}

class _AddSubscriptionDialogState extends State<AddSubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _packageNameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _totalMeetingsController =
      TextEditingController();
  final TextEditingController _totalAmountController = TextEditingController();
  final TextEditingController _onlineMeetingsController = TextEditingController();
  final TextEditingController _faceToFaceMeetingsController = TextEditingController();
  final TextEditingController _allowedPostponementsController = TextEditingController();
  
  DateTime? _startDate=DateTime.now();
  // Freeze date is only relevant when the package type is "Donduruldu".
  DateTime? _freezeDate;
  bool _isLoading = false;
  bool _isPaymentReceived = false;
  // "Ödeme Alınacak": creates a planned payment with the date below.
  // Mutually exclusive with "Ödeme Alındı".
  bool _isPaymentPlanned = false;
  // Planned payment date. Chosen with a date-picker widget (like the start
  // date) and defaulted to the package start date when "Ödeme Alınacak" is
  // enabled; past dates are also allowed.
  DateTime? _plannedDate;
  // Received payment date. Chosen with a date-picker widget and defaulted to
  // the package start date when "Ödeme Alındı" is enabled.
  DateTime? _receivedDate;
  PaymentType _paymentType = PaymentType.nakit;
  SubsMeetingType _selectedMeetingType = SubsMeetingType.faceToFace;

  // Admin picks the package status. Default is Aktif/Haftalık.
  SubActiveStatus _selectedStatus = SubActiveStatus.activeWeekly;

  // Package duration type (1 Aylık / 3 Aylık). Selecting one auto-fills the
  // suggested meeting count; the admin can still edit it afterwards.
  SubsPackageType? _selectedPackageType;

  // Weight-tracking packages have no payment; payment widgets are hidden and
  // no payment record is created for them.
  bool get _isWeightTracking =>
      _selectedStatus == SubActiveStatus.activeWeightTracking;

  // Tracks whether the admin has manually overridden the auto-calculated
  // allowed postponements. Once true, we stop auto-updating that field.
  bool _allowedPostponementsEditedManually = false;

  @override
  void initState() {
    super.initState();
    _totalMeetingsController.addListener(_syncAllowedPostponements);
  }

  /// Keeps the allowed-postponements field in sync with the auto-calculated
  /// value while the admin has not manually edited it.
  void _syncAllowedPostponements() {
    if (_allowedPostponementsEditedManually) return;
    final total = int.tryParse(_totalMeetingsController.text) ?? 0;
    final suggested =
        SubscriptionModel.calculateAllowedPostponements(total).toString();
    if (_allowedPostponementsController.text != suggested) {
      _allowedPostponementsController.text = suggested;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Slimmer insets give the form more usable width, especially on phones.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: const Text('Yeni Paket Ekle'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560), // width cap for the scrollable form
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Package status (topmost). Default: Aktif/Haftalık.
                DropdownButtonFormField<SubActiveStatus>(
                  value: _selectedStatus,
                  isExpanded: true,
                  items: SubActiveStatus.values.map((SubActiveStatus status) {
                    return DropdownMenuItem<SubActiveStatus>(
                      value: status,
                      child: Text(status.displayName),
                    );
                  }).toList(),
                  onChanged: (newValue) =>
                      setState(() => _selectedStatus = newValue!),
                  decoration: const InputDecoration(
                    labelText: 'Paket Durumu',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Package duration type. Selecting one auto-fills the suggested
                // meeting count (still editable by the admin below).
                DropdownButtonFormField<SubsPackageType>(
                  value: _selectedPackageType,
                  isExpanded: true,
                  items: SubsPackageType.values.map((SubsPackageType type) {
                    return DropdownMenuItem<SubsPackageType>(
                      value: type,
                      child: Text(
                        '${type.label} (${type.defaultMeetings} görüşme)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedPackageType = newValue;
                      // Auto-fill the suggested meeting count; the listener on
                      // the field keeps allowed postponements in sync too.
                      if (newValue != null) {
                        _totalMeetingsController.text =
                            newValue.defaultMeetings.toString();
                      }
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: 'Paket Tipi',
                    hintText: 'Paket süresini seçin',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Freeze date (shown only when the package is frozen).
                if (_selectedStatus == SubActiveStatus.frozen) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Dondurulma Tarihi'),
                    subtitle: Text(
                        _freezeDate != null
                            ? DateFormatter.formatNumericDate(_freezeDate!)
                            : 'Bir tarih seçin',
                        style: _freezeDate != null
                            ? const TextStyle(fontWeight: FontWeight.bold)
                            : null),
                    trailing: const Icon(Icons.ac_unit),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _freezeDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2050),
                      );
                      if (picked != null) setState(() => _freezeDate = picked);
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Package Name (optional)
                TextFormField(
                  controller: _packageNameController,
                  decoration: const InputDecoration(
                    labelText: 'Paket Adı (ZORUNLU DEĞİL)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Notes (optional)
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

                // Total Meetings
                TextFormField(
                  controller: _totalMeetingsController,
                  decoration: const InputDecoration(
                    labelText: 'Toplam Görüşme Sayısı',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Lütfen toplam görüşme sayısını girin.';
                    if (int.tryParse(v) == null) return 'Geçerli bir sayı girin.';
                    return null;
                  },
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
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Lütfen izin verilen erteleme sayısını girin.';
                    final parsed = int.tryParse(v);
                    if (parsed == null) return 'Geçerli bir sayı girin.';
                    if (parsed < 0) return 'Erteleme sayısı negatif olamaz.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Total Amount (hidden for free weight-tracking packages)
                if (!_isWeightTracking) ...[
                  TextFormField(
                    controller: _totalAmountController,
                    decoration: const InputDecoration(
                      labelText: 'Toplam Ücret (TL)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Lütfen toplam ücreti girin.';
                      if (double.tryParse(v) == null) return 'Geçerli bir ücret girin.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Start Date
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Başlangıç Tarihi'),
                  subtitle: Text(
                      _startDate != null
                          ? DateFormatter.formatNumericDate(_startDate!)
                          : 'Bir tarih seçin',
                      style: _startDate != null
                          ? const TextStyle(fontWeight: FontWeight.bold)
                          : null),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2050),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                ),
                const SizedBox(height: 16),

                // Meeting Type Selection
                const Text('Görüşme Türü', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

// No LayoutBuilder here (AlertDialog uses Intrinsic* sizing)
                SizedBox(
                  height: 40, // bound the height so SingleChildScrollView has constraints
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ToggleButtons(
                        borderRadius: BorderRadius.circular(8),
                        // Don't set minWidth; only minHeight to avoid forced overflow
                        constraints: const BoxConstraints(minHeight: 40.0),
                        isSelected: [
                          _selectedMeetingType == SubsMeetingType.online,
                          _selectedMeetingType == SubsMeetingType.faceToFace,
                          _selectedMeetingType == SubsMeetingType.hybrid,
                        ],
                        onPressed: (int index) {
                          setState(() {
                            _selectedMeetingType = SubsMeetingType.values[index];
                          });
                        },
                        children: const <Widget>[
                          Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Online')),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Yüz Yüze')),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Online+Yüz Yüze')),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),


                // Hybrid extra fields
                if (_selectedMeetingType == SubsMeetingType.hybrid) ...[
                  TextFormField(
                    controller: _onlineMeetingsController,
                    decoration: const InputDecoration(
                      labelText: 'Online Görüşme Sayısı',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Lütfen online görüşme sayısını girin.';
                      if (int.tryParse(v) == null) return 'Geçerli bir sayı girin.';
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
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Lütfen yüz yüze görüşme sayısını girin.';
                      if (int.tryParse(v) == null) return 'Geçerli bir sayı girin.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Payment section is hidden entirely for weight-tracking packages.
                if (!_isWeightTracking) ...[
                  // Payment Received Checkbox
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ödeme Alındı mı?'),
                    value: _isPaymentReceived,
                    onChanged: (val) => setState(() {
                      _isPaymentReceived = val ?? false;
                      if (_isPaymentReceived) {
                        // Mutually exclusive with "Ödeme Alınacak".
                        _isPaymentPlanned = false;
                        // Default the received payment date to the package start
                        // date when this option is enabled.
                        _receivedDate = _startDate ?? DateTime.now();
                      }
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),

                  // Payment type for the created payment (only when payment received)
                  if (_isPaymentReceived) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<PaymentType>(
                      value: _paymentType,
                      isExpanded: true,
                      items: PaymentType.selectableValues.map((PaymentType type) {
                        return DropdownMenuItem<PaymentType>(
                          value: type,
                          child: Text(type.label),
                        );
                      }).toList(),
                      onChanged: (newValue) => setState(() => _paymentType = newValue!),
                      decoration: const InputDecoration(
                        labelText: 'Ödeme Türü',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Received payment date (date-picker widget, same style as
                    // "Başlangıç Tarihi"). Defaults to the package start date.
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ödeme Alınan Tarih'),
                      subtitle: Text(
                          _receivedDate != null
                              ? DateFormatter.formatNumericDate(_receivedDate!)
                              : 'Bir tarih seçin',
                          style: _receivedDate != null
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null),
                      trailing: const Icon(Icons.event),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _receivedDate ?? _startDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2050),
                        );
                        if (picked != null) {
                          setState(() => _receivedDate = picked);
                        }
                      },
                    ),
                  ],

                  // Payment Planned Checkbox: creates a "Planlandı" payment
                  // with the date entered below.
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ödeme Alınacak mı?'),
                    value: _isPaymentPlanned,
                    onChanged: (val) => setState(() {
                      _isPaymentPlanned = val ?? false;
                      if (_isPaymentPlanned) {
                        // Mutually exclusive with "Ödeme Alındı".
                        _isPaymentReceived = false;
                        // Default the planned payment date to the package start
                        // date (not today) when this option is enabled.
                        _plannedDate = _startDate ?? DateTime.now();
                      }
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),

                  // Planned payment date (only when payment is planned).
                  // Chosen with a date-picker widget, same as "Başlangıç Tarihi".
                  if (_isPaymentPlanned) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ödemenin Alınacağı Tarih'),
                      subtitle: Text(
                          _plannedDate != null
                              ? DateFormatter.formatNumericDate(_plannedDate!)
                              : 'Bir tarih seçin',
                          style: _plannedDate != null
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null),
                      trailing: const Icon(Icons.event),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _plannedDate ?? _startDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2050),
                        );
                        if (picked != null) {
                          setState(() => _plannedDate = picked);
                        }
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),

      actions: [
        TextButton(
          onPressed: () {
            if (!mounted) return;
            Navigator.of(context).pop(); // Close the dialog
          },
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addSubscription,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Paket Ekle'),
        ),
      ],
    );
  }

  Future<void> _addSubscription() async {
    if (!_formKey.currentState!.validate()) {
      logger.warn('Form doğrulama başarısız.');
      return;
    }

    if (_startDate == null) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Lütfen başlangıç tarihini seçin.',
      );
      logger.warn('Başlangıç tarihi seçilmedi.');
      return;
    }

    if (_selectedStatus == SubActiveStatus.frozen && _freezeDate == null) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Paket donduruldu olarak işaretlendi. Lütfen dondurulma tarihini seçin.',
      );
      logger.warn('Dondurulma tarihi seçilmedi.');
      return;
    }

    if (_selectedMeetingType == SubsMeetingType.hybrid) {
      int online = int.tryParse(_onlineMeetingsController.text) ?? 0;
      int faceToFace = int.tryParse(_faceToFaceMeetingsController.text) ?? 0;
      int total = int.tryParse(_totalMeetingsController.text) ?? 0;
      
      if (online + faceToFace != total) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Online ve yüz yüze görüşme sayıları toplamı, toplam görüşme sayısına eşit olmalıdır.',
        );
        logger.warn('Online ve yüz yüze görüşme sayıları toplamı toplam görüşme sayısına eşit değil.');
        return;
      }
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final totalMeetings = int.parse(_totalMeetingsController.text);
      
      // Admin-editable allowed postponements (pre-filled with the auto-calculated value)
      final allowedPostponements = int.parse(_allowedPostponementsController.text);

      // Weight-tracking packages are free and never take a payment, regardless
      // of the (hidden) fields' state.
      final bool paymentReceived = !_isWeightTracking && _isPaymentReceived;
      final bool paymentPlanned =
          !_isWeightTracking && !paymentReceived && _isPaymentPlanned;
      final double totalAmount =
          _isWeightTracking ? 0.0 : double.parse(_totalAmountController.text);

      final String notes = _notesController.text.trim();

      // Prepare subscription data
      final subscriptionData = {
        'packageName': _packageNameController.text,
        if (_selectedPackageType != null)
          'packageType': _selectedPackageType!.label,
        if (notes.isNotEmpty) 'notes': notes,
        'startDate': _startDate!,
        'totalMeetings': totalMeetings,
        'meetingsCompleted': 0,
        'meetingsRemaining': totalMeetings,
        'meetingsBurned': 0,
        'postponementsUsed': 0,
        'allowedPostponements': allowedPostponements,
        'totalAmount': totalAmount,
        'amountPaid': paymentReceived ? totalAmount : 0.0,
        'status': _selectedStatus.label,
        'meetingType': _selectedMeetingType.label,
        // Persist the freeze date only for frozen packages.
        if (_selectedStatus == SubActiveStatus.frozen && _freezeDate != null)
          'freezeDate': _freezeDate,
        'createDate': DateTime.now(),
        'createUser': null, // TODO: Add current user ID if available
      };
      
      // Add online and face-to-face meeting counts for hybrid type
      if (_selectedMeetingType == SubsMeetingType.hybrid) {
        subscriptionData['onlineMeetings'] = int.parse(_onlineMeetingsController.text);
        subscriptionData['faceToFaceMeetings'] = int.parse(_faceToFaceMeetingsController.text);
      }

      // Use the SubProvider to add the subscription
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final String? subscriptionId = await subProvider.addSubscription(
        userId: widget.userId,
        subscriptionData: subscriptionData,
      );

      logger.info('Yeni abonelik eklendi');
      
      // If payment is received, create a payment record
      if (paymentReceived && subscriptionId != null) {
        try {
          final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
          final double paymentAmount = totalAmount;
          
          // Create a payment with the subscription's total amount and start date
          await paymentProvider.addPayment(
            userId: widget.userId,
            subscription: SubscriptionModel(
              subscriptionId: subscriptionId,
              userId: widget.userId,
              packageName: _packageNameController.text,
              startDate: _startDate!,
              totalMeetings: totalMeetings,
              allowedPostponements: allowedPostponements,
              totalAmount: paymentAmount,
              meetingType: _selectedMeetingType,
            ),
            amount: paymentAmount,
            paymentDate: _receivedDate ?? _startDate, // "Ödeme Alınan Tarih"
            status: PaymentStatus.completed,
            paymentType: _paymentType,
            notes: 'Paket ödemesi: ${_packageNameController.text}',
          );
          
          logger.info('Abonelik ödemesi eklendi');
        } catch (e) {
          logger.err('Error adding payment: {}', [e]);
          if (mounted) {
            await DialogUtils.openError(
              context,
              title: 'Uyarı',
              message: 'Paket eklendi fakat ödeme kaydı oluşturulurken bir hata oluştu: $e',
            );
          }
        }
      }

      // If a payment is planned, create a "Planlandı" payment record with the
      // dialog's amount and the entered due date.
      if (paymentPlanned && subscriptionId != null) {
        try {
          final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
          final DateTime plannedDate = _plannedDate ?? _startDate!;

          await paymentProvider.addPayment(
            userId: widget.userId,
            subscription: SubscriptionModel(
              subscriptionId: subscriptionId,
              userId: widget.userId,
              packageName: _packageNameController.text,
              startDate: _startDate!,
              totalMeetings: totalMeetings,
              allowedPostponements: allowedPostponements,
              totalAmount: totalAmount,
              meetingType: _selectedMeetingType,
            ),
            amount: totalAmount,
            dueDate: plannedDate,
            status: PaymentStatus.planned,
            // The real type is chosen when the payment is actually completed.
            paymentType: PaymentType.na,
            notes: 'Paket ödemesi: ${_packageNameController.text}',
          );

          logger.info('Planlanan abonelik ödemesi eklendi');
        } catch (e) {
          logger.err('Error adding planned payment: {}', [e]);
          if (mounted) {
            await DialogUtils.openError(
              context,
              title: 'Uyarı',
              message: 'Paket eklendi fakat planlanan ödeme kaydı oluşturulurken bir hata oluştu: $e',
            );
          }
        }
      }

      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: paymentReceived
            ? 'Paket ve ödeme kaydı başarıyla eklendi.'
            : paymentPlanned
                ? 'Paket ve planlanan ödeme kaydı başarıyla eklendi.'
                : 'Paket başarıyla eklendi.',
      );
      widget.onSubscriptionAdded();
      Navigator.of(context).pop();
    } catch (e) {
      logger.err('Error adding subscription: {}', [e]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Paket eklenirken bir hata oluştu: $e',
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
  void dispose() {
    _totalMeetingsController.removeListener(_syncAllowedPostponements);
    _packageNameController.dispose();
    _notesController.dispose();
    _totalMeetingsController.dispose();
    _totalAmountController.dispose();
    _onlineMeetingsController.dispose();
    _faceToFaceMeetingsController.dispose();
    _allowedPostponementsController.dispose();
    super.dispose();
  }
}
