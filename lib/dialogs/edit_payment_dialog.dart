// edit_payment_dialog.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../utils/date_input_utils.dart';
import '../utils/dialog_utils.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../widgets/loading_overlay.dart';

class EditPaymentDialog extends StatefulWidget {
  final PaymentModel payment;
  final Function onPaymentUpdated;

  const EditPaymentDialog({
    super.key,
    required this.payment,
    required this.onPaymentUpdated,
  });

  @override
  createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends State<EditPaymentDialog> 
    with LoadingStateMixin {
  final TextEditingController _amountController = TextEditingController();
  DateTime? _selectedPaymentDate;
  DateTime? _selectedDueDate;

  // Default to COMPLETED
  PaymentStatus _paymentStatus = PaymentStatus.completed;
  // Null means "unspecified" (PaymentType.na) so legacy payments show no
  // pre-selected type and the admin can explicitly choose one.
  PaymentType? _paymentType;

  File? _dekontImage;
  final ImagePicker _picker = ImagePicker();
  bool _loadingSubscriptions = true;

  // kept for future use
  final DateFormat df=DateFormat('dd.MM.yyyy', 'tr_TR');
  // Subscription selection
  List<SubscriptionModel> _availableSubscriptions = [];
  String? _selectedSubscriptionId;

  /// Active packages plus the currently-linked one (even if passive) so the
  /// dropdown value stays valid. Passive packages cannot be newly assigned.
  List<SubscriptionModel> get _selectableSubscriptions =>
      _availableSubscriptions
          .where((s) =>
              s.status.isActive || s.subscriptionId == _selectedSubscriptionId)
          .toList();

  @override
  void initState() {
    super.initState();
    // Show the amount as a whole number (e.g. 20000, not 20000.0).
    _amountController.text = widget.payment.amount.toStringAsFixed(0);
    // If payment date is null (payment was planned), default to today for when user switches to completed
    _selectedPaymentDate = widget.payment.paymentDate ?? DateTime.now();
    _selectedDueDate = widget.payment.dueDate;
    _paymentStatus = widget.payment.status;
    _paymentType = widget.payment.paymentType == PaymentType.na
        ? null
        : widget.payment.paymentType;
    _selectedSubscriptionId = widget.payment.subscriptionId;
    _loadSubscriptions();
  }
  
  Future<void> _loadSubscriptions() async {
    try {
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final subscriptions = await subProvider.fetchSubscriptions(
        userId: widget.payment.userId,
        showAllSubscriptions: true,
      );
      if (mounted) {
        setState(() {
          _availableSubscriptions = subscriptions;
          
          // Check if selected subscription still exists, if not reset to null (Paketsiz)
          if (_selectedSubscriptionId != null) {
            final exists = subscriptions.any((s) => s.subscriptionId == _selectedSubscriptionId);
            if (!exists) {
              _selectedSubscriptionId = null;
            }
          }
          
          _loadingSubscriptions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSubscriptions = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AlertDialog(
          title: const Text('Ödemeyi Düzenle'),
          content: SingleChildScrollView(
            child: ListBody(
          children: [
            // Amount Field (with numeric guard)
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              // Whole numbers only — no decimal point / comma.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Miktar (TL)'),
            ),
            const SizedBox(height: 16),

            // Subscription Selection Dropdown
            if (_loadingSubscriptions)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<String?>(
                value: _selectedSubscriptionId,
                decoration: const InputDecoration(
                  labelText: 'Bağlı Paket',
                  hintText: 'Paket seçin (opsiyonel)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Paketsiz ödeme'),
                  ),
                  ..._selectableSubscriptions.map((sub) {
                    return DropdownMenuItem<String?>(
                      value: sub.subscriptionId,
                      child: Text(
                        '${sub.packageName} (${df.format(sub.startDate)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (newValue) {
                  setState(() {
                    _selectedSubscriptionId = newValue;
                  });
                },
              ),
            const SizedBox(height: 16),

            // Payment Status Dropdown (no clearing on toggle)
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
                  // DO NOT clear the other date anymore.
                  // We keep both in memory so the picker reopens with the last chosen date.
                });
              },
              decoration: const InputDecoration(labelText: 'Ödeme Durumu'),
            ),
            const SizedBox(height: 16),

            // Payment type dropdown (Nakit / Pos / Iban)
            DropdownButtonFormField<PaymentType>(
              value: _paymentType,
              hint: const Text('Belirtilmemiş'),
              items: PaymentType.selectableValues.map((PaymentType type) {
                return DropdownMenuItem<PaymentType>(
                  value: type,
                  child: Text(type.label),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _paymentType = newValue;
                });
              },
              decoration: const InputDecoration(labelText: 'Ödeme Türü'),
            ),
            const SizedBox(height: 16),

            // "Planlanan tarihi seç" ONLY when Planned
            if (_paymentStatus == PaymentStatus.planned) ...[
              ListTile(
                title: Text(
                  _selectedDueDate == null
                      ? 'Planlanan tarihi seç'
                      : 'Planlanan tarih: ${df.format(_selectedDueDate!)}',
                  style: _selectedDueDate != null ? const TextStyle(fontWeight: FontWeight.bold) : null,
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final now = DateTime.now();
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedDueDate ?? now, // <- preserves previous
                    firstDate: kPaymentDateFirst,
                    lastDate: kPaymentDateLast,
                  );
                  // Keep the previously selected date if the user cancels.
                  if (pickedDate != null) {
                    setState(() {
                      _selectedDueDate = pickedDate;
                      // DO NOT clear _selectedPaymentDate
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
            ],

            // "Ödeme tarihi seç" ONLY when Completed
            if (_paymentStatus == PaymentStatus.completed) ...[
              ListTile(
                title: Text(
                  _selectedPaymentDate == null
                      ? 'Ödeme tarihi seç'
                      : 'Ödeme Tarihi: ${df.format(_selectedPaymentDate!)}${DateUtils.isSameDay(_selectedPaymentDate!, DateTime.now()) ? ' (Bugün)' : ''}',
                  style: _selectedPaymentDate != null ? const TextStyle(fontWeight: FontWeight.bold) : null,
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedPaymentDate ?? DateTime.now(), // <- preserves previous
                    firstDate: kPaymentDateFirst,
                    lastDate: kPaymentDateLast,
                  );
                  // Keep the previously selected date if the user cancels.
                  if (pickedDate != null) {
                    setState(() {
                      _selectedPaymentDate = pickedDate;
                      // DO NOT clear _selectedDueDate
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Dekont only when completed
              ElevatedButton(
                onPressed: () => _pickDekontImage(),
                child: const Text('Dekont Görseli Yükle (Opsiyonel)'),
              ),
              const SizedBox(height: 16),
              _dekontImage != null
                  ? Image.file(_dekontImage!, height: 100)
                  : widget.payment.dekontUrl != null
                  ? Image.network(widget.payment.dekontUrl!, height: 100)
                  : const Text('Dekont Görseli Seçilmedi'),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: isLoading ? null : _deletePayment,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Ödemeyi Sil'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () => _updatePayment(),
              child: const Text('Ödemeyi Güncelle'),
            ),
          ],
        ),
        if (isLoading) const LoadingOverlay(message: 'Ödeme güncelleniyor...'),
      ],
    );
  }

  /// Deletes the payment for good, after an explicit confirmation.
  ///
  /// PaymentProvider takes the amount back off the linked package when the
  /// deleted payment was a completed one (see deletePayment).
  Future<void> _deletePayment() async {
    final formattedAmount =
        NumberFormat('#,##0', 'tr_TR').format(widget.payment.amount);
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Ödeme Sil',
      message: '$formattedAmount ₺ tutarındaki ${widget.payment.status.label} '
          'ödeme kalıcı olarak silinecek. Bu işlem geri alınamaz.\n\n'
          'Silmek istediğinizden emin misiniz?',
      confirmText: 'Evet, Sil',
      cancelText: 'Vazgeç',
    );
    if (!confirmed) return;
    if (!mounted) return;

    startLoading();
    try {
      final paymentProvider =
          Provider.of<PaymentProvider>(context, listen: false);
      await paymentProvider.deletePayment(
        widget.payment.paymentId,
        widget.payment.userId,
      );

      if (!mounted) return;
      widget.onPaymentUpdated();
      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Ödeme silindi.',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Ödeme silinirken bir hata oluştu: $e',
      );
    } finally {
      if (mounted) stopLoading();
    }
  }

  /// TR/EN-friendly numeric parser.
  double? _parseAmountOrNull(String text) {
    String s = text.trim().replaceAll(' ', '');
    if (s.isEmpty) return null;

    if (s.contains('.') && s.contains(',')) {
      s = s.replaceAll('.', '');
      s = s.replaceAll(',', '.');
    } else if (s.contains(',')) {
      s = s.replaceAll(',', '.');
    }
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;

    try {
      final v = double.parse(s);
      if (v.isNaN || v.isInfinite) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDekontImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    setState(() {
      if (pickedFile != null) {
        _dekontImage = File(pickedFile.path);
      }
    });
  }

  Future<void> _updatePayment() async {
    // Amount validation
    final rawAmount = _amountController.text;
    if (rawAmount.trim().isEmpty) {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Lütfen miktarı giriniz.',
        );
      }
      return;
    }
    final parsedAmount = _parseAmountOrNull(rawAmount);
    if (parsedAmount == null) {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Miktar geçersiz. Lütfen sayısal bir değer giriniz.\nÖrnek: 1200,50',
        );
      }
      return;
    }

    // Status-specific date requirements
    if (_paymentStatus == PaymentStatus.completed) {
      if (_selectedPaymentDate == null) {
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Lütfen ödeme tarihini seçiniz.',
          );
        }
        return;
      }
    } else if (_paymentStatus == PaymentStatus.planned) {
      if (_selectedDueDate == null) {
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Lütfen planlanan tarihi seçiniz.',
          );
        }
        return;
      }
    } else {
      if (_selectedDueDate == null && _selectedPaymentDate == null) {
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Lütfen bir tarih seçiniz.',
          );
        }
        return;
      }
    }

    // Original values
    final oldPayment = widget.payment;
    final oldAmount = oldPayment.amount;
    final oldStatus = oldPayment.status;
    final newAmount = parsedAmount;

    startLoading();

    try {
      String? dekontUrl = widget.payment.dekontUrl;
      if (_dekontImage != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('payments')
            .child('${widget.payment.paymentId}_${DateTime.now().millisecondsSinceEpoch}');
        await storageRef.putFile(_dekontImage!);
        dekontUrl = await storageRef.getDownloadURL();
      }

      final amountDifference = newAmount - oldAmount;

      final String? oldSubscriptionId = widget.payment.subscriptionId;
      final String? newSubscriptionId = _selectedSubscriptionId;
      final bool subscriptionChanged = oldSubscriptionId != newSubscriptionId;
      final statusChanged = oldStatus != _paymentStatus;

      final updatedPayment = PaymentModel(
        paymentId: widget.payment.paymentId,
        userId: widget.payment.userId,
        subscriptionId: _selectedSubscriptionId,
        amount: newAmount,
        status: _paymentStatus,
        paymentType: _paymentType ?? PaymentType.na,
        // We now keep both dates as chosen; validations already enforce the required one.
        paymentDate: _selectedPaymentDate,
        dueDate: _selectedDueDate,
        dekontUrl: dekontUrl,
        createDate: widget.payment.createDate,
        createUser: widget.payment.createUser,
        updateDate: DateTime.now(),
        updateUser: 'admin',
        notes: widget.payment.notes,
        notificationTimes: widget.payment.notificationTimes,
      );

      // Re-checked after the await: the widget may be gone by now.
      if (!mounted) return;
      final paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
      final subProvider = paymentProvider.subProvider;
      await paymentProvider.updatePayment(updatedPayment);

      // Handle subscription amount adjustments
      if (subscriptionChanged || statusChanged || (oldStatus == PaymentStatus.completed && amountDifference != 0)) {
        if (subscriptionChanged) {
          // Subscription changed: remove from old, add to new
          
          // Step 1: Remove amount from old subscription if it was completed
          if (oldSubscriptionId != null && oldStatus == PaymentStatus.completed) {
            await subProvider.adjustAmountPaid(
              userId: widget.payment.userId,
              subscriptionId: oldSubscriptionId,
              delta: -oldAmount,
            );
          }
          
          // Step 2: Add amount to new subscription if it is completed
          if (newSubscriptionId != null && _paymentStatus == PaymentStatus.completed) {
            await subProvider.adjustAmountPaid(
              userId: widget.payment.userId,
              subscriptionId: newSubscriptionId,
              delta: newAmount,
            );
          }
        } else if (newSubscriptionId != null) {
          // Same subscription, but amount or status changed

          double adjustmentAmount = 0;
          if (statusChanged) {
            if (_paymentStatus == PaymentStatus.completed && oldStatus != PaymentStatus.completed) {
              adjustmentAmount = newAmount;
            } else if (_paymentStatus != PaymentStatus.completed && oldStatus == PaymentStatus.completed) {
              adjustmentAmount = -oldAmount;
            }
          } else if (_paymentStatus == PaymentStatus.completed && amountDifference != 0) {
            adjustmentAmount = amountDifference;
          }

          await subProvider.adjustAmountPaid(
            userId: widget.payment.userId,
            subscriptionId: newSubscriptionId,
            delta: adjustmentAmount,
          );
        }
      }

      // The subscription's amountPaid may have changed in the adjustment block
      // above. updatePayment() already notified SubProvider, but that fired
      // BEFORE these writes, so notify again now to guarantee the subscriptions
      // tab refetches and shows the updated amount.
      subProvider.markChanged();

      widget.onPaymentUpdated();
      if (mounted) {
        await DialogUtils.popThenInfo(
          context,
          title: 'Başarılı',
          message: 'İşlem Başarılı.',
        );
      }
    } catch (e) {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Ödeme güncellenirken bir hata oluştu: $e',
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
