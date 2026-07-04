import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/dialog_utils.dart';

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
  final TextEditingController _totalMeetingsController =
      TextEditingController();
  final TextEditingController _totalAmountController = TextEditingController();
  final TextEditingController _onlineMeetingsController = TextEditingController();
  final TextEditingController _faceToFaceMeetingsController = TextEditingController();
  final TextEditingController _allowedPostponementsController = TextEditingController();
  
  DateTime? _startDate=DateTime.now();
  bool _isLoading = false;
  bool _isPaymentReceived = false;
  PaymentType _paymentType = PaymentType.nakit;
  SubsMeetingType _selectedMeetingType = SubsMeetingType.faceToFace;

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
      title: const Text('Yeni Abonelik Paketi Ekle'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520), // <-- give the dialog content a width cap
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Package Name
                TextFormField(
                  controller: _packageNameController,
                  decoration: const InputDecoration(
                    labelText: 'Paket Adı',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'Lütfen bir paket adı girin.' : null,
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

                // Total Amount
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

                // Start Date
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Başlangıç Tarihi'),
                  subtitle: Text(_startDate != null
                      ? DateFormat('d MMMM yyyy', 'tr_TR').format(_startDate!)
                      : 'Bir tarih seçin', style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
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

                // Payment Received Checkbox
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ödeme Alındı mı?'),
                  value: _isPaymentReceived,
                  onChanged: (val) => setState(() => _isPaymentReceived = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                // Payment type for the created payment (only when payment received)
                if (_isPaymentReceived) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<PaymentType>(
                    value: _paymentType,
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
              : const Text('Abonelik Ekle'),
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

      // Prepare subscription data
      final subscriptionData = {
        'packageName': _packageNameController.text,
        'startDate': _startDate!,
        'totalMeetings': totalMeetings,
        'meetingsCompleted': 0,
        'meetingsRemaining': totalMeetings,
        'meetingsBurned': 0,
        'postponementsUsed': 0,
        'allowedPostponements': allowedPostponements,
        'totalAmount': double.parse(_totalAmountController.text),
        'amountPaid': _isPaymentReceived 
            ? double.parse(_totalAmountController.text) 
            : 0.0,
        'status': SubActiveStatus.active.label,
        'meetingType': _selectedMeetingType.label,
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
      if (_isPaymentReceived && subscriptionId != null) {
        try {
          final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
          final double paymentAmount = double.parse(_totalAmountController.text);
          
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
            paymentDate: _startDate, // Use subscription start date as payment date
            status: PaymentStatus.completed,
            paymentType: _paymentType,
            notes: 'Abonelik ödemesi: ${_packageNameController.text}',
          );
          
          logger.info('Abonelik ödemesi eklendi');
        } catch (e) {
          logger.err('Error adding payment: {}', [e]);
          if (mounted) {
            await DialogUtils.openError(
              context,
              title: 'Uyarı',
              message: 'Abonelik eklendi fakat ödeme kaydı oluşturulurken bir hata oluştu: $e',
            );
          }
        }
      }

      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: _isPaymentReceived 
            ? 'Abonelik ve ödeme kaydı başarıyla eklendi.'
            : 'Abonelik başarıyla eklendi.',
      );
      widget.onSubscriptionAdded();
      Navigator.of(context).pop();
    } catch (e) {
      logger.err('Error adding subscription: {}', [e]);
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Abonelik eklenirken bir hata oluştu: $e',
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
    _totalMeetingsController.dispose();
    _totalAmountController.dispose();
    _onlineMeetingsController.dispose();
    _faceToFaceMeetingsController.dispose();
    _allowedPostponementsController.dispose();
    super.dispose();
  }
}
