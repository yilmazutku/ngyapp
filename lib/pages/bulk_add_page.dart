// pages/bulk_add_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/appointment_model.dart';
import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/user_model.dart';
import '../providers/appointment_manager.dart';
import '../providers/payment_provider.dart';
import '../utils/date_input_utils.dart';
import '../utils/dialog_utils.dart';
import '../widgets/loading_overlay.dart';

/// Admin page for adding multiple appointments and payments for a single
/// customer at once. Both tabs intentionally skip the linked subscription
/// selection: appointments use fixed defaults (Haftalık Görüşme, 30 dk,
/// Yapıldı, 00:00) and payments are assumed to be cash (Nakit / Tamamlandı).
class BulkAddPage extends StatefulWidget {
  final UserModel user;

  const BulkAddPage({super.key, required this.user});

  @override
  State<BulkAddPage> createState() => _BulkAddPageState();
}

class _BulkAddPageState extends State<BulkAddPage>
    with SingleTickerProviderStateMixin, LoadingStateMixin {
  static const String _bulkButtonLabel = 'Toplu Ödeme/Randevu Ekle';

  final Logger logger = Logger.forClass(BulkAddPage);

  late final TabController _tabController;

  final List<_ApptEntry> _apptEntries = [];
  final List<_PaymentEntry> _paymentEntries = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _apptEntries.add(_ApptEntry());
    _paymentEntries.add(_PaymentEntry());
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final e in _apptEntries) {
      e.dispose();
    }
    for (final e in _paymentEntries) {
      e.dispose();
    }
    super.dispose();
  }

  String get _userName => '${widget.user.name} ${widget.user.surname}'.trim();

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
      message: '$_userName için ${_apptEntries.length} randevu eklenecek. '
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
          userId: widget.user.userId,
          subscriptionId: null,
          meetingType: entry.meetingType,
          appointmentType: AppointmentType.haftalik,
          appointmentDateTime:
              DateTime(date.year, date.month, date.day, 0, 0),
          status: AppointmentStatus.completed,
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
      message: '$_userName için ${_paymentEntries.length} ödeme eklenecek. '
          'Devam edilsin mi?',
    );
    if (!confirmed) return;

    startLoading(timeout: const Duration(minutes: 2));
    int added = 0;
    try {
      final paymentProvider =
          Provider.of<PaymentProvider>(context, listen: false);
      for (int i = 0; i < _paymentEntries.length; i++) {
        await paymentProvider.addPayment(
          userId: widget.user.userId,
          subscription: null,
          amount: parsedAmounts[i],
          paymentDate: parsedDates[i],
          status: PaymentStatus.completed,
          paymentType: PaymentType.nakit,
        );
        added++;
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
            title: Text('Toplu Ekle - $_userName'),
            backgroundColor: Colors.blue.shade800,
            foregroundColor: Colors.white,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(icon: Icon(Icons.calendar_today), text: 'Randevu'),
                Tab(icon: Icon(Icons.payment), text: 'Ödeme'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildAppointmentTab(),
              _buildPaymentTab(),
            ],
          ),
        ),
        if (isLoading) const LoadingOverlay(message: 'Kaydediliyor...'),
      ],
    );
  }

  Widget _buildAppointmentTab() {
    return Column(
      children: [
        const _FixedInfoBanner(
          text: 'Sabit alanlar: Randevu Türü: Haftalık Görüşme · '
              'Görüşme Süresi: 30 dk · Durum: Yapıldı · Saat: 00:00',
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _apptEntries.length,
            itemBuilder: (context, index) =>
                _buildAppointmentCard(index),
          ),
        ),
        _buildAddRowButton(
          label: 'Randevu Satırı Ekle',
          onPressed: () => setState(() => _apptEntries.add(_ApptEntry())),
        ),
        _buildSubmitBar(onPressed: _submitAppointments),
      ],
    );
  }

  Widget _buildAppointmentCard(int index) {
    final entry = _apptEntries[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
              separator: '.',
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

  Widget _buildPaymentTab() {
    return Column(
      children: [
        const _FixedInfoBanner(
          text: 'Sabit alanlar: Ödeme Türü: Nakit · Durum: Tamamlandı',
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _paymentEntries.length,
            itemBuilder: (context, index) => _buildPaymentCard(index),
          ),
        ),
        _buildAddRowButton(
          label: 'Ödeme Satırı Ekle',
          onPressed: () =>
              setState(() => _paymentEntries.add(_PaymentEntry())),
        ),
        _buildSubmitBar(onPressed: _submitPayments),
      ],
    );
  }

  Widget _buildPaymentCard(int index) {
    final entry = _paymentEntries[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
              separator: '.',
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

  Widget _buildAddRowButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: isLoading ? null : onPressed,
          icon: const Icon(Icons.add),
          label: Text(label),
        ),
      ),
    );
  }

  Widget _buildSubmitBar({required VoidCallback onPressed}) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onPressed,
            icon: const Icon(Icons.save),
            label: const Text(_bulkButtonLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small banner that describes the fixed (non-editable) fields of a tab.
class _FixedInfoBanner extends StatelessWidget {
  final String text;

  const _FixedInfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

/// Masked date text field that auto-inserts [separator] as the user types.
class _DateField extends StatelessWidget {
  final TextEditingController controller;
  final String separator;
  final String label;

  const _DateField({
    required this.controller,
    required this.separator,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [DateInputFormatter(separator)],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.calendar_today),
      ),
    );
  }
}

class _ApptEntry {
  final TextEditingController dateController = TextEditingController();
  MeetingType meetingType = MeetingType.f2f;

  void dispose() {
    dateController.dispose();
  }
}

class _PaymentEntry {
  final TextEditingController dateController = TextEditingController();
  final TextEditingController amountController = TextEditingController();

  void dispose() {
    dateController.dispose();
    amountController.dispose();
  }
}
