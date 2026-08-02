import 'package:flutter/material.dart';

/// Public BMI (Beden Kitle İndeksi) calculator page.
/// Accessible without login (reachable from the login page).
/// Takes age, weight (kg) and height (cm) and shows the BMI value, its
/// category and the ideal weight range for the given height.
class BmiCalculatorPage extends StatefulWidget {
  const BmiCalculatorPage({super.key});

  @override
  State<BmiCalculatorPage> createState() => _BmiCalculatorPageState();
}

class _BmiCalculatorPageState extends State<BmiCalculatorPage> {
  static const String _pageTitle = 'BKİ Hesaplama';
  static const String _ageLabel = 'Yaş';
  static const String _weightLabel = 'Kilo (kg)';
  static const String _heightLabel = 'Boy (cm)';
  static const String _calculateText = 'Hesapla';
  static const String _requiredText = 'Bu alan zorunludur';
  static const String _invalidNumberText = 'Geçerli bir sayı girin';
  static const String _underAgeNote =
      'Not: 18 yaş altı için BKİ, yaşa ve cinsiyete göre persentil eğrileriyle '
      'değerlendirilir; bu sonuç yetişkinler için geçerlidir.';

  // WHO adult BMI category thresholds.
  static const double _underweightLimit = 18.5;
  static const double _normalLimit = 25.0;
  static const double _overweightLimit = 30.0;

  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();

  double? _bmi;
  int? _age;
  double? _idealWeightMin;
  double? _idealWeightMax;

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  /// Parses a locale-tolerant decimal input (accepts both ',' and '.').
  double? _parseDecimal(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  String? _validateNumber(
    String? value, {
    required double min,
    required double max,
  }) {
    if (value == null || value.trim().isEmpty) return _requiredText;
    final parsed = _parseDecimal(value);
    if (parsed == null) return _invalidNumberText;
    if (parsed < min || parsed > max) {
      return 'Değer $min - $max aralığında olmalıdır';
    }
    return null;
  }

  void _calculate() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final age = _parseDecimal(_ageController.text)!.round();
    final weight = _parseDecimal(_weightController.text)!;
    final heightMeters = _parseDecimal(_heightController.text)! / 100;

    setState(() {
      _age = age;
      _bmi = weight / (heightMeters * heightMeters);
      _idealWeightMin = _underweightLimit * heightMeters * heightMeters;
      _idealWeightMax =
          (_normalLimit - 0.1) * heightMeters * heightMeters;
    });
  }

  /// Category label and color for the calculated BMI.
  (String, Color) _categoryFor(double bmi) {
    if (bmi < _underweightLimit) return ('Zayıf', Colors.blue);
    if (bmi < _normalLimit) return ('Normal', Colors.green);
    if (bmi < _overweightLimit) return ('Fazla Kilolu', Colors.orange);
    return ('Obez', Colors.red);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_pageTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep the form comfortably narrow on wide (desktop) screens.
            final maxWidth = constraints.maxWidth > 600 ? 500.0 : double.infinity;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildForm(),
                      const SizedBox(height: 24),
                      if (_bmi != null) _buildResultCard(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: _ageLabel,
              hintText: 'Örn: 30',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.cake),
            ),
            validator: (value) => _validateNumber(value, min: 1, max: 120),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: _weightLabel,
              hintText: 'Örn: 70',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.monitor_weight),
            ),
            validator: (value) => _validateNumber(value, min: 10, max: 400),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _heightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: _heightLabel,
              hintText: 'Örn: 170',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.height),
            ),
            validator: (value) => _validateNumber(value, min: 50, max: 250),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.calculate),
              label: const Text(
                _calculateText,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final bmi = _bmi!;
    final (categoryText, categoryColor) = _categoryFor(bmi);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              'Beden Kitle İndeksiniz',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              bmi.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: categoryColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: categoryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: categoryColor.withOpacity(0.4)),
              ),
              child: Text(
                categoryText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: categoryColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Boyunuza göre ideal kilo aralığı: '
              '${_idealWeightMin!.toStringAsFixed(1)} - '
              '${_idealWeightMax!.toStringAsFixed(1)} kg',
              style: const TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
            if (_age != null && _age! < 18) ...[
              const SizedBox(height: 12),
              Text(
                _underAgeNote,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
