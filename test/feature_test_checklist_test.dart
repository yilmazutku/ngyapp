import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/models/feature_test_checklist.dart';
import 'package:ngy_app/models/feature_test_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  const List<FeatureTestSection> sections = [
    FeatureTestSection(
      id: 'a',
      title: 'Bölüm A',
      icon: Icons.star,
      color: Colors.red,
      steps: [
        FeatureTestStep('a.1', 'Birinci', 'Olur'),
        FeatureTestStep(
          'a.2',
          'Windows adımı',
          'Gider',
          platforms: {TargetPlatform.windows},
        ),
      ],
    ),
    FeatureTestSection(
      id: 'b',
      title: 'Bölüm B',
      icon: Icons.star,
      color: Colors.blue,
      steps: [FeatureTestStep('b.1', 'Üçüncü', 'Çıkar')],
    ),
  ];

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FeatureTestChecklist> loaded({
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    final FeatureTestChecklist checklist =
        FeatureTestChecklist(platform: platform, sections: sections);
    addTearDown(checklist.dispose);
    await checklist.load();
    return checklist;
  }

  test('eski sürümün işaretleri "geçti" olarak taşınır', () async {
    SharedPreferences.setMockInitialValues({
      FeatureTestChecklist.legacyStorageKey: ['a.1', 'b.1'],
    });
    final FeatureTestChecklist checklist = await loaded();
    expect(checklist.resultOf('a.1'), FeatureTestResult.passed);
    expect(checklist.resultOf('b.1'), FeatureTestResult.passed);
    expect(checklist.summary.passed, 2);

    checklist.setResult('a.2', FeatureTestResult.failed);
    await pumpEventQueue();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(FeatureTestChecklist.legacyStorageKey), isFalse);
    expect(prefs.getString(FeatureTestChecklist.storageKey), isNotNull);
  });

  test('aynı sonuç ikinci kez seçilince işaret kalkar', () async {
    final FeatureTestChecklist checklist = await loaded();
    checklist.setResult('a.1', FeatureTestResult.passed);
    expect(checklist.resultOf('a.1'), FeatureTestResult.passed);
    checklist.setResult('a.1', FeatureTestResult.passed);
    expect(checklist.resultOf('a.1'), isNull);
    checklist.setResult('a.1', FeatureTestResult.skipped);
    checklist.setResult('a.1', FeatureTestResult.failed);
    expect(checklist.resultOf('a.1'), FeatureTestResult.failed);
  });

  test('sonuçlar, notlar, eklenen adımlar ve ayarlar geri yüklenir', () async {
    final FeatureTestChecklist first = FeatureTestChecklist(
        platform: TargetPlatform.android, sections: sections);
    await first.load();
    first.setResult('a.1', FeatureTestResult.failed);
    first.setNote('a.1', '  Bildirim gelmedi  ');
    final String id = first.addCustomStep(
      sectionId: 'b',
      action: 'Kendi adımım',
      expected: 'Çalışır',
    );
    first.setResult(id, FeatureTestResult.skipped);
    first.filter = FeatureTestFilter.failed;
    first.onlyThisDevice = true;
    first.toggleCollapsed('b');
    first.setSetting('simulator.kind', 'bloodTestDueDay');
    await pumpEventQueue();
    first.dispose();

    final FeatureTestChecklist restored = await loaded();
    expect(restored.resultOf('a.1'), FeatureTestResult.failed);
    expect(restored.noteOf('a.1'), 'Bildirim gelmedi');
    expect(restored.stepsOf(sections[1]).map((s) => s.action),
        ['Üçüncü', 'Kendi adımım']);
    expect(restored.stepsOf(sections[1]).last.isCustom, isTrue);
    expect(restored.resultOf(id), FeatureTestResult.skipped);
    expect(restored.filter, FeatureTestFilter.failed);
    expect(restored.onlyThisDevice, isTrue);
    expect(restored.isCollapsed('b'), isTrue);
    expect(restored.isCollapsed('a'), isFalse);
    expect(restored.setting('simulator.kind'), 'bloodTestDueDay');
  });

  test('bozuk kayıt sayfayı bozmaz', () async {
    SharedPreferences.setMockInitialValues({
      FeatureTestChecklist.storageKey: '{bozuk',
    });
    final FeatureTestChecklist checklist = await loaded();
    expect(checklist.isLoaded, isTrue);
    expect(checklist.summary.done, 0);
  });

  test('filtre ve cihaz kapsamı görünen adımları ve sayıları belirler',
      () async {
    final FeatureTestChecklist checklist = await loaded();
    checklist.setResult('a.1', FeatureTestResult.failed);
    expect(
        checklist.visibleStepsOf(sections[0]).map((s) => s.id), ['a.1', 'a.2']);
    expect(checklist.summary.total, 3);

    checklist.onlyThisDevice = true;
    expect(checklist.visibleStepsOf(sections[0]).map((s) => s.id), ['a.1']);
    expect(checklist.summary.total, 2);

    checklist.filter = FeatureTestFilter.open;
    expect(checklist.visibleStepsOf(sections[0]), isEmpty);
    expect(checklist.visibleStepsOf(sections[1]).map((s) => s.id), ['b.1']);

    checklist.filter = FeatureTestFilter.failed;
    expect(checklist.visibleStepsOf(sections[0]).map((s) => s.id), ['a.1']);
    expect(checklist.visibleStepsOf(sections[1]), isEmpty);
  });

  test('eklenen adım düzenlenir; silinince sonucu ve notu da gider', () async {
    final FeatureTestChecklist checklist = await loaded();
    final String id = checklist.addCustomStep(
      sectionId: 'a',
      action: 'İlk hâli',
      expected: '',
    );
    checklist.updateCustomStep(
      stepId: id,
      action: 'Son hâli',
      expected: 'Beklenen',
    );
    expect(checklist.stepsOf(sections[0]).last.action, 'Son hâli');
    expect(checklist.stepsOf(sections[0]).last.expected, 'Beklenen');

    checklist.setResult(id, FeatureTestResult.failed);
    checklist.setNote(id, 'Not');
    checklist.removeCustomStep(id);
    expect(checklist.stepsOf(sections[0]).map((s) => s.id), ['a.1', 'a.2']);
    expect(checklist.resultOf(id), isNull);
    expect(checklist.noteOf(id), isNull);
  });

  test('sıfırlama sonuçları ve notları siler, eklenen adımları bırakır',
      () async {
    final FeatureTestChecklist checklist = await loaded();
    final String id = checklist.addCustomStep(
      sectionId: 'b',
      action: 'Kalıcı adım',
      expected: '',
    );
    checklist.setResult('a.1', FeatureTestResult.passed);
    checklist.setNote('b.1', 'Not');
    checklist.resetResults();
    expect(checklist.summary.done, 0);
    expect(checklist.noteOf('b.1'), isNull);
    expect(checklist.stepsOf(sections[1]).map((s) => s.id), ['b.1', id]);
  });

  test('rapor hatalı adımları notlarıyla, bölümleri özetiyle verir', () async {
    final FeatureTestChecklist checklist =
        await loaded(platform: TargetPlatform.windows);
    checklist.setResult('a.1', FeatureTestResult.passed);
    checklist.setNote('a.1', 'Sorunsuz');
    checklist.setResult('a.2', FeatureTestResult.failed);
    checklist.setNote('a.2', 'Enter yeni satır açtı');

    final String report =
        checklist.buildReport(now: DateTime(2026, 11, 6, 21, 30));
    expect(report, contains('Tarih: 06.11.2026 21:30'));
    expect(report, contains('Cihaz: Windows'));
    expect(report, contains('Kapsam: Bütün adımlar'));
    expect(
        report,
        contains('Sonuç: 3 adımdan 2 tanesi test edildi — 1 geçti, '
            '1 hatalı, 0 atlandı, 1 yapılmadı'));
    expect(
        report,
        contains('HATALI ADIMLAR (1)\n'
            '1) Bölüm A › 2. Windows adımı\n'
            '   Beklenen: Gider\n'
            '   Not: Enter yeni satır açtı'));
    expect(
        report,
        contains('NOTLAR (1)\n'
            '- Bölüm A › 1. Birinci [Geçti]\n'
            '   Not: Sorunsuz'));
    expect(report, contains('- Bölüm A: 2/2 (1 geçti, 1 hatalı)'));
    expect(report, endsWith('- Bölüm B: 0/1 (1 yapılmadı)'));
  });

  test('hızlandırma: simüle edilen süre seçilen hızla gerçek zamana çevrilir',
      () {
    final DateTime start = DateTime(2026, 11, 7, 12);
    expect(
        FeatureTestSpeed.dayInMinute
            .realTimeOf(start.add(const Duration(days: 3)), start),
        start.add(const Duration(minutes: 3)));
    expect(
        FeatureTestSpeed.dayInTenSeconds
            .realTimeOf(start.add(const Duration(days: 1)), start),
        start.add(const Duration(seconds: 10)));
    expect(
        FeatureTestSpeed.realTime
            .realTimeOf(start.add(const Duration(days: 2)), start),
        start.add(const Duration(days: 2)));
    expect(
        FeatureTestSpeed.dayInMinute
            .realTimeOf(start.subtract(const Duration(days: 2)), start),
        start,
        reason: 'geçmişte kalan an hemen düşer');
  });
}
