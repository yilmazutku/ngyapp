import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/payment_model.dart';
import '../models/user_model.dart';
import '../providers/payment_provider.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';
import '../widgets/status_note.dart';
import 'customer_sum.dart';

class PaymentTypePaymentsPage extends StatefulWidget {
  const PaymentTypePaymentsPage({
    super.key,
    required this.title,
    required this.periodText,
    required this.icon,
    required this.payments,
    required this.userOf,
    required this.reloadPayments,
  });

  final String title;

  final String periodText;

  final IconData icon;

  final List<PaymentModel> payments;

  final UserModel? Function(String userId) userOf;

  final Future<List<PaymentModel>> Function() reloadPayments;

  @override
  State<PaymentTypePaymentsPage> createState() =>
      _PaymentTypePaymentsPageState();
}

class _PaymentTypePaymentsPageState extends State<PaymentTypePaymentsPage> {
  static const String _unknownUserName = 'Bilinmiyor';
  static const String _tapHint =
      'Danışanın Ödeme sekmesini açmak için satıra dokunun.';
  static const String _emptyText = 'Bu dönemde bu tipte ödeme kalmadı.';

  static const double _maxContentWidth = 720;

  final NumberFormat _currencyFormat = NumberFormat('#,##0 ₺', 'tr_TR');
  final ScrollController _listController = ScrollController();

  late List<PaymentModel> _payments;
  bool _isReloading = false;

  bool _paymentsChanged = false;

  late final PaymentProvider _paymentProvider;

  @override
  void initState() {
    super.initState();
    _payments = widget.payments;
    _paymentProvider = Provider.of<PaymentProvider>(context, listen: false);
    _paymentProvider.addListener(_onPaymentsChanged);
  }

  @override
  void dispose() {
    _paymentProvider.removeListener(_onPaymentsChanged);
    _listController.dispose();
    super.dispose();
  }

  void _onPaymentsChanged() {
    _paymentsChanged = true;
  }

  double get _total => _payments.fold<double>(0, (sum, p) => sum + p.amount);

  String _userName(String userId) =>
      widget.userOf(userId)?.fullName ?? _unknownUserName;

  Future<void> _openPaymentsTab(PaymentModel payment) async {
    final UserModel? user = widget.userOf(payment.userId);
    if (user == null) {
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Bu ödemenin danışan kaydı bulunamadı.',
      );
      return;
    }

    final Object? result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerSummaryPage(user: user, openPaymentsTab: true),
      ),
    );
    if (!mounted) return;
    final bool userDeleted = result is String && result.isNotEmpty;
    if (_paymentsChanged || userDeleted) {
      await _reload();
    }
  }

  Future<void> _reload() async {
    _paymentsChanged = false;
    setState(() => _isReloading = true);
    try {
      final List<PaymentModel> payments = await widget.reloadPayments();
      if (!mounted) return;
      setState(() => _payments = payments);
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Ödemeler yenilenirken bir hata oluştu: $e',
      );
    } finally {
      if (mounted) setState(() => _isReloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWithBack(title: widget.title, showHomeButton: true),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isReloading) const LinearProgressIndicator(),
              _buildSummaryCard(),
              Expanded(
                child: _payments.isEmpty
                    ? const StatusNote(icon: Icons.inbox, text: _emptyText)
                    : _buildList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: Colors.teal, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.periodText,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.receipt_long, size: 18),
                  label: Text('${_payments.length} ödeme'),
                ),
                Chip(
                  avatar: const Icon(Icons.paid, size: 18, color: Colors.green),
                  label: Text(
                    'Toplam: ${_currencyFormat.format(_total)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (_payments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _tapHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return Scrollbar(
      controller: _listController,
      child: ListView.builder(
        controller: _listController,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: _payments.length,
        itemBuilder: (context, index) => _buildPaymentTile(_payments[index]),
      ),
    );
  }

  Widget _buildPaymentTile(PaymentModel payment) {
    final UserModel? user = widget.userOf(payment.userId);
    final DateTime? date = payment.effectiveDate;

    return Card(
      key: ValueKey(payment.paymentId),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: _isReloading ? null : () => _openPaymentsTab(payment),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade50,
          foregroundColor: Colors.blue.shade800,
          child: Text(user?.initials ?? '?'),
        ),
        title: Text(
          _userName(payment.userId),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.blue.shade800,
          ),
        ),
        subtitle: Text(
          date == null
              ? 'Tarih belirtilmemiş'
              : DateFormatter.formatNumericDate(date),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currencyFormat.format(payment.amount),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
