// dialogs/add_payment_dialog.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/dialog_utils.dart';
import '../widgets/loading_overlay.dart';

class AddPaymentDialog extends StatefulWidget {
  final String userId;
  final Function onPaymentAdded;

  const AddPaymentDialog({
    super.key,
    required this.userId,
    required this.onPaymentAdded,
  });

  @override
  createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends State<AddPaymentDialog> 
    with LoadingStateMixin {
  final Logger logger = Logger.forClass(AddPaymentDialog);
  List<SubscriptionModel> _subscriptions = [];
  SubscriptionModel? _selectedSubscription;
  bool _isLoadingSubscriptions = true;
  final DateFormat df=DateFormat('dd.MM.yyyy', 'tr_TR');
  @override
  void initState() {
    super.initState();
    _paymentStatus = PaymentStatus.completed;
    _fetchSubscriptions();
  }

  Future<void> _fetchSubscriptions() async {
    setState(() {
      _isLoadingSubscriptions = true;
    });

    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final fetched = await subProvider.fetchSubscriptions(
        userId: widget.userId,
        showAllSubscriptions: false,
      );
      // Only active packages can receive payments; frozen/completed are excluded.
      final List<SubscriptionModel> activeSubscriptions =
          fetched.where((s) => s.status.isActive).toList();

      setState(() {
        _subscriptions = activeSubscriptions;
        _isLoadingSubscriptions = false;
        _selectedSubscription =
            _subscriptions.isNotEmpty ? _subscriptions.first : null;
      });

      // No longer show error if no active subscriptions - allow "paketsiz ödeme"
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

  // Controllers and variables
  final TextEditingController _amountController = TextEditingController();
  DateTime? _selectedPaymentDate=DateTime.now();
  DateTime? _selectedDueDate;
  PaymentStatus _paymentStatus = PaymentStatus.completed;
  PaymentType _paymentType = PaymentType.nakit;
  File? _dekontImage;
  final ImagePicker _picker = ImagePicker();

  // New variables for notifications

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AlertDialog(
          title: const Text('Ödeme Ekle'),
          content: SingleChildScrollView(
            child: ListBody(
          children: [
            // Subscription Dropdown
            if (_isLoadingSubscriptions)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<SubscriptionModel?>(
                value: _selectedSubscription,
                items: [
                  const DropdownMenuItem<SubscriptionModel?>(
                    value: null,
                    child: Text('Paketsiz ödeme'),
                  ),
                  ..._subscriptions.map((sub) {
                    String amountInfo = '';
                    if (sub.amountPaid < sub.totalAmount) {
                      final remaining = sub.totalAmount - sub.amountPaid;
                      amountInfo = ' (Kalan ödeme: ${remaining.toStringAsFixed(0)} TL)';
                    }
                    return DropdownMenuItem<SubscriptionModel?>(
                      value: sub,
                      child: Text('${sub.packageName}$amountInfo'),
                    );
                  }).toList(),
                ],
                onChanged: (newValue) {
                  setState(() {
                    _selectedSubscription = newValue;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Bağlı Paket',
                  hintText: 'Paket seçin (opsiyonel)',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 16),
            
            // Amount Field
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              // Whole numbers only — no decimal point / comma.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Miktar (TL)',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Lütfen ödeme miktarını giriniz.';
                }
                if (int.tryParse(value) == null) {
                  return 'Geçerli bir miktar giriniz (tam sayı).';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            //Payment status dropdown
            DropdownButtonFormField<PaymentStatus>(
              value: _paymentStatus,
              items: PaymentStatus.values.map((PaymentStatus status) {
                return DropdownMenuItem<PaymentStatus>(
                  value: status,
                  child: Text(status.label),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _paymentStatus = newValue!;
                  if (_paymentStatus == PaymentStatus.completed) {
                    // Switching to completed: set payment date to today, clear due date
                    _selectedPaymentDate = DateTime.now();
                    _selectedDueDate = null;
                  } else {
                    // Switching to planned: clear payment date
                    _selectedPaymentDate = null;
                  }
                });
              },
              decoration: const InputDecoration(
                labelText: 'Ödeme Durumu',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Payment type dropdown (Nakit / Pos / Iban)
            DropdownButtonFormField<PaymentType>(
              value: _paymentType,
              items: PaymentType.selectableValues.map((PaymentType type) {
                return DropdownMenuItem<PaymentType>(
                  value: type,
                  child: Text(type.label),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _paymentType = newValue!;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Ödeme Türü',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Due Date Picker (Visible only when status is 'Planlandı')
            if (_paymentStatus == PaymentStatus.planned) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _selectedDueDate == null
                      ? 'Planlanan Tarih Seç'
                      : 'Planlanan Tarih: ${df.format(_selectedDueDate!)}',
                  style: _selectedDueDate != null ? const TextStyle(fontWeight: FontWeight.bold) : null,
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  DateTime? pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedDueDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2030),
                  );
                  if (pickedDate != null) {
                    setState(() {
                      _selectedDueDate = pickedDate;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
            ],

            // Payment Date Picker (Visible only when status is 'Tamamlandı')
            if (_paymentStatus == PaymentStatus.completed) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _selectedPaymentDate == null
                      ? 'Ödeme Tarihi Seç'
                      : 'Ödeme Tarihi: ${df.format(_selectedPaymentDate!)}${DateUtils.isSameDay(_selectedPaymentDate!, DateTime.now()) ? ' (Bugün)' : ''}',
                  style: _selectedPaymentDate != null ? const TextStyle(fontWeight: FontWeight.bold) : null,
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  DateTime? pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedPaymentDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  // Keep the previously selected date if the user cancels.
                  if (pickedDate != null) {
                    setState(() {
                      _selectedPaymentDate = pickedDate;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _pickDekontImage(),
                child: const Text('Dekont Yükle (Opsiyonel)'),
              ),
              const SizedBox(height: 16),
              _dekontImage != null
                  ? Image.file(
                      _dekontImage!,
                      height: 100,
                    )
                  : const Text('Dekont Seçilmedi'),
            ],
          ],
        ),
      ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () => _addPayment(context),
              child: const Text('Ödeme Ekle'),
            ),
          ],
        ),
        if (isLoading) const LoadingOverlay(message: 'Ödeme ekleniyor...'),
      ],
    );
  }

  Future<void> _pickDekontImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    setState(() {
      if (pickedFile != null) {
        _dekontImage = File(pickedFile.path);
        logger.info('Dekont image selected: ${pickedFile.path}');
      } else {
        logger.err('No dekont image selected.');
      }
    });
  }

  Future<void> _addPayment(BuildContext context) async {
    if (_amountController.text.isEmpty) {
      logger.err('_addPayment: Amount is required.');
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen miktarı giriniz.',
        );
      }
      return;
    }

    if (_paymentStatus == PaymentStatus.completed &&
        _selectedPaymentDate == null) {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen ödeme tarihini seçiniz.',
        );
      }
      return;
    }
    
    if (_paymentStatus == PaymentStatus.planned &&
        _selectedDueDate == null) {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen planlanan tarihi seçiniz.',
        );
      }
      return;
    }
    
    // Subscription is now optional - "paketsiz ödeme" is allowed

    // Show confirmation dialog
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Ödeme Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Aşağıdaki ödemeyi eklemek istediğinizden emin misiniz?'),
              const SizedBox(height: 16),
              Text('Miktar: ${_amountController.text} TL'),
              Text('Bağlı Paket: ${_selectedSubscription?.packageName ?? "Yok"}'),
              Text('Durum: ${_paymentStatus.label}'),
              Text('Ödeme Türü: ${_paymentType.label}'),
              if (_selectedDueDate != null)
                Text(
                  'Planlanan Tarih: ${df.format(_selectedDueDate!)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (_selectedPaymentDate != null)
                Text(
                  'Ödeme Tarihi: ${df.format(_selectedPaymentDate!)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (_dekontImage != null) const Text('Dekont: Yüklendi'),
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

    if (shouldSave != true) return;

    startLoading();

    try {
      final paymentProvider =
          Provider.of<PaymentProvider>(context, listen: false);

      // Add the payment
      final paymentAmount = double.parse(_amountController.text);
      
      await paymentProvider.addPayment(
        userId: widget.userId,
        subscription: _selectedSubscription,
        amount: paymentAmount,
        paymentDate: _selectedPaymentDate,
        status: _paymentStatus,
        paymentType: _paymentType,
        dekontImage: _dekontImage,
        dueDate: _selectedDueDate,
      );

      // Update subscription's amountPaid if a subscription is selected and payment is completed
      if (_selectedSubscription != null && _paymentStatus == PaymentStatus.completed) {
        final subscriptionId = _selectedSubscription!.subscriptionId;

        // The delta is applied against the stored total, so a concurrently
        // recorded payment is not overwritten by this (possibly stale) model.
        final subProvider = Provider.of<SubProvider>(context, listen: false);
        await subProvider.adjustAmountPaid(
          userId: widget.userId,
          subscriptionId: subscriptionId,
          delta: paymentAmount,
        );

        // Keep the local model roughly in step for the rest of this dialog.
        _selectedSubscription!.amountPaid += paymentAmount;

        logger.info('Added $paymentAmount to subscription $subscriptionId amountPaid');
      }

      widget.onPaymentAdded();
      if (mounted) {
        Navigator.of(context).pop();
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: 'Ödeme başarıyla eklendi.\n\n'
              'Miktar: ${_amountController.text} TL\n'
              'Bağlı Paket: ${_selectedSubscription?.packageName ?? "Yok"}\n'
              'Durum: ${_paymentStatus.label}\n'
              'Ödeme Türü: ${_paymentType.label}\n'
              '${_selectedDueDate != null ? 'Planlanan Tarih: ${df.format(_selectedDueDate!)}\n' : ''}'
              '${_selectedPaymentDate != null ? 'Ödeme Tarihi: ${df.format(_selectedPaymentDate!)}\n' : ''}',
        );
      }
    } catch (e) {
      logger.err('Error adding payment: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Ödeme eklenirken bir hata oluştu: $e',
        );
      }
    } finally {
      stopLoading();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
}
