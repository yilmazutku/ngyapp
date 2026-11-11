import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/appointment_model.dart';
import '../models/subs_model.dart';
import '../providers/sub_provider.dart';
import '../utils/dialog_utils.dart';
import '../utils/postponement_notices.dart';
import '../widgets/inline_note.dart';

Future<bool?> showRescheduleAppointmentDialog(
  BuildContext context, {
  required AppointmentModel appointment,
  required DateTime newStart,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => RescheduleAppointmentDialog(
      appointment: appointment,
      newStart: newStart,
    ),
  );
}

class RescheduleAppointmentDialog extends StatefulWidget {
  const RescheduleAppointmentDialog({
    super.key,
    required this.appointment,
    required this.newStart,
  });

  final AppointmentModel appointment;
  final DateTime newStart;

  @override
  State<RescheduleAppointmentDialog> createState() =>
      _RescheduleAppointmentDialogState();
}

class _RescheduleAppointmentDialogState
    extends State<RescheduleAppointmentDialog> {
  static const String _title = 'Randevuyu Taşı';
  static const String _unknownCustomer = 'Bilinmiyor';
  static const String _currentLabel = 'MEVCUT';
  static const String _newLabel = 'YENİ';
  static const String _confirmQuestion =
      'Randevu yeni tarih ve saate taşınsın mı?';
  static const String _rightQuestion =
      'Danışanın erteleme hakkından düşülsün mü?';
  static const String _deductOption = 'Evet, erteleme hakkından düş';
  static const String _moveOnlyOption =
      'Hayır, yalnızca tarihi ve saati değiştir';
  static const String _remainingLabel = 'Kalan erteleme hakkı';
  static const String _remainingUnknown = 'Kalan erteleme hakkı okunamadı.';
  static const String _noPackageNote =
      'Randevu bir pakete bağlı değil; düşülecek erteleme hakkı yok.';
  static const String _alreadyDeductedNote =
      'Bu randevu için danışanın erteleme hakkı daha önce düşüldü; yeniden '
      'düşülmez. Yalnızca ertelendiği tarih güncellenir.';
  static const String _confirmText = 'Randevuyu Taşı';
  static const String _cancelText = 'Vazgeç';
  static const double _maxContentWidth = 460;

  static final String _postponedLabel = AppointmentStatus.postponed.label;
  static final String _customerSourceLabel = PostponeSource.user.label;

  static final DateFormat _dayFmt = DateFormat('d MMMM y EEEE', 'tr_TR');
  static final DateFormat _timeFmt = DateFormat('HH:mm');

  late final Future<int?> _remainingRights;
  bool? _deductRight;
  bool _busy = false;

  AppointmentModel get _appointment => widget.appointment;

  bool get _hasPackage => _appointment.subscriptionId?.isNotEmpty ?? false;

  bool get _rightAlreadyDeducted =>
      _appointment.postponedBy == PostponeSource.user;

  bool get _isPostponed => _appointment.status == AppointmentStatus.postponed;

  String get _deductHint => _isPostponed
      ? 'Erteleme kaynağı “$_customerSourceLabel” olur.'
      : 'Randevu “$_postponedLabel” olur; erteleme kaynağı '
          '“$_customerSourceLabel” seçilir.';

  String get _moveOnlyHint => _isPostponed
      ? 'Randevu “$_postponedLabel” olarak kalır; erteleme kaynağı değişmez.'
      : 'Randevu “${_appointment.status.label}” olarak kalır; erteleme '
          'sayılmaz.';

  @override
  void initState() {
    super.initState();
    _remainingRights = _loadRemainingRights();
  }

  Future<int?> _loadRemainingRights() async {
    if (!_hasPackage) return null;
    try {
      final List<SubscriptionModel> subscriptions =
          await Provider.of<SubProvider>(context, listen: false)
              .fetchSubscriptions(
        userId: _appointment.userId,
        showAllSubscriptions: true,
      );
      for (final SubscriptionModel subscription in subscriptions) {
        if (subscription.subscriptionId == _appointment.subscriptionId) {
          return subscription.remainingPostponements;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final bool deduct = !_rightAlreadyDeducted && _deductRight == true;
    setState(() => _busy = true);
    final bool proceed = !deduct || await _confirmRightsLeft();
    if (!mounted) return;
    if (!proceed) {
      setState(() => _busy = false);
      return;
    }
    DialogUtils.closeOwnRoute(context, deduct);
  }

  Future<bool> _confirmRightsLeft() async {
    final int? remaining = await _remainingRights;
    if (!mounted) return false;
    if (remaining == null || remaining > 0) return true;
    return PostponementNotices.confirmNoRightsLeft(context);
  }

  String _timeRange(DateTime start) {
    final DateTime end =
        start.add(Duration(minutes: _appointment.durationMinutes));
    return '${_timeFmt.format(start)} – ${_timeFmt.format(end)}';
  }

  Widget _slot(BuildContext context,
      {required String label, required DateTime start, required bool isNew}) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color accent = isNew ? colors.primary : colors.onSurfaceVariant;
    final TextStyle? valueStyle = isNew
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isNew ? colors.primary.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNew ? colors.primary : colors.outlineVariant,
          width: isNew ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(_dayFmt.format(start), style: valueStyle),
              Text(_timeRange(start), style: valueStyle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _remainingRightsLine(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (!_hasPackage) return Text(_noPackageNote, style: style);

    return FutureBuilder<int?>(
      future: _remainingRights,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text('$_remainingLabel: …', style: style);
        }
        final int? remaining = snapshot.data;
        if (remaining == null) return Text(_remainingUnknown, style: style);
        return Text(
          '$_remainingLabel: $remaining',
          style: style?.copyWith(
            fontWeight: FontWeight.bold,
            color: remaining <= 0 ? theme.colorScheme.error : null,
          ),
        );
      },
    );
  }

  Widget _option(BuildContext context,
      {required bool value, required String title, required String hint}) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: RadioListTile<bool>(
        value: value,
        dense: true,
        visualDensity: VisualDensity.compact,
        horizontalTitleGap: 4,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: _deductRight == value ? colors.primary : colors.outline,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        title: Text(
          title,
          style:
              theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(hint, style: theme.textTheme.bodySmall),
      ),
    );
  }

  Widget _rightSection(BuildContext context) {
    if (_rightAlreadyDeducted) {
      return InlineNote(
        icon: Icons.info_outline,
        text: _alreadyDeductedNote,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _rightQuestion,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        _remainingRightsLine(context),
        RadioGroup<bool>(
          groupValue: _deductRight,
          onChanged: (bool? value) {
            if (value == null) return;
            setState(() => _deductRight = value);
          },
          child: Column(
            children: [
              _option(context,
                  value: true, title: _deductOption, hint: _deductHint),
              _option(context,
                  value: false, title: _moveOnlyOption, hint: _moveOnlyHint),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool canConfirm =
        !_busy && (_rightAlreadyDeducted || _deductRight != null);

    return AlertDialog(
      title: const Text(_title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _appointment.user?.fileLabel ?? _unknownCustomer,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                '${_appointment.appointmentType.lbl} • '
                '${_appointment.meetingType.label} • '
                '${_appointment.durationMinutes} dk',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _slot(context,
                  label: _currentLabel,
                  start: _appointment.effectiveDateTime,
                  isNew: false),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Center(
                  child: Icon(Icons.arrow_downward,
                      size: 20, color: colors.primary),
                ),
              ),
              _slot(context,
                  label: _newLabel, start: widget.newStart, isNew: true),
              const SizedBox(height: 12),
              Text(_confirmQuestion, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              _rightSection(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => DialogUtils.closeOwnRoute(context),
          child: const Text(_cancelText),
        ),
        FilledButton(
          onPressed: canConfirm ? _confirm : null,
          child: const Text(_confirmText),
        ),
      ],
    );
  }
}
