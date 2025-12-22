import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/meas_model.dart';
import '../providers/meas_provider.dart';
import '../utils/dialog_utils.dart';

class EditMeasurementDialog extends StatefulWidget {
  final String userId;
  final MeasurementModel measurement;
  final VoidCallback onMeasurementUpdated;

  const EditMeasurementDialog({
    super.key,
    required this.userId,
    required this.measurement,
    required this.onMeasurementUpdated,
  });

  @override
  createState() => _EditMeasurementDialogState();
}

class _EditMeasurementDialogState extends State<EditMeasurementDialog> {
  final Logger logger = Logger.forClass(EditMeasurementDialog);
  final DateFormat df=DateFormat('d MMMM y', 'tr_TR');
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // We keep date separate but preserve original time-of-day on save
  late DateTime _dateOnly;

  // Controllers prefilled from the incoming model
  late final TextEditingController _weightCtrl;
  late final TextEditingController _chestCtrl;
  late final TextEditingController _backCtrl;
  late final TextEditingController _waistCtrl;
  late final TextEditingController _hipsCtrl;
  late final TextEditingController _legCtrl;
  late final TextEditingController _armCtrl;
  late final TextEditingController _fatKgCtrl;
  late final TextEditingController _calorieCtrl;
  late final TextEditingController _hungerCtrl;
  late final TextEditingController _constipationCtrl;
  late final TextEditingController _otherCtrl;

  @override
  void initState() {
    super.initState();
    final m = widget.measurement;

    _dateOnly = DateTime(m.measDate.year, m.measDate.month, m.measDate.day);

    _weightCtrl = TextEditingController(text: _fmtNum(m.weight));
    _chestCtrl = TextEditingController(text: _fmtNum(m.chest));
    _backCtrl = TextEditingController(text: _fmtNum(m.back));
    _waistCtrl = TextEditingController(text: _fmtNum(m.waist));
    _hipsCtrl = TextEditingController(text: _fmtNum(m.hips));
    _legCtrl = TextEditingController(text: _fmtNum(m.leg));
    _armCtrl = TextEditingController(text: _fmtNum(m.arm));
    _fatKgCtrl = TextEditingController(text: _fmtNum(m.fatKg));
    _calorieCtrl = TextEditingController(text: m.calorie?.toString() ?? '');
    _hungerCtrl = TextEditingController(text: m.hungerStatus ?? '');
    _constipationCtrl = TextEditingController(text: m.constipation ?? '');
    _otherCtrl = TextEditingController(text: m.other ?? '');
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _chestCtrl.dispose();
    _backCtrl.dispose();
    _waistCtrl.dispose();
    _hipsCtrl.dispose();
    _legCtrl.dispose();
    _armCtrl.dispose();
    _fatKgCtrl.dispose();
    _calorieCtrl.dispose();
    _hungerCtrl.dispose();
    _constipationCtrl.dispose();
    _otherCtrl.dispose();
    super.dispose();
  }

  String _fmtNum(double? v) => v == null ? '' : v.toString();

  double? _toDouble(String s) =>
      s.trim().isEmpty ? null : double.tryParse(s.replaceAll(',', '.'));

  int? _toInt(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOnly,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      _dateOnly = DateTime(picked.year, picked.month, picked.day);
      setState(() {});
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final original = widget.measurement;

    // Preserve original time-of-day (hour/min/sec) when changing date
    final newDate = DateTime(
      _dateOnly.year,
      _dateOnly.month,
      _dateOnly.day,
      original.measDate.hour,
      original.measDate.minute,
      original.measDate.second,
    );

    // Create an updated model (same id!)
    final updated = MeasurementModel(
      measurementId: original.measurementId,
      measDate: newDate,
      weight: _toDouble(_weightCtrl.text),
      chest: _toDouble(_chestCtrl.text),
      back: _toDouble(_backCtrl.text),
      waist: _toDouble(_waistCtrl.text),
      hips: _toDouble(_hipsCtrl.text),
      leg: _toDouble(_legCtrl.text),
      arm: _toDouble(_armCtrl.text),
      fatKg: _toDouble(_fatKgCtrl.text),
      calorie: _toInt(_calorieCtrl.text),
      hungerStatus: _hungerCtrl.text.trim().isEmpty ? null : _hungerCtrl.text.trim(),
      constipation: _constipationCtrl.text.trim().isEmpty ? null : _constipationCtrl.text.trim(),
      other: _otherCtrl.text.trim().isEmpty ? null : _otherCtrl.text.trim(),
      createDate: original.createDate,
      createUser: original.createUser,
      updateDate: DateTime.now(),
      updateUser: 'admin',
      changeState: original.changeState,
    );

    // Confirm
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Ölçüm Güncelle',
      message: 'Bu ölçümü güncellemek istediğinize emin misiniz?\n'
          'Tarih: ${df.format(updated.measDate)}',
      confirmText: 'Evet',
      cancelText: 'İptal',
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final provider = Provider.of<MeasProvider>(context, listen: false);
      await provider.updateMeasurement(widget.userId, updated);

      if (!mounted) return;
      Navigator.of(context).pop(); // close first
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Ölçüm başarıyla güncellendi.',
      );

      widget.onMeasurementUpdated(); // parent refresh
    } catch (e) {
      logger.err('Error updating measurement: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Ölçüm güncellenirken hata oluştu: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = df.format(_dateOnly);
    logger.info('EditMeasDialog build.');
    return AlertDialog(
      title: const Text('Ölçüm Düzenle'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Date (required)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Tarih: $dateLabel'),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),

              // Numeric (optional)
              _numField(_weightCtrl, 'Ağırlık (kg)'),
              _numField(_chestCtrl, 'Göğüs (cm)'),
              _numField(_backCtrl, 'Sırt (cm)'),
              _numField(_waistCtrl, 'Bel (cm)'),
              _numField(_hipsCtrl, 'Kalça (cm)'),
              _numField(_legCtrl, 'Bacak (cm)'),
              _numField(_armCtrl, 'Kol (cm)'),
              _numField(_fatKgCtrl, 'Yağ (kg)'),
              _intField(_calorieCtrl, 'Kalori'),

              const SizedBox(height: 12),

              // Text (optional)
              _textField(_hungerCtrl, 'Açlık Durumu'),
              _textField(_constipationCtrl, 'Kabızlık'),
              _textField(_otherCtrl, 'Diğer'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Kaydet'),
        ),
      ],
    );
  }

  Widget _numField(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );

  Widget _intField(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );

  Widget _textField(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );
}
