import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/date_formatter.dart';
import 'feature_test_plan.dart';

class FeatureTestSummary {
  final int total;
  final int passed;
  final int failed;
  final int skipped;

  const FeatureTestSummary({
    required this.total,
    required this.passed,
    required this.failed,
    required this.skipped,
  });

  int get done => passed + failed + skipped;
  int get open => total - done;
  bool get isComplete => total > 0 && done == total;
}

class FeatureTestChecklist extends ChangeNotifier {
  FeatureTestChecklist({
    required this.platform,
    this.sections = featureTestSections,
  });

  static const String storageKey = 'featureTestChecklist.v2';
  static const String legacyStorageKey = 'featureTestChecklist.v1';

  static const String _resultsKey = 'results';
  static const String _notesKey = 'notes';
  static const String _customKey = 'custom';
  static const String _collapsedKey = 'collapsed';
  static const String _filterKey = 'filter';
  static const String _onlyThisDeviceKey = 'onlyThisDevice';
  static const String _settingsKey = 'settings';
  static const String _idKey = 'id';
  static const String _sectionKey = 'section';
  static const String _actionKey = 'action';
  static const String _expectedKey = 'expected';

  static const String _reportTitle = 'Kan Tahlili Test · Test Raporu';

  final TargetPlatform platform;
  final List<FeatureTestSection> sections;

  final Map<String, FeatureTestResult> _results = {};
  final Map<String, String> _notes = {};
  final Map<String, List<FeatureTestStep>> _custom = {};
  final Set<String> _collapsed = {};
  final Map<String, String> _settings = {};
  FeatureTestFilter _filter = FeatureTestFilter.all;
  bool _onlyThisDevice = false;
  bool _loaded = false;
  bool _disposed = false;

  bool get isLoaded => _loaded;
  FeatureTestFilter get filter => _filter;
  bool get onlyThisDevice => _onlyThisDevice;

  FeatureTestResult? resultOf(String stepId) => _results[stepId];
  String? noteOf(String stepId) => _notes[stepId];
  bool isCollapsed(String sectionId) => _collapsed.contains(sectionId);
  bool get allCollapsed =>
      sections.every((section) => _collapsed.contains(section.id));
  String? setting(String key) => _settings[key];

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(storageKey);
      if (raw != null) {
        _restore(raw);
      } else {
        for (final String id
            in prefs.getStringList(legacyStorageKey) ?? const <String>[]) {
          _results[id] = FeatureTestResult.passed;
        }
      }
    } catch (e) {
      _results.clear();
    }
    _loaded = true;
    _notify();
  }

  void _restore(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) return;

    final Object? results = decoded[_resultsKey];
    if (results is Map) {
      results.forEach((id, value) {
        final FeatureTestResult? result = FeatureTestResult.fromValue(value);
        if (id is String && result != null) _results[id] = result;
      });
    }

    final Object? notes = decoded[_notesKey];
    if (notes is Map) {
      notes.forEach((id, value) {
        if (id is String && value is String && value.trim().isNotEmpty) {
          _notes[id] = value;
        }
      });
    }

    final Object? custom = decoded[_customKey];
    if (custom is List) {
      final Set<String> sectionIds = {for (final s in sections) s.id};
      for (final Object? entry in custom) {
        if (entry is! Map) continue;
        final Object? id = entry[_idKey];
        final Object? sectionId = entry[_sectionKey];
        final Object? action = entry[_actionKey];
        final Object? expected = entry[_expectedKey];
        if (id is! String ||
            sectionId is! String ||
            !sectionIds.contains(sectionId) ||
            action is! String ||
            action.trim().isEmpty) {
          continue;
        }
        (_custom[sectionId] ??= []).add(FeatureTestStep(
          id,
          action,
          expected is String ? expected : '',
          isCustom: true,
        ));
      }
    }

    final Object? collapsed = decoded[_collapsedKey];
    if (collapsed is List) {
      _collapsed.addAll(collapsed.whereType<String>());
    }

    final Object? settings = decoded[_settingsKey];
    if (settings is Map) {
      settings.forEach((key, value) {
        if (key is String && value is String) _settings[key] = value;
      });
    }

    _filter = FeatureTestFilter.fromValue(decoded[_filterKey]);
    _onlyThisDevice = decoded[_onlyThisDeviceKey] == true;
  }

  Map<String, Object> _toJson() => {
        _resultsKey: {
          for (final MapEntry<String, FeatureTestResult> entry
              in _results.entries)
            entry.key: entry.value.value,
        },
        _notesKey: _notes,
        _customKey: [
          for (final MapEntry<String, List<FeatureTestStep>> entry
              in _custom.entries)
            for (final FeatureTestStep step in entry.value)
              {
                _idKey: step.id,
                _sectionKey: entry.key,
                _actionKey: step.action,
                _expectedKey: step.expected,
              },
        ],
        _collapsedKey: _collapsed.toList(),
        _filterKey: _filter.value,
        _onlyThisDeviceKey: _onlyThisDevice,
        _settingsKey: _settings,
      };

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(_toJson()));
      if (prefs.containsKey(legacyStorageKey)) {
        await prefs.remove(legacyStorageKey);
      }
    } catch (e) {
      return;
    }
  }

  void _changed() {
    _notify();
    unawaited(_save());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<FeatureTestStep> stepsOf(FeatureTestSection section) => [
        ...section.steps,
        ...?_custom[section.id],
      ];

  bool isInScope(FeatureTestStep step) =>
      !_onlyThisDevice || step.appliesTo(platform);

  List<FeatureTestStep> visibleStepsOf(FeatureTestSection section) => [
        for (final FeatureTestStep step in stepsOf(section))
          if (isInScope(step) && _filter.matches(_results[step.id])) step,
      ];

  FeatureTestSummary summaryOf(Iterable<FeatureTestStep> steps) {
    int total = 0;
    int passed = 0;
    int failed = 0;
    int skipped = 0;
    for (final FeatureTestStep step in steps) {
      if (!isInScope(step)) continue;
      total++;
      switch (_results[step.id]) {
        case FeatureTestResult.passed:
          passed++;
        case FeatureTestResult.failed:
          failed++;
        case FeatureTestResult.skipped:
          skipped++;
        case null:
          break;
      }
    }
    return FeatureTestSummary(
      total: total,
      passed: passed,
      failed: failed,
      skipped: skipped,
    );
  }

  FeatureTestSummary get summary =>
      summaryOf([for (final section in sections) ...stepsOf(section)]);

  void setResult(String stepId, FeatureTestResult? result) {
    if (result == null || _results[stepId] == result) {
      if (_results.remove(stepId) == null) return;
    } else {
      _results[stepId] = result;
    }
    _changed();
  }

  void setNote(String stepId, String? note) {
    final String text = note?.trim() ?? '';
    if (text.isEmpty) {
      if (_notes.remove(stepId) == null) return;
    } else {
      if (_notes[stepId] == text) return;
      _notes[stepId] = text;
    }
    _changed();
  }

  String addCustomStep({
    required String sectionId,
    required String action,
    required String expected,
  }) {
    final String id =
        'custom.$sectionId.${DateTime.now().microsecondsSinceEpoch}';
    (_custom[sectionId] ??= []).add(FeatureTestStep(
      id,
      action.trim(),
      expected.trim(),
      isCustom: true,
    ));
    _changed();
    return id;
  }

  void updateCustomStep({
    required String stepId,
    required String action,
    required String expected,
  }) {
    for (final List<FeatureTestStep> steps in _custom.values) {
      final int index = steps.indexWhere((step) => step.id == stepId);
      if (index < 0) continue;
      steps[index] = FeatureTestStep(
        stepId,
        action.trim(),
        expected.trim(),
        isCustom: true,
      );
      _changed();
      return;
    }
  }

  void removeCustomStep(String stepId) {
    bool removed = false;
    for (final List<FeatureTestStep> steps in _custom.values) {
      final int before = steps.length;
      steps.removeWhere((step) => step.id == stepId);
      removed = removed || steps.length != before;
    }
    if (!removed) return;
    _custom.removeWhere((_, steps) => steps.isEmpty);
    _results.remove(stepId);
    _notes.remove(stepId);
    _changed();
  }

  void toggleCollapsed(String sectionId) {
    if (!_collapsed.remove(sectionId)) _collapsed.add(sectionId);
    _changed();
  }

  void setAllCollapsed(bool collapsed) {
    _collapsed.clear();
    if (collapsed) _collapsed.addAll(sections.map((section) => section.id));
    _changed();
  }

  set filter(FeatureTestFilter value) {
    if (_filter == value) return;
    _filter = value;
    _changed();
  }

  set onlyThisDevice(bool value) {
    if (_onlyThisDevice == value) return;
    _onlyThisDevice = value;
    _changed();
  }

  void setSetting(String key, String? value) {
    if (value == null) {
      if (_settings.remove(key) == null) return;
    } else {
      if (_settings[key] == value) return;
      _settings[key] = value;
    }
    unawaited(_save());
  }

  void resetResults() {
    if (_results.isEmpty && _notes.isEmpty) return;
    _results.clear();
    _notes.clear();
    _changed();
  }

  String buildReport({required DateTime now}) {
    final FeatureTestSummary total = summary;
    final StringBuffer report = StringBuffer()
      ..writeln(_reportTitle)
      ..writeln('Tarih: ${DateFormatter.formatNumericDateTime(now)}')
      ..writeln('Cihaz: ${featureTestPlatformLabel(platform)}')
      ..writeln(_onlyThisDevice
          ? 'Kapsam: Yalnızca bu cihaza uygun adımlar'
          : 'Kapsam: Bütün adımlar')
      ..writeln('Sonuç: ${total.total} adımdan ${total.done} tanesi test edildi'
          ' — ${total.passed} geçti, ${total.failed} hatalı, '
          '${total.skipped} atlandı, ${total.open} yapılmadı');

    final List<String> failures = [];
    final List<String> notes = [];
    for (final FeatureTestSection section in sections) {
      final List<FeatureTestStep> steps = stepsOf(section);
      for (int i = 0; i < steps.length; i++) {
        final FeatureTestStep step = steps[i];
        if (!isInScope(step)) continue;
        final FeatureTestResult? result = _results[step.id];
        final String? note = _notes[step.id];
        final String title = '${section.title} › ${i + 1}. ${step.action}';
        if (result == FeatureTestResult.failed) {
          final StringBuffer entry = StringBuffer(title);
          if (step.expected.isNotEmpty) {
            entry.write('\n   Beklenen: ${step.expected}');
          }
          if (note != null) entry.write('\n   Not: $note');
          failures.add(entry.toString());
        } else if (note != null) {
          notes.add('$title [${result?.label ?? FeatureTestFilter.open.label}]'
              '\n   Not: $note');
        }
      }
    }

    if (failures.isNotEmpty) {
      report
        ..writeln()
        ..writeln('HATALI ADIMLAR (${failures.length})');
      for (int i = 0; i < failures.length; i++) {
        report.writeln('${i + 1}) ${failures[i]}');
      }
    }
    if (notes.isNotEmpty) {
      report
        ..writeln()
        ..writeln('NOTLAR (${notes.length})');
      for (final String note in notes) {
        report.writeln('- $note');
      }
    }

    report
      ..writeln()
      ..writeln('BÖLÜMLER');
    for (final FeatureTestSection section in sections) {
      final FeatureTestSummary s = summaryOf(stepsOf(section));
      if (s.total == 0) continue;
      final List<String> parts = [
        if (s.passed > 0) '${s.passed} geçti',
        if (s.failed > 0) '${s.failed} hatalı',
        if (s.skipped > 0) '${s.skipped} atlandı',
        if (s.open > 0) '${s.open} yapılmadı',
      ];
      report.writeln(
          '- ${section.title}: ${s.done}/${s.total} (${parts.join(', ')})');
    }
    return report.toString().trimRight();
  }
}
