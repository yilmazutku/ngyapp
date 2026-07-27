// pages/bulk_add_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/appointment_model.dart';
import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/subs_model.dart';
import '../providers/appointment_manager.dart';
import '../providers/payment_provider.dart';
import '../providers/sub_provider.dart';
import '../utils/date_input_utils.dart';
import '../utils/dialog_utils.dart';
import '../widgets/loading_overlay.dart';

/// Admin page for adding multiple appointments and payments linked to a single
/// subscription at once. Every created record is linked to [subscription] (its
/// id and owner), so they show up under the package and are cascade-deleted
/// with it. Appointments use fixed defaults (Haftalık Görüşme, 30 dk, Yapıldı,
/// 00:00) and payments are assumed to be cash (Nakit / Tamamlandı); the
/// completed payments are also added to the subscription's paid total.
class BulkAddPage extends StatefulWidget {
  final SubscriptionModel subscription;

  const BulkAddPage({super.key, required this.subscription});

  @override
  State<BulkAddPage> createState() => _BulkAddPageState();
}

class _BulkAddPageState extends State<BulkAddPage> with LoadingStateMixin {
  /// Note stamped on every record created through this bulk page.
  static const String _bulkNote = 'Toplu ekleme ile eklendi';

  final Logger logger = Logger.forClass(BulkAddPage);

  final List<_ApptEntry> _apptEntries = [];
  final List<_PaymentEntry> _paymentEntries = [];

  /// Package the created records link to. Defaults to the package whose card
  /// opened this page; can be set to `null` (the "Paketsiz" item) to add
  /// records without a package — mirrors the nullable subscription convention
  /// used by the add/edit payment dialogs.
  SubscriptionModel? _selectedSubscription;

  @override
  void initState() {
    super.initState();
    _apptEntries.add(_ApptEntry());
    _paymentEntries.add(_PaymentEntry());
    // Default the app-bar dropdown to the package whose card opened this page.
    _selectedSubscription = widget.subscription;
  }

  @override
  void dispose() {
    for (final e in _apptEntries) {
      e.dispose();
    }
    for (final e in _paymentEntries) {
      e.dispose();
    }
    super.dispose();
  }

  /// Human-readable target for confirmation messages: the selected package
  /// name, or "paketsiz" when no package is linked.
  String get _targetLabel => _selectedSubscription != null
      ? "'${_selectedSubscription!.packageName}' paketine"
      : 'paketsiz olarak';

  // ---------------------- Appointment actions ----------------------

  Future<void> _submitAppointments() async {
    if (_apptEntries.isEmpty) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Lütfen en az bir randevu ekleyin.',
      );
      return;
    }

    final List<DateTime> parsedDates = [];
    for (int i = 0; i < _apptEntries.length; i++) {
      final date = parseDayMonthYear(_apptEntries[i].dateController.text);
      if (date == null) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: '${i + 1}. randevu için geçerli bir tarih giriniz '
              '(gg.aa.yyyy).',
        );
        return;
      }
      parsedDates.add(date);
    }

    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Toplu Randevu Ekle',
      message: '${_apptEntries.length} randevu $_targetLabel eklenecek. '
          'Devam edilsin mi?',
    );
    if (!confirmed) return;

    startLoading(timeout: const Duration(minutes: 2));
    int added = 0;
    try {
      final manager = Provider.of<AppointmentManager>(context, listen: false);
      final baseId = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < _apptEntries.length; i++) {
        final entry = _apptEntries[i];
        final date = parsedDates[i];
        final appointment = AppointmentModel(
          appointmentId: '${baseId}_$i',
          userId: widget.subscription.userId,
          subscriptionId: _selectedSubscription?.subscriptionId,
          meetingType: entry.meetingType,
          appointmentType: AppointmentType.haftalik,
          appointmentDateTime:
              DateTime(date.year, date.month, date.day, 0, 0),
          status: AppointmentStatus.completed,
          notes: _bulkNote,
          createDate: DateTime.now(),
          createUser: 'admin',
          durationMinutes: 30,
        );
        await manager.addAppointment(appointment);
        added++;
      }

      if (mounted) {
        stopLoading();
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: '$added randevu başarıyla eklendi.',
        );
        setState(() {
          for (final e in _apptEntries) {
            e.dispose();
          }
          _apptEntries
            ..clear()
            ..add(_ApptEntry());
        });
      }
    } catch (e) {
      logger.err('Error bulk adding appointments: {}', [e]);
      if (mounted) {
        stopLoading();
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Randevular eklenirken bir hata oluştu '
              '($added randevu eklendi): $e',
        );
      }
    } finally {
      if (mounted) stopLoading();
    }
  }

  // ---------------------- Payment actions ----------------------

  Future<void> _submitPayments() async {
    if (_paymentEntries.isEmpty) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Lütfen en az bir ödeme ekleyin.',
      );
      return;
    }

    final List<DateTime> parsedDates = [];
    final List<double> parsedAmounts = [];
    for (int i = 0; i < _paymentEntries.length; i++) {
      final entry = _paymentEntries[i];
      final date = parseDayMonthYear(entry.dateController.text);
      if (date == null) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: '${i + 1}. ödeme için geçerli bir tarih giriniz '
              '(gg.aa.yyyy).',
        );
        return;
      }
      final amount =
          double.tryParse(entry.amountController.text.trim().replaceAll(',', '.'));
      if (amount == null || amount <= 0) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: '${i + 1}. ödeme için geçerli bir miktar giriniz.',
        );
        return;
      }
      parsedDates.add(date);
      parsedAmounts.add(amount);
    }

    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Toplu Ödeme Ekle',
      message: '${_paymentEntries.length} ödeme $_targetLabel eklenecek. '
          'Devam edilsin mi?',
    );
    if (!confirmed) return;

    startLoading(timeout: const Duration(minutes: 2));
    int added = 0;
    try {
      final paymentProvider =
          Provider.of<PaymentProvider>(context, listen: false);
      final subProvider = Provider.of<SubProvider>(context, listen: false);
      final SubscriptionModel? linkedSub = _selectedSubscription;
      double addedAmount = 0;
      for (int i = 0; i < _paymentEntries.length; i++) {
        await paymentProvider.addPayment(
          userId: widget.subscription.userId,
          subscription: linkedSub,
          amount: parsedAmounts[i],
          paymentDate: parsedDates[i],
          status: PaymentStatus.completed,
          paymentType: PaymentType.nakit,
          notes: _bulkNote,
        );
        addedAmount += parsedAmounts[i];
        added++;
      }

      // Reflect the completed payments in the subscription's paid total so the
      // package summary stays accurate (mirrors the single add-payment flow).
      // Skipped for "Paketsiz" payments, which are not tied to any package.
      if (linkedSub != null && addedAmount > 0) {
        final newAmountPaid = linkedSub.amountPaid + addedAmount;
        await subProvider.updateAmountPaid(
          userId: widget.subscription.userId,
          subscriptionId: linkedSub.subscriptionId,
          amountPaid: newAmountPaid,
        );
        linkedSub.amountPaid = newAmountPaid;
      }

      if (mounted) {
        stopLoading();
        await DialogUtils.openInfo(
          context,
          title: 'Başarılı',
          message: '$added ödeme başarıyla eklendi.',
        );
        setState(() {
          for (final e in _paymentEntries) {
            e.dispose();
          }
          _paymentEntries
            ..clear()
            ..add(_PaymentEntry());
        });
      }
    } catch (e) {
      logger.err('Error bulk adding payments: {}', [e]);
      if (mounted) {
        stopLoading();
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Ödemeler eklenirken bir hata oluştu '
              '($added ödeme eklendi): $e',
        );
      }
    } finally {
      if (mounted) stopLoading();
    }
  }

  // ---------------------- Build ----------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Toplu Ekle'),
            backgroundColor: Colors.blue.shade800,
            foregroundColor: Colors.white,
            bottom: _buildSubscriptionBar(),
          ),
          // Page is split in two: appointments on top, payments below.
          body: Column(
            children: [
              Expanded(child: _buildAppointmentSection()),
              const Divider(height: 1, thickness: 1),
              Expanded(child: _buildPaymentSection()),
            ],
          ),
        ),
        if (isLoading) const LoadingOverlay(message: 'Kaydediliyor...'),
      ],
    );
  }

  /// App-bar row letting the admin pick where the created records go: the
  /// card's own package (default) or "Paketsiz" (null) to add them without a
  /// package.
  PreferredSizeWidget _buildSubscriptionBar() {
    const double barHeight = 60;
    return PreferredSize(
      preferredSize: const Size.fromHeight(barHeight),
      child: SizedBox(
        height: barHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(
            children: [
              const Icon(Icons.card_membership, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Bağlı Paket:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<SubscriptionModel?>(
                      isExpanded: true,
                      value: _selectedSubscription,
                      items: [
                        DropdownMenuItem<SubscriptionModel?>(
                          value: widget.subscription,
                          child: Text(
                            widget.subscription.packageType != null
                                ? '${widget.subscription.packageName} (${widget.subscription.packageType!.label})'
                                : widget.subscription.packageName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const DropdownMenuItem<SubscriptionModel?>(
                          value: null,
                          child: Text('Paketsiz'),
                        ),
                      ],
                      onChanged: isLoading
                          ? null
                          : (value) =>
                              setState(() => _selectedSubscription = value),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppointmentSection() {
    return Column(
      children: [
        _SectionHeader(
          icon: Icons.calendar_today,
          title: 'Randevular',
          info: '',
          color: Colors.blue,
          addLabel: 'Randevu Ekle',
          onAdd: isLoading
              ? null
              : () => setState(() => _apptEntries.add(_ApptEntry())),
        ),
        Expanded(
          child: _EntryGrid(
            itemCount: _apptEntries.length,
            itemBuilder: _buildAppointmentCard,
          ),
        ),
        _buildSubmitBar(
          label: 'Randevuları Kaydet',
          onPressed: _submitAppointments,
        ),
      ],
    );
  }

  Widget _buildAppointmentCard(int index) {
    final entry = _apptEntries[index];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Randevu ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_apptEntries.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Satırı sil',
                    onPressed: () => setState(() {
                      _apptEntries.removeAt(index).dispose();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _DateField(
              controller: entry.dateController,
              label: 'Tarih (gg.aa.yyyy)',
            ),
            const SizedBox(height: 12),
            const Text('Görüşme Türü'),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildMeetingTypeButton(entry, MeetingType.f2f),
                const SizedBox(width: 8),
                _buildMeetingTypeButton(entry, MeetingType.online),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingTypeButton(_ApptEntry entry, MeetingType type) {
    final bool selected = entry.meetingType == type;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() => entry.meetingType = type),
        style: OutlinedButton.styleFrom(
          backgroundColor:
              selected ? Colors.green.withValues(alpha: 0.08) : null,
          side: BorderSide(
            color: selected ? Colors.green : Colors.grey.shade300,
          ),
        ),
        child: Text(
          type.label,
          style: TextStyle(
            color: selected ? Colors.green.shade700 : Colors.grey,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Column(
      children: [
        _SectionHeader(
          icon: Icons.payment,
          title: 'Ödemeler',
          info: '',
          color: Colors.green,
          addLabel: 'Ödeme Ekle',
          onAdd: isLoading
              ? null
              : () => setState(() => _paymentEntries.add(_PaymentEntry())),
        ),
        Expanded(
          child: _EntryGrid(
            itemCount: _paymentEntries.length,
            itemBuilder: _buildPaymentCard,
          ),
        ),
        _buildSubmitBar(
          label: 'Ödemeleri Kaydet',
          onPressed: _submitPayments,
        ),
      ],
    );
  }

  Widget _buildPaymentCard(int index) {
    final entry = _paymentEntries[index];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Ödeme ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_paymentEntries.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Satırı sil',
                    onPressed: () => setState(() {
                      _paymentEntries.removeAt(index).dispose();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _DateField(
              controller: entry.dateController,
              label: 'Tarih (gg.aa.yyyy)',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: entry.amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Miktar (TL)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitBar({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Center(
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onPressed,
            icon: const Icon(Icons.save),
            label: Text(label),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact section header: title + fixed-field info + an "add row" action.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String info;
  final MaterialColor color;
  final String addLabel;
  final VoidCallback? onAdd;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.info,
    required this.color,
    required this.addLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.shade50,
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              addLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: TextButton.styleFrom(foregroundColor: color.shade700),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 20, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color.shade900,
                  ),
                ),
                Text(
                  info,
                  style: TextStyle(fontSize: 11, color: color.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollable, responsive grid that lays entry cards out in two columns
/// (falling back to a single column on narrow screens) so they no longer
/// stretch across the full width.
class _EntryGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(int index) itemBuilder;

  const _EntryGrid({
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double spacing = 12;
          final int columns = constraints.maxWidth < 520 ? 1 : 2;
          final double itemWidth =
              (constraints.maxWidth - (columns - 1) * spacing) / columns;
          return SingleChildScrollView(
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (int i = 0; i < itemCount; i++)
                  SizedBox(width: itemWidth, child: itemBuilder(i)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Date text field pre-filled with the `.` separators; the user only types
/// the digits, which fill the day/month/year slots around the fixed dots.
class _DateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _DateField({
    required this.controller,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [MaskedDateInputFormatter()],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.calendar_today),
      ),
    );
  }
}

class _ApptEntry {
  final TextEditingController dateController =
      TextEditingController(text: MaskedDateInputFormatter.emptyMask);
  MeetingType meetingType = MeetingType.f2f;

  void dispose() {
    dateController.dispose();
  }
}

class _PaymentEntry {
  final TextEditingController dateController =
      TextEditingController(text: MaskedDateInputFormatter.emptyMask);
  final TextEditingController amountController = TextEditingController();

  void dispose() {
    dateController.dispose();
    amountController.dispose();
  }
}
