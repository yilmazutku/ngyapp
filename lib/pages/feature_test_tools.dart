import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../dialogs/customer_picker_dialog.dart';
import '../models/admin_notification.dart';
import '../models/blood_test_scan.dart';
import '../models/feature_test_checklist.dart';
import '../models/feature_test_plan.dart';
import '../models/user_model.dart';
import '../providers/admin_notifications_provider.dart';
import '../providers/appointment_colors_provider.dart';
import '../providers/blood_test_provider.dart';
import '../providers/meal_photo_notifications_provider.dart';
import '../providers/user_provider.dart';
import '../utils/birthdays.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../widgets/birthday_chip.dart';
import '../widgets/blood_test_reminder_preview.dart';
import '../widgets/chat/chat_input_keys.dart';
import '../widgets/customer_chip.dart';
import '../widgets/filter_chip_group.dart';
import '../widgets/status_note.dart';
import 'customer_sum.dart';

final DateFormat _clockFormat = DateFormat('HH:mm:ss', 'tr_TR');
final DateFormat _weekdayFormat = DateFormat('EEEE', 'tr_TR');

String _customerName(UserModel user) =>
    user.fullName.isEmpty ? user.email : user.fullName;

DateTime _today() => DateUtils.dateOnly(DateTime.now());

class FeatureTestToolPanel extends StatelessWidget {
  const FeatureTestToolPanel({
    super.key,
    required this.tool,
    required this.color,
    required this.checklist,
  });

  final FeatureTestTool tool;
  final Color color;
  final FeatureTestChecklist checklist;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.alphaBlend(color.withValues(alpha: 0.04), Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(tool.icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tool.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _body(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (tool) {
      case FeatureTestTool.reminderCalculator:
        return _ReminderCalculator(color: color);
      case FeatureTestTool.notificationSimulator:
        return _NotificationSimulator(checklist: checklist, color: color);
      case FeatureTestTool.notificationStatus:
        return const _NotificationStatus();
      case FeatureTestTool.scanPreview:
        return _ScanPreview(color: color);
      case FeatureTestTool.birthdayPreview:
        return _BirthdayPreview(color: color);
      case FeatureTestTool.enterKeys:
        return _EnterKeyTester(color: color);
    }
  }
}

class _ToolHint extends StatelessWidget {
  const _ToolHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style:
          TextStyle(fontSize: 12.5, height: 1.35, color: Colors.grey.shade700),
    );
  }
}

class _ReminderCalculator extends StatefulWidget {
  const _ReminderCalculator({required this.color});

  final Color color;

  @override
  State<_ReminderCalculator> createState() => _ReminderCalculatorState();
}

class _ReminderCalculatorState extends State<_ReminderCalculator> {
  static const String _dateLabel = 'Tahlil tarihi';
  static const String _quickTitle = 'Hızlı seç';

  DateTime _testDate = _today();

  Map<String, DateTime> _quickDates() {
    final DateTime today = _today();
    return {
      'Bugün': today,
      '3 ay önce': BloodTestReminderSchedule.addMonths(today, -3),
      '4 ay önce': BloodTestReminderSchedule.addMonths(today, -4),
      '31 Ağustos': DateTime(today.year, 8, 31),
      '30 Kasım': DateTime(today.year, 11, 30),
    };
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _testDate,
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: _dateLabel,
    );
    if (picked == null || !mounted) return;
    setState(() => _testDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, DateTime> quickDates = _quickDates();
    String? selected;
    for (final MapEntry<String, DateTime> entry in quickDates.entries) {
      if (DateUtils.isSameDay(entry.value, _testDate)) {
        selected = entry.key;
        break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ToolHint(
          'Bir tahlil tarihi seçin; tahlil yüklerken açılan pencerenin '
          'göstereceği hatırlatma günleri ve saatleri burada hesaplanır.',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              '$_dateLabel:',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(DateFormatter.formatLongDate(_testDate)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilterChipGroup<String>(
          title: _quickTitle,
          options: {for (final String label in quickDates.keys) label: label},
          selectedValue: selected,
          showAllOption: false,
          horizontalScroll: false,
          selectedColor: widget.color.withValues(alpha: 0.16),
          onSelected: (label) {
            final DateTime? date = label == null ? null : quickDates[label];
            if (date == null) return;
            setState(() => _testDate = date);
          },
        ),
        const SizedBox(height: 10),
        BloodTestReminderPreview(testDate: _testDate),
      ],
    );
  }
}

class _NotificationSimulator extends StatefulWidget {
  const _NotificationSimulator({required this.checklist, required this.color});

  final FeatureTestChecklist checklist;
  final Color color;

  @override
  State<_NotificationSimulator> createState() => _NotificationSimulatorState();
}

class _NotificationSimulatorState extends State<_NotificationSimulator> {
  static const String _kindKey = 'simulator.kind';
  static const String _delayKey = 'simulator.delaySeconds';
  static const String _customerIdKey = 'simulator.customerId';
  static const String _customerNameKey = 'simulator.customerName';

  static const Map<AdminTestNotificationKind, String> _kindLabels = {
    AdminTestNotificationKind.plain: 'Deneme',
    AdminTestNotificationKind.bloodTestDayBefore: 'Kan tahlili · 1 gün kala',
    AdminTestNotificationKind.bloodTestDueDay: 'Kan tahlili · 3 ay doldu',
  };

  static const Map<int, String> _delayLabels = {
    0: 'Hemen',
    10: '10 sn',
    30: '30 sn',
    60: '1 dk',
    120: '2 dk',
    300: '5 dk',
    900: '15 dk',
  };

  static const int _defaultDelaySeconds = 60;

  late AdminTestNotificationKind _kind;
  late int _delaySeconds;
  NotificationCustomer? _customer;
  bool _busy = false;
  String? _lastInfo;

  @override
  void initState() {
    super.initState();
    final FeatureTestChecklist checklist = widget.checklist;
    _kind = _kindLabels.keys.firstWhere(
      (kind) => kind.name == checklist.setting(_kindKey),
      orElse: () => AdminTestNotificationKind.plain,
    );
    final int? delay = int.tryParse(checklist.setting(_delayKey) ?? '');
    _delaySeconds =
        _delayLabels.containsKey(delay) ? delay! : _defaultDelaySeconds;
    final String? customerId = checklist.setting(_customerIdKey);
    final String? customerName = checklist.setting(_customerNameKey);
    if (customerId != null && customerName != null) {
      _customer = NotificationCustomer(userId: customerId, name: customerName);
    }
  }

  bool get _needsCustomer => _kind != AdminTestNotificationKind.plain;

  bool get _canCreate => !_busy && (!_needsCustomer || _customer != null);

  Future<void> _pickCustomer() async {
    final UserProvider users =
        Provider.of<UserProvider>(context, listen: false);
    final LoadingDialog loading =
        DialogUtils.openLoading(context, message: 'Danışanlar yükleniyor...');
    try {
      final List<UserModel> customers = await users.fetchAllCustomers();
      loading.close();
      if (!mounted) return;
      final UserModel? picked =
          await showCustomerPickerDialog(context, customers: customers);
      if (picked == null || !mounted) return;
      final NotificationCustomer customer = NotificationCustomer(
        userId: picked.userId,
        name: _customerName(picked),
      );
      setState(() => _customer = customer);
      widget.checklist
        ..setSetting(_customerIdKey, customer.userId)
        ..setSetting(_customerNameKey, customer.name);
    } catch (e) {
      loading.close();
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Danışanlar yüklenemedi: $e',
      );
    }
  }

  Future<void> _create() async {
    final AdminNotificationsProvider notifications =
        Provider.of<AdminNotificationsProvider>(context, listen: false);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NotificationCustomer? customer = _needsCustomer ? _customer : null;
    final AdminTestNotificationKind kind = _kind;
    final String label = _kindLabels[kind]!;
    final DateTime fireAt =
        DateTime.now().add(Duration(seconds: _delaySeconds));
    setState(() => _busy = true);
    try {
      final String? id = await notifications.addTestNotification(
        fireAt: fireAt,
        kind: kind,
        customers: [if (customer != null) customer],
      );
      if (!mounted) return;
      if (id == null) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Oturum bulunamadı; bildirim kurulamadı.',
        );
        return;
      }
      final String info = _delaySeconds == 0
          ? '"$label" bildirimi zile düştü.'
          : '"$label" bildirimi saat ${_clockFormat.format(fireAt)} olunca '
              'düşecek. Uygulamayı açık tutun ya da arka plana alın.';
      setState(() => _lastInfo = info);
      messenger.showSnackBar(SnackBar(content: Text(info)));
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Bildirim kurulamadı: $e',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAll() async {
    final AdminNotificationsProvider notifications =
        Provider.of<AdminNotificationsProvider>(context, listen: false);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final int removed = await notifications.removeTestNotifications();
      if (!mounted) return;
      setState(() => _lastInfo = null);
      messenger.showSnackBar(SnackBar(
        content: Text(removed == 0
            ? 'Silinecek deneme bildirimi yok.'
            : '$removed deneme bildirimi silindi.'),
      ));
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Deneme bildirimleri silinemedi: $e',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color selectedColor = widget.color.withValues(alpha: 0.16);
    final String? lastInfo = _lastInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilterChipGroup<AdminTestNotificationKind>(
          title: 'Tür',
          options: _kindLabels,
          selectedValue: _kind,
          showAllOption: false,
          horizontalScroll: false,
          selectedColor: selectedColor,
          onSelected: (kind) {
            if (kind == null) return;
            setState(() => _kind = kind);
            widget.checklist.setSetting(_kindKey, kind.name);
          },
        ),
        const SizedBox(height: 12),
        FilterChipGroup<int>(
          title: 'Ne zaman düşsün?',
          options: _delayLabels,
          selectedValue: _delaySeconds,
          showAllOption: false,
          horizontalScroll: false,
          selectedColor: selectedColor,
          onSelected: (seconds) {
            if (seconds == null) return;
            setState(() => _delaySeconds = seconds);
            widget.checklist.setSetting(_delayKey, '$seconds');
          },
        ),
        if (_needsCustomer) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Danışan:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickCustomer,
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: Text(_customer?.name ?? 'Danışan seç'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: widget.color),
              onPressed: _canCreate ? _create : null,
              icon: const Icon(Icons.alarm_add_rounded, size: 18),
              label: const Text('Bildirimi kur'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _removeAll,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Deneme bildirimlerini sil'),
            ),
          ],
        ),
        if (_needsCustomer && _customer == null) ...[
          const SizedBox(height: 8),
          const _ToolHint(
              'Kan tahlili hatırlatması için önce bir danışan seçin.'),
        ],
        if (lastInfo != null) ...[
          const SizedBox(height: 8),
          _ToolHint(lastInfo),
        ],
      ],
    );
  }
}

class _NotificationStatus extends StatelessWidget {
  const _NotificationStatus();

  @override
  Widget build(BuildContext context) {
    final AdminNotificationsProvider system =
        Provider.of<AdminNotificationsProvider>(context, listen: false);
    final MealPhotoNotificationsProvider chat =
        Provider.of<MealPhotoNotificationsProvider>(context, listen: false);
    return ListenableBuilder(
      listenable: Listenable.merge([system, chat]),
      builder: (context, _) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _StatTile(
            icon: Icons.notifications_none_rounded,
            label: 'Sistem',
            value: system.isLoaded
                ? '${system.unreadCount} okunmamış'
                : 'Yükleniyor...',
            detail: '${system.notifications.length} bildirim listede',
          ),
          _StatTile(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Sohbet',
            value: chat.isLoaded
                ? '${chat.unreadCount} okunmamış'
                : 'Yükleniyor...',
            detail: 'Bugün ${chat.items.length} öğün fotoğrafı',
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.deepPurple.shade400),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label · $value',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                detail,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScanPreview extends StatefulWidget {
  const _ScanPreview({required this.color});

  final Color color;

  @override
  State<_ScanPreview> createState() => _ScanPreviewState();
}

class _ScanPreviewState extends State<_ScanPreview> {
  static const Map<int, String> _dayOptions = {
    0: 'Bugün',
    1: 'Yarın',
    8: '8 gün sonra',
    15: '15 gün sonra',
  };
  static const int _collapsedChipCount = 12;

  int _dayOffset = 0;
  DateTime? _customDay;
  BloodTestScanPreview? _preview;
  BloodTestScanState? _state;
  String? _lastScanByName;
  bool _stateFailed = false;
  bool _busy = false;
  bool _showAllMissing = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  DateTime _previewTime() {
    final DateTime now = DateTime.now();
    final DateTime day =
        _customDay ?? DateTime(now.year, now.month, now.day + _dayOffset);
    return DateTime(
        day.year, day.month, day.day, now.hour, now.minute, now.second);
  }

  Future<void> _loadState() async {
    final BloodTestProvider bloodTests =
        Provider.of<BloodTestProvider>(context, listen: false);
    final UserProvider users =
        Provider.of<UserProvider>(context, listen: false);
    try {
      final BloodTestScanState state = await bloodTests.fetchScanState();
      String? byName;
      final String? by = state.lastScanBy;
      if (by != null) {
        if (by == FirebaseAuth.instance.currentUser?.uid) {
          byName = 'siz';
        } else {
          final UserModel? user = await users.fetchUserDetails(userId: by);
          byName = user == null ? null : _customerName(user);
        }
      }
      if (!mounted) return;
      setState(() {
        _state = state;
        _lastScanByName = byName;
        _stateFailed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _stateFailed = true);
    }
  }

  Future<void> _pickDay() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customDay ?? _today(),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Tarama günü',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customDay = picked;
      _preview = null;
    });
  }

  Future<void> _runPreview() async {
    final BloodTestProvider bloodTests =
        Provider.of<BloodTestProvider>(context, listen: false);
    final DateTime at = _previewTime();
    setState(() => _busy = true);
    try {
      final BloodTestScanPreview preview = await bloodTests.previewScan(at: at);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _showAllMissing = false;
      });
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Önizleme yapılamadı: $e',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notifyMe(BloodTestScanPreview preview) async {
    final AdminNotificationsProvider notifications =
        Provider.of<AdminNotificationsProvider>(context, listen: false);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await notifications.addTestNotification(
        fireAt: DateTime.now(),
        kind: AdminTestNotificationKind.missingBloodTests,
        customers: preview.missing,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Liste zilin Sistem sekmesine "DENEME" etiketiyle '
            'düştü (${preview.missing.length} danışan).'),
      ));
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Liste bildirilemedi: $e',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runRealScan() async {
    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Gerçek Tarama',
      message: 'Kan tahlili eksik danışanların bugünkü listesi bütün '
          'adminlerin ziline gönderilir. Bugün zaten tarandıysa liste '
          'güncellenir. Devam edilsin mi?',
      confirmText: 'Taramayı çalıştır',
      cancelText: 'Vazgeç',
    );
    if (!confirmed || !mounted) return;
    final BloodTestProvider bloodTests =
        Provider.of<BloodTestProvider>(context, listen: false);
    final LoadingDialog loading =
        DialogUtils.openLoading(context, message: 'Danışanlar taranıyor...');
    try {
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Oturum bulunamadı');
      final int? count = await bloodTests.runDailyScan(
        uid: uid,
        now: DateTime.now(),
        force: true,
      );
      loading.close();
      if (!mounted) return;
      unawaited(_loadState());
      await DialogUtils.openInfo(
        context,
        title: 'Tarama tamamlandı',
        message: (count ?? 0) == 0
            ? 'Kan tahlili eksik danışan bulunmadı.'
            : '$count danışanın kan tahlili eksik. Zilin "Sistem" '
                'sekmesindeki "Kan tahlili eksik danışanlar" bildirimine '
                'bakın.',
      );
    } catch (e) {
      loading.close();
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Tarama yapılamadı: $e',
      );
    }
  }

  Future<void> _openCustomer(NotificationCustomer customer) async {
    await openCustomerSummaryById(
      context,
      userId: customer.userId,
      displayName: customer.name,
    );
  }

  String _lastScanText() {
    if (_stateFailed) return 'Son tarama bilgisi alınamadı.';
    final BloodTestScanState? state = _state;
    if (state == null) return 'Son tarama bilgisi yükleniyor...';
    final DateTime? at = state.lastScanAt;
    if (!state.hasScanned || at == null) return 'Henüz tarama yapılmadı.';
    final String? by = _lastScanByName;
    return 'Son tarama: ${DateFormatter.formatNumericDateTime(at)}'
        '${by == null ? '' : ' · $by'}';
  }

  @override
  Widget build(BuildContext context) {
    final BloodTestScanPreview? preview = _preview;
    final DateTime? customDay = _customDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Expanded(child: _ToolHint(_lastScanText())),
          ],
        ),
        const SizedBox(height: 10),
        FilterChipGroup<int>(
          title: 'Hangi gün taransa?',
          options: _dayOptions,
          selectedValue: customDay == null ? _dayOffset : null,
          showAllOption: false,
          horizontalScroll: false,
          selectedColor: widget.color.withValues(alpha: 0.16),
          onSelected: (offset) {
            if (offset == null) return;
            setState(() {
              _dayOffset = offset;
              _customDay = null;
              _preview = null;
            });
          },
        ),
        TextButton.icon(
          onPressed: _busy ? null : _pickDay,
          icon: const Icon(Icons.event_rounded, size: 18),
          label: Text(customDay == null
              ? 'Başka bir gün seç'
              : DateFormatter.formatLongDate(customDay)),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: widget.color),
              onPressed: _busy ? null : _runPreview,
              icon: const Icon(Icons.manage_search_rounded, size: 18),
              label: const Text('Önizle'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _runRealScan,
              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: const Text('Gerçek taramayı çalıştır'),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        if (preview != null) _buildPreview(preview),
      ],
    );
  }

  Widget _buildPreview(BloodTestScanPreview preview) {
    final List<NotificationCustomer> missing = preview.missing;
    final bool canCollapse = missing.length > _collapsedChipCount;
    final List<NotificationCustomer> shown = _showAllMissing || !canCollapse
        ? missing
        : missing.take(_collapsedChipCount).toList();
    final int hidden = missing.length - shown.length;
    const TextStyle heading = TextStyle(fontWeight: FontWeight.w800);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          '${DateFormatter.formatLongDate(preview.at)} için listeye girecek: '
          '${missing.length} danışan',
          style: heading,
        ),
        const SizedBox(height: 6),
        if (missing.isEmpty)
          const _ToolHint('Listeye girecek danışan yok.')
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final NotificationCustomer customer in shown)
                CustomerChip(
                  label: customer.name,
                  onPressed: () => _openCustomer(customer),
                ),
              if (hidden > 0)
                ActionChip(
                  label: Text('+$hidden daha'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showAllMissing = true),
                ),
            ],
          ),
        if (preview.waiting.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '1 haftası dolmamış yeni danışanlar (${preview.waiting.length})',
            style: heading,
          ),
          const SizedBox(height: 4),
          for (final BloodTestScanWaiting waiting in preview.waiting)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _ToolHint('${waiting.customer.name} · listeye giriş: '
                  '${DateFormatter.formatNumericDateTime(waiting.listedFrom)}'),
            ),
        ],
        if (preview.unrecordedCount > 0) ...[
          const SizedBox(height: 10),
          _ToolHint('${preview.unrecordedCount} danışanda kan tahlili seçimi '
              'hiç kaydedilmemiş; ilk taramada "Hayır" olarak işaretlenir.'),
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _notifyMe(preview),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Önizlemeyi bana bildir'),
          ),
        ],
      ],
    );
  }
}

class _BirthdayPreview extends StatefulWidget {
  const _BirthdayPreview({required this.color});

  final Color color;

  @override
  State<_BirthdayPreview> createState() => _BirthdayPreviewState();
}

class _BirthdayPreviewState extends State<_BirthdayPreview> {
  static const int _upcomingDays = 30;

  BirthdayIndex? _index;
  bool _failed = false;
  DateTime _day = _today();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final UserProvider users =
        Provider.of<UserProvider>(context, listen: false);
    final AppointmentColorsProvider colors =
        Provider.of<AppointmentColorsProvider>(context, listen: false);
    try {
      await colors.fetchColors();
    } catch (e) {}
    try {
      final List<UserModel> customers =
          await users.fetchAllCustomers(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _index = BirthdayIndex(customers);
        _failed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _pickDay() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Gün',
    );
    if (picked == null || !mounted) return;
    setState(() => _day = picked);
  }

  String _dayLabel(DateTime day) =>
      '${DateFormatter.formatLongDate(day)} ${_weekdayFormat.format(day)}';

  @override
  Widget build(BuildContext context) {
    final BirthdayIndex? index = _index;
    if (_failed) {
      return StatusNote(
        icon: Icons.cloud_off_rounded,
        text: 'Danışanlar yüklenemedi.',
        isError: true,
        action: TextButton(
          onPressed: () {
            setState(() => _failed = false);
            _load(forceRefresh: true);
          },
          child: const Text('Tekrar dene'),
        ),
      );
    }
    if (index == null) {
      return const StatusNote(showProgress: true, text: 'Yükleniyor...');
    }

    final DateTime today = _today();
    final List<UserModel> born = index.on(_day);
    final List<MapEntry<DateTime, List<UserModel>>> upcoming = [];
    for (int offset = 0; offset < _upcomingDays; offset++) {
      final DateTime day =
          DateTime(today.year, today.month, today.day + offset);
      final List<UserModel> users = index.on(day);
      if (users.isNotEmpty) upcoming.add(MapEntry(day, users));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(_dayLabel(_day)),
            ),
            if (!DateUtils.isSameDay(_day, today))
              TextButton(
                onPressed: () => setState(() => _day = today),
                child: const Text('Bugün'),
              ),
            IconButton(
              tooltip: 'Danışanları yeniden yükle',
              onPressed: () {
                setState(() => _index = null);
                _load(forceRefresh: true);
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (born.isEmpty)
          const _ToolHint('Bu gün doğum günü olan danışan yok.')
        else
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final UserModel user in born)
                BirthdayChip(user: user, day: _day),
            ],
          ),
        const SizedBox(height: 14),
        const Text(
          'Yaklaşan doğum günleri (30 gün)',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        if (upcoming.isEmpty)
          const _ToolHint('Önümüzdeki 30 günde doğum günü yok.')
        else
          for (final MapEntry<DateTime, List<UserModel>> entry in upcoming)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _day = entry.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cake_rounded,
                      size: 16,
                      color: DateUtils.isSameDay(entry.key, _day)
                          ? widget.color
                          : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_dayLabel(entry.key)}: '
                        '${entry.value.map(_customerName).join(', ')}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: DateUtils.isSameDay(entry.key, _day)
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 10),
        const _ToolHint('Etiketin rengi Ayarlar > Randevu Arkaplan Renkleri > '
            '"Doğum Günü (DG)" satırından değiştirilir.'),
      ],
    );
  }
}

class _EnterKeyTester extends StatefulWidget {
  const _EnterKeyTester({required this.color});

  final Color color;

  @override
  State<_EnterKeyTester> createState() => _EnterKeyTesterState();
}

class _EnterKeyTesterState extends State<_EnterKeyTester> {
  static const String _hintText = 'Deneme mesajı yazın...';
  static const String _replyText = 'Yanıtlanıyor: "Bugünkü öğle yemeğim"';
  static const int _maxLogEntries = 6;

  final TextEditingController _controller = TextEditingController();
  final List<String> _log = [];
  bool _replying = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addLog(String entry) {
    setState(() {
      _log.insert(0, '${_clockFormat.format(DateTime.now())} · $entry');
      if (_log.length > _maxLogEntries) _log.removeLast();
    });
  }

  void _send() {
    final String text = _controller.text.trim();
    if (text.isEmpty) {
      _addLog('Boş mesaj gönderilmez');
      return;
    }
    final bool asReply = _replying;
    _controller.clear();
    _replying = false;
    _addLog('${asReply ? 'Yanıt gönderildi' : 'Gönderildi'}: '
        '"${text.replaceAll('\n', ' ⏎ ')}"');
  }

  void _cancelReply() {
    _replying = false;
    _addLog('Yanıt iptal edildi (Esc)');
  }

  void _closeReply() {
    _replying = false;
    _addLog('Yanıt kapatıldı');
  }

  @override
  Widget build(BuildContext context) {
    final TargetPlatform platform = defaultTargetPlatform;
    final bool enterSends = chatEnterSendsOn(platform);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ToolHint('Bu cihaz: ${featureTestPlatformLabel(platform)} · '
            '${enterSends ? 'donanım klavyesinde Enter gönderir, Shift+Enter yeni satır açar' : 'Enter yeni satır açar (gönderme düğmeyle)'}'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _replying,
          onChanged: (value) => setState(() => _replying = value),
          title: const Text('Yanıt modu'),
          subtitle: const Text(
              'Bir mesaja yanıt yazıyormuş gibi; Esc yanıtı iptal eder.'),
        ),
        if (_replying)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: widget.color, width: 3)),
            ),
            child: Row(
              children: [
                Icon(Icons.reply_rounded, size: 18, color: widget.color),
                const SizedBox(width: 8),
                const Expanded(child: Text(_replyText)),
                IconButton(
                  tooltip: 'Yanıtı kapat',
                  onPressed: _closeReply,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ChatInputKeyHandler(
                controller: _controller,
                hasReply: () => _replying,
                onSend: _send,
                onCancelReply: _cancelReply,
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _hintText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Gönder',
              onPressed: _send,
              icon: Icon(Icons.send_rounded, color: widget.color),
            ),
          ],
        ),
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final String entry in _log)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                entry,
                style: TextStyle(
                  fontSize: 12.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: Colors.grey.shade800,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
