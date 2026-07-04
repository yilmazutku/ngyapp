import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/dialog_utils.dart';

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
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _packageNameController;
  late TextEditingController _totalMeetingsController;
  late TextEditingController _totalAmountController;
  late TextEditingController _amountPaidController;
  late TextEditingController _onlineMeetingsController;
  late TextEditingController _faceToFaceMeetingsController;
  late TextEditingController _postponementsUsedController;
  late TextEditingController _allowedPostponementsController;
  DateTime? _startDate;
  bool _isLoading = false;
  late SubActiveStatus _status;
  late SubsMeetingType _meetingType;
  bool _isPaymentIncomplete = false;

  // Tracks whether the admin has manually overridden the auto-calculated
  // allowed postponements. Once true, we stop auto-updating that field.
  bool _allowedPostponementsEditedManually = false;

  final Logger _logger = Logger.forClass(EditSubscriptionDialog);

  // Payment type of the payment(s) linked to this subscription.
  // Null = unspecified (PaymentType.na). Loaded from the linked payment so the
  // admin can review/change it; changes are propagated back to the payment(s).
  PaymentType? _paymentType;
  PaymentType? _originalPaymentType;
  bool _loadingPaymentType = true;

  @override
  void initState() {
    super.initState();
    _packageNameController =
        TextEditingController(text: widget.subscription.packageName);
    _totalMeetingsController = TextEditingController(
        text: widget.subscription.totalMeetings.toString());
    _totalAmountController =
        TextEditingController(text: widget.subscription.totalAmount.toString());
    _amountPaidController =
        TextEditingController(text: widget.subscription.amountPaid.toString());
    _onlineMeetingsController = TextEditingController(
        text: widget.subscription.onlineMeetings?.toString() ?? "0");
    _faceToFaceMeetingsController = TextEditingController(
        text: widget.subscription.faceToFaceMeetings?.toString() ?? "0");
    _postponementsUsedController = TextEditingController(
        text: widget.subscription.postponementsUsed.toString());
    _allowedPostponementsController = TextEditingController(
        text: widget.subscription.allowedPostponements.toString());
    _startDate = widget.subscription.startDate;
    _status = widget.subscription.status;
    _meetingType = widget.subscription.meetingType;
    
    // Check if payment is incomplete
    _isPaymentIncomplete = widget.subscription.amountPaid < widget.subscription.totalAmount;
    
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

      PaymentType? type;
      if (payments.isNotEmpty && payments.first.paymentType != PaymentType.na) {
        type = payments.first.paymentType;
      }

      if (mounted) {
        setState(() {
          _paymentType = type;
          _originalPaymentType = type;
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
    final totalAmount = double.tryParse(_totalAmountController.text) ?? 0.0;
    final amountPaid = double.tryParse(_amountPaidController.text) ?? 0.0;
    
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
      title: const Text('Abonelik Düzenle'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: ListBody(
            children: [
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _totalAmountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Toplam Ücret (TL)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Lütfen toplam ödeme miktarını giriniz.';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Geçersiz ödeme miktarı. Lütfen kontrol ediniz.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountPaidController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Ödenmiş Miktar (TL)',
                  border: const OutlineInputBorder(),
                  filled: _isPaymentIncomplete,
                  fillColor: _isPaymentIncomplete ? Colors.red.shade100 : null,
                  labelStyle: _isPaymentIncomplete 
                    ? TextStyle(color: Colors.red.shade800)
                    : null,
                ),
                style: _isPaymentIncomplete 
                  ? TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold)
                  : null,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Lütfen ödenmiş miktarı giriniz.';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Geçerli bir miktar girin.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Payment type of the linked payment (Nakit / Pos / Iban).
              // Changing it updates the corresponding payment record(s).
              if (_loadingPaymentType)
                const Center(child: CircularProgressIndicator())
              else
                DropdownButtonFormField<PaymentType>(
                  value: _paymentType,
                  hint: const Text('Belirtilmemiş'),
                  items: PaymentType.selectableValues.map((PaymentType type) {
                    return DropdownMenuItem<PaymentType>(
                      value: type,
                      child: Text(type.label),
                    );
                  }).toList(),
                  onChanged: (newValue) => setState(() => _paymentType = newValue),
                  decoration: const InputDecoration(
                    labelText: 'Ödeme Türü',
                    border: OutlineInputBorder(),
                    helperText: 'Bağlı ödeme kaydına uygulanır',
                  ),
                ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_startDate == null
                    ? 'Başlangıç Tarihi Seçimi'
                    : 'Başlangıç Tarihi: ${_startDate!.toLocal().toString().split(' ')[0]}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  DateTime? pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate:
                        DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  setState(() {
                    _startDate = pickedDate;
                  });
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
              const SizedBox(height: 16),
              
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
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Paket Durumu',
                  border: OutlineInputBorder(),
                ),
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
          onPressed: _isLoading ? null : _updateSubscription,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Paket Güncelle'),
        ),
      ],
    );
  }

  Future<void> _updateSubscription() async {
    if (_formKey.currentState!.validate()) {
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
        
        // Create an update map with raw data - no subscription model objects
        final Map<String, dynamic> updateData = {
          'packageName': _packageNameController.text,
          'startDate': _startDate!,
          'totalMeetings': totalMeetings,
          'allowedPostponements': allowedPostponements,
          'postponementsUsed': int.parse(_postponementsUsedController.text),
          'totalAmount': double.parse(_totalAmountController.text),
          'amountPaid': double.parse(_amountPaidController.text),
          'status': _status.label,
          'meetingType': _meetingType.label,
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
        final double newTotalAmount = double.parse(_totalAmountController.text);

        // Use the SubProvider to update the subscription
        await subProvider.updateSubscription(
          userId: userId,
          subscriptionId: subscriptionId,
          updateData: updateData,
        );

        // Propagate payment-type and amount changes to the linked payment(s).
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

        if (!mounted) return;
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Abonelik başarıyla güncellendi.',
        );
        
        // Close dialog first, then notify parent about the update
        Navigator.of(context).pop();
        
        // Call the update callback after dialog is closed
        widget.onSubscriptionUpdated();
      } catch (e) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Abonelik güncellenirken bir hata oluştu: $e',
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
    _totalMeetingsController.dispose();
    _totalAmountController.dispose();
    _amountPaidController.dispose();
    _onlineMeetingsController.dispose();
    _faceToFaceMeetingsController.dispose();
    _postponementsUsedController.dispose();
    _allowedPostponementsController.dispose();
    super.dispose();
  }
}
