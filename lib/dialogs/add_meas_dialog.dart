import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/logger.dart';
import '../models/meas_model.dart';
import '../providers/meas_provider.dart';
import '../utils/dialog_utils.dart';

class AddMeasurementDialog extends StatefulWidget {
  final String userId;
  final VoidCallback onMeasurementAdded;

  const AddMeasurementDialog({
    super.key,
    required this.userId,
    required this.onMeasurementAdded,
  });

  @override
  createState() => _AddMeasurementDialogState();
}

class _AddMeasurementDialogState extends State<AddMeasurementDialog> {
  final Logger logger = Logger.forClass(AddMeasurementDialog);

  // Form state
  final _formKey = GlobalKey<FormState>();

  // Date
  DateTime _measDate = DateTime.now();

  // Controllers for numeric/text fields (nullable fields allowed)
  final _weightCtrl = TextEditingController();
  final _chestCtrl = TextEditingController();
  final _backCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _hipsCtrl = TextEditingController();
  final _legCtrl = TextEditingController();
  final _armCtrl = TextEditingController();
  final _fatKgCtrl = TextEditingController();
  final _calorieCtrl = TextEditingController();
  final _hungerCtrl = TextEditingController();
  final _constipationCtrl = TextEditingController();
  final _otherCtrl = TextEditingController();

  bool _isSaving = false;

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

  double? _parseDouble(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  int? _parseInt(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return int.tryParse(s.trim());
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _measDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      // Keep time portion 00:00; measurement is date-based in UI
      _measDate = DateTime(picked.year, picked.month, picked.day);
      setState(() {});
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Confirm
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Ölçüm Ekle',
      message: 'Bu ölçümü eklemek istediğinize emin misiniz?\n'
          'Tarih: ${DateFormat('d MMMM yyyy', 'tr_TR').format(_measDate)}',
      confirmText: 'Evet',
      cancelText: 'İptal',
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final meas = MeasurementModel(
        measurementId: DateTime.now().millisecondsSinceEpoch.toString(),
        measDate: _measDate,
        weight: _parseDouble(_weightCtrl.text),
        chest: _parseDouble(_chestCtrl.text),
        back: _parseDouble(_backCtrl.text),
        waist: _parseDouble(_waistCtrl.text),
        hips: _parseDouble(_hipsCtrl.text),
        leg: _parseDouble(_legCtrl.text),
        arm: _parseDouble(_armCtrl.text),
        fatKg: _parseDouble(_fatKgCtrl.text),
        calorie: _parseInt(_calorieCtrl.text),
        hungerStatus: _hungerCtrl.text.trim().isEmpty ? null : _hungerCtrl.text.trim(),
        constipation: _constipationCtrl.text.trim().isEmpty ? null : _constipationCtrl.text.trim(),
        other: _otherCtrl.text.trim().isEmpty ? null : _otherCtrl.text.trim(),
        createUser: 'admin', // aynı pattern: ödeme eklerken kullandığınız gibi
      );

      final provider = Provider.of<MeasProvider>(context, listen: false);
      await provider.addMeasurement(widget.userId, meas);

      if (!mounted) return;
      Navigator.of(context).pop(); // close dialog first
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Ölçüm başarıyla eklendi.',
      );

      widget.onMeasurementAdded(); // parent refresh
    } catch (e) {
      logger.err('Error adding measurement: {}', [e]);
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Ölçüm eklenirken bir hata oluştu: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    logger.info('AddMeasDialog build.');
    return AlertDialog(
      title: const Text('Ölçüm Ekle'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          // keep dialog comfortable on wide screens
          maxWidth: size.width * 0.9,
          maxHeight: size.height * 0.8,
          minWidth: size.width * 0.4,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Date picker (required)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Tarih: ${DateFormat('d MMMM yyyy', 'tr_TR').format(_measDate)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 12),

                // Numbers (optional)
                _numField(controller: _weightCtrl, label: 'Ağırlık (kg)'),
                _numField(controller: _chestCtrl, label: 'Göğüs (cm)'),
                _numField(controller: _backCtrl, label: 'Sırt (cm)'),
                _numField(controller: _waistCtrl, label: 'Bel (cm)'),
                _numField(controller: _hipsCtrl, label: 'Kalça (cm)'),
                _numField(controller: _legCtrl, label: 'Bacak (cm)'),
                _numField(controller: _armCtrl, label: 'Kol (cm)'),
                _numField(controller: _fatKgCtrl, label: 'Yağ (kg)'),
                _intField(controller: _calorieCtrl, label: 'Kalori'),

                const SizedBox(height: 12),

                // Texts (optional)
                _textField(controller: _hungerCtrl, label: 'Açlık Durumu'),
                _textField(controller: _constipationCtrl, label: 'Kabızlık'),
                _textField(controller: _otherCtrl, label: 'Diğer'),
              ],
            ),
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
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Kaydet'),
        ),
      ],
    );
  }

  Widget _numField({required TextEditingController controller, required String label}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        // optional numbers: no validation needed; accept empty
      ),
    );
  }

  Widget _intField({required TextEditingController controller, required String label}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _textField({required TextEditingController controller, required String label}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
