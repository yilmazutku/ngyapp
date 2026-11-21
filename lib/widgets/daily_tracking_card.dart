import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/daily_data_provider.dart';
import '../services/health_steps_service.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';

class DailyTrackingCard extends StatefulWidget {
  const DailyTrackingCard({
    super.key,
    required this.userId,
    required this.today,
    required this.onShowHistory,
    this.healthSteps = const HealthStepsService(),
  });

  final String userId;
  final DateTime today;
  final VoidCallback onShowHistory;
  final HealthStepsService healthSteps;

  @override
  State<DailyTrackingCard> createState() => _DailyTrackingCardState();
}

class _DailyTrackingCardState extends State<DailyTrackingCard> {
  static const String _titleText = 'Günlük Takip';
  static const String _historyText = 'Geçmiş';
  static const String _waterText = 'Su';
  static const String _stepsText = 'Adım';
  static const String _savedLabel = 'Kayıtlı';
  static const String _notSavedText = '—';
  static const String _saveText = 'Kaydet';
  static const String _previousDayTooltip = 'Önceki gün';
  static const String _nextDayTooltip = 'Sonraki gün';
  static const String _fromHealthText =
      'Adım sayısı sağlık uygulamasından alındı.';
  static const String _loadErrorText = 'Kayıtlı veriler yüklenemedi.';
  static const String _retryText = 'Tekrar dene';
  static const String _errorTitle = 'Hata';
  static const String _successTitle = 'Başarılı';
  static const String _invalidStepsText =
      'Girilen adım sayısı geçerli değildir. Lütfen kontrol ediniz.';
  static const String _savedText = 'Günlük verileriniz başarıyla kaydedildi.';
  static const String _saveErrorText = 'Veriler kaydedilirken bir hata oluştu.';

  static const int _maxDaysBack = 365;
  static const double _maxWaterLiters = 5;
  static const int _waterDivisions = 20;
  static const double _valueLabelWidth = 48;
  static const double _savedFieldWidth = 84;
  static const EdgeInsets _fieldPadding =
      EdgeInsets.symmetric(horizontal: 8, vertical: 9);
  static const double _progressSize = 14;

  final DateFormat _weekdayFormat = DateFormat('EEEE', 'tr_TR');
  final NumberFormat _stepsFormat = NumberFormat.decimalPattern('tr_TR');
  final TextEditingController _stepsController =
      TextEditingController(text: '0');
  final FocusNode _stepsFocusNode = FocusNode();

  late DateTime _date;
  double _waterIntakeLiters = 0;
  DailyData? _saved;
  bool _loadFailed = false;
  bool _stepsFromHealth = false;
  bool _stepsEdited = false;
  bool _isSaving = false;
  int _loadRequest = 0;

  DateTime get _today => _dayOf(widget.today);

  DateTime get _firstDate =>
      DateTime(_today.year, _today.month, _today.day - _maxDaysBack);

  bool get _ready => _saved != null && !_isSaving;

  @override
  void initState() {
    super.initState();
    _stepsFocusNode.addListener(_handleStepsFocusChange);
    _date = _today;
    _load();
  }

  @override
  void dispose() {
    _stepsFocusNode.removeListener(_handleStepsFocusChange);
    _stepsFocusNode.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  static DateTime _dayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  void _handleStepsFocusChange() {
    if (_stepsFocusNode.hasFocus) {
      if (_stepsController.text == '0') {
        _stepsController.clear();
      }
    } else if (_stepsController.text.isEmpty) {
      _stepsController.text = '0';
    }
  }

  void _handleStepsChanged(String _) {
    _stepsEdited = true;
    if (_stepsFromHealth) {
      setState(() => _stepsFromHealth = false);
    }
  }

  void _selectDate(DateTime date) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _date = _dayOf(date);
      _saved = null;
      _loadFailed = false;
      _stepsFromHealth = false;
      _stepsEdited = false;
      _waterIntakeLiters = 0;
      _stepsController.text = '0';
    });
    _load();
  }

  void _shiftDate(int days) =>
      _selectDate(DateTime(_date.year, _date.month, _date.day + days));

  Future<void> _load() async {
    final int request = ++_loadRequest;
    final DateTime date = _date;
    final DailyDataProvider provider =
        Provider.of<DailyDataProvider>(context, listen: false);
    final Future<int?> healthSteps = widget.healthSteps.stepsForDay(date);

    try {
      final DailyData saved =
          await provider.fetchDailyDataForDate(widget.userId, date: date);
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _saved = saved;
        _waterIntakeLiters =
            saved.waterIntake.clamp(0.0, _maxWaterLiters).toDouble();
        _stepsController.text = saved.steps.toString();
      });
    } catch (_) {
      if (!mounted || request != _loadRequest) return;
      setState(() => _loadFailed = true);
      return;
    }

    final int? steps = await healthSteps;
    if (!mounted || request != _loadRequest || _stepsEdited || _isSaving) {
      return;
    }
    if (steps == null || steps <= 0) return;
    setState(() {
      _stepsController.text = steps.toString();
      _stepsFromHealth = true;
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _firstDate,
      lastDate: _today,
      locale: const Locale('tr', 'TR'),
    );
    if (!mounted || picked == null || DateFormatter.isSameDay(picked, _date)) {
      return;
    }
    _selectDate(picked);
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final String text = _stepsController.text.trim();
    final int? steps = text.isEmpty ? 0 : int.tryParse(text);
    if (steps == null || steps < 0) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: _errorTitle,
        message: _invalidStepsText,
      );
      return;
    }

    final DateTime date = _date;
    final double water = _waterIntakeLiters;
    final DailyDataProvider provider =
        Provider.of<DailyDataProvider>(context, listen: false);
    setState(() => _isSaving = true);

    try {
      await provider.saveDailyData(
        widget.userId,
        date,
        waterIntake: water,
        steps: steps,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      await DialogUtils.openError(
        context,
        title: _errorTitle,
        message: _saveErrorText,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _saved = DailyData(waterIntake: water, steps: steps, isSaved: true);
      _stepsController.text = steps.toString();
    });
    await DialogUtils.openInfo(
      context,
      title: _successTitle,
      message: _savedText,
    );
  }

  String _dateLabel() {
    final String label =
        DateFormatter.formatChatDayLabel(_date, now: widget.today);
    if (DateFormatter.calendarDaysBetween(_date, widget.today) <= 1) {
      return label;
    }
    return '$label ${_weekdayFormat.format(_date)}';
  }

  String _savedWaterText(DailyData? saved) => saved == null || !saved.isSaved
      ? _notSavedText
      : '${saved.waterIntake.toStringAsFixed(1)}L';

  String _savedStepsText(DailyData? saved) => saved == null || !saved.isSaved
      ? _notSavedText
      : _stepsFormat.format(saved.steps);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildDateBar(),
            const Divider(height: 8, thickness: 0.5),
            const SizedBox(height: 4),
            _buildWaterRow(),
            const Divider(height: 16, thickness: 0.5),
            _buildStepsRow(),
            const SizedBox(height: 8),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Text(
          _titleText,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: widget.onShowHistory,
          icon: Icon(Icons.history, size: 16, color: Colors.indigo.shade600),
          label: Text(
            _historyText,
            style: TextStyle(fontSize: 12, color: Colors.indigo.shade600),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            visualDensity: VisualDensity.compact,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildDateBar() {
    final bool isToday = DateFormatter.isSameDay(_date, _today);
    final Color color =
        isToday ? Colors.indigo.shade700 : Colors.deepOrange.shade700;

    return Row(
      children: [
        IconButton(
          tooltip: _previousDayTooltip,
          visualDensity: VisualDensity.compact,
          onPressed:
              !_isSaving && _date.isAfter(_firstDate) ? () => _shiftDate(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: TextButton.icon(
            onPressed: _isSaving ? null : _pickDate,
            icon: Icon(Icons.calendar_today, size: 16, color: color),
            label: Text(
              _dateLabel(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: _nextDayTooltip,
          visualDensity: VisualDensity.compact,
          onPressed: !_isSaving && !isToday ? () => _shiftDate(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildRowLabel(IconData icon, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildWaterRow() {
    return Row(
      children: [
        _buildRowLabel(Icons.water_drop, Colors.blue.shade600, _waterText),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.blue.shade400,
              inactiveTrackColor: Colors.blue.shade100,
              thumbColor: Colors.blue.shade600,
            ),
            child: Slider(
              value: _waterIntakeLiters,
              min: 0,
              max: _maxWaterLiters,
              divisions: _waterDivisions,
              onChanged: _ready
                  ? (double value) => setState(() => _waterIntakeLiters = value)
                  : null,
            ),
          ),
        ),
        SizedBox(
          width: _valueLabelWidth,
          child: Text(
            '${_waterIntakeLiters.toStringAsFixed(1)}L',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
            textAlign: TextAlign.end,
          ),
        ),
        const SizedBox(width: 8),
        _buildSavedField(_savedWaterText(_saved)),
      ],
    );
  }

  OutlineInputBorder _fieldBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      );

  Widget _buildStepsRow() {
    final OutlineInputBorder border = _fieldBorder();

    return Row(
      children: [
        _buildRowLabel(
            Icons.directions_walk, Colors.green.shade600, _stepsText),
        Expanded(
          child: TextField(
            controller: _stepsController,
            focusNode: _stepsFocusNode,
            enabled: _ready,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onChanged: _handleStepsChanged,
            onSubmitted: (_) => _stepsFocusNode.unfocus(),
            onTapOutside: (_) => _stepsFocusNode.unfocus(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              contentPadding: _fieldPadding,
              border: border,
              enabledBorder: border,
              disabledBorder: border,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.green.shade400, width: 1.5),
              ),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildSavedField(_savedStepsText(_saved)),
      ],
    );
  }

  Widget _buildSavedField(String value) {
    final OutlineInputBorder border = _fieldBorder();
    final bool loading = _saved == null && !_loadFailed;

    return SizedBox(
      width: _savedFieldWidth,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _savedLabel,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          isDense: true,
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: _fieldPadding,
          border: border,
          enabledBorder: border,
        ),
        child: Center(
          heightFactor: 1,
          child: loading
              ? const SizedBox(
                  width: _progressSize,
                  height: _progressSize,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        Expanded(child: _buildFooterNote()),
        const SizedBox(width: 8),
        SizedBox(
          height: 32,
          child: FilledButton.icon(
            onPressed: _ready ? _save : null,
            icon: _isSaving
                ? const SizedBox(
                    width: _progressSize,
                    height: _progressSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 16),
            label: const Text(_saveText, style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterNote() {
    if (_loadFailed) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _loadErrorText,
            style: TextStyle(fontSize: 11, color: Colors.red.shade700),
          ),
          TextButton(
            onPressed: () => _selectDate(_date),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(_retryText, style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }
    if (!_stepsFromHealth) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(Icons.favorite, size: 14, color: Colors.pink.shade400),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _fromHealthText,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }
}
