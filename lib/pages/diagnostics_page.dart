// pages/diagnostics_page.dart

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/appointment_model.dart';
import '../models/logger.dart';
import '../models/payment_model.dart';
import '../models/user_model.dart';
import '../providers/appointment_manager.dart';
import '../providers/payment_provider.dart';
import '../providers/user_provider.dart';
import '../utils/date_input_utils.dart';

/// Self-test / diagnostics screen for the features added recently:
/// bulk appointment & payment creation and the new `dosyaNo` user field.
///
/// It runs a suite of automated checks against a real customer, creating
/// temporary data through the same providers the app uses, verifying the
/// results, and then cleaning everything up so no test data is left behind.
class DiagnosticsPage extends StatefulWidget {
  final UserModel user;

  const DiagnosticsPage({super.key, required this.user});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final Logger logger = Logger.forClass(DiagnosticsPage);
  final List<_TestResult> _results = [];
  final Random _rnd = Random();
  bool _running = false;
  String? _currentStep;

  int get _passed => _results.where((r) => r.passed).length;

  /// Throws with [message] when [condition] is false. Used inside tests to
  /// assert expectations without a test framework.
  void _expect(bool condition, String message) {
    if (!condition) throw Exception(message);
  }

  Future<void> _runTest(String name, Future<String> Function() body) async {
    setState(() => _currentStep = name);
    try {
      final detail = await body();
      _results.add(_TestResult(name, true, detail));
    } catch (e) {
      logger.err('Diagnostic "{}" failed: {}', [name, e]);
      _results.add(_TestResult(name, false, e.toString()));
    }
    if (mounted) setState(() {});
  }

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _results.clear();
      _currentStep = null;
    });

    await _testDateParsingValid();
    await _testDateParsingInvalidDay();
    await _testDateParsingIncomplete();
    await _testDateMaskFormatting();
    await _testMeetingTypeDefaults();
    await _testDosyaNoSerialization();
    await _testBulkAppointments();
    await _testBulkPayments();
    await _testDosyaNoPersistence();

    if (mounted) {
      setState(() {
        _running = false;
        _currentStep = null;
      });
    }
  }

  // ---------------------- Pure logic tests ----------------------

  Future<void> _testDateParsingValid() async {
    await _runTest('Tarih ayrıştırma – geçerli (15.06.2025)', () async {
      final d = parseDayMonthYear('15.06.2025');
      _expect(
        d != null && d.day == 15 && d.month == 6 && d.year == 2025,
        'Beklenen 15.06.2025, alınan: $d',
      );
      return 'Tarih doğru ayrıştırıldı.';
    });
  }

  Future<void> _testDateParsingInvalidDay() async {
    await _runTest('Tarih ayrıştırma – geçersiz gün (31.02.2024)', () async {
      final d = parseDayMonthYear('31.02.2024');
      _expect(d == null, 'Geçersiz tarih null dönmeliydi, alınan: $d');
      return 'Geçersiz takvim tarihi doğru şekilde reddedildi.';
    });
  }

  Future<void> _testDateParsingIncomplete() async {
    await _runTest('Tarih ayrıştırma – eksik (1.1)', () async {
      final d = parseDayMonthYear('1.1');
      _expect(d == null, 'Eksik tarih null dönmeliydi, alınan: $d');
      return 'Eksik tarih doğru şekilde reddedildi.';
    });
  }

  Future<void> _testDateMaskFormatting() async {
    await _runTest('Tarih maskesi (nokta ekleme)', () async {
      final dotted = DateInputFormatter.format('15062025', '.');
      _expect(dotted == '15.06.2025', '"15.06.2025" bekleniyordu, alınan: $dotted');
      final partial = DateInputFormatter.format('1506', '.');
      _expect(partial == '15.06', '"15.06" bekleniyordu, alınan: $partial');
      final capped = DateInputFormatter.format('150620259999', '.');
      _expect(capped == '15.06.2025', '8 haneye kırpılmalıydı, alınan: $capped');
      return 'Noktalar otomatik olarak doğru eklendi.';
    });
  }

  Future<void> _testMeetingTypeDefaults() async {
    await _runTest('Görüşme türü etiketleri (f2f / online)', () async {
      _expect(MeetingType.f2f.label == 'Yüz yüze',
          'f2f etiketi beklenenden farklı: ${MeetingType.f2f.label}');
      _expect(MeetingType.online.label == 'Online',
          'online etiketi beklenenden farklı: ${MeetingType.online.label}');
      return 'Görüşme türü etiketleri doğru.';
    });
  }

  Future<void> _testDosyaNoSerialization() async {
    await _runTest('Dosya NO model serileştirme (toMap)', () async {
      final withDosya = _sampleUser('DN-9999');
      final map1 = withDosya.toMap();
      _expect(map1['dosyaNo'] == 'DN-9999',
          'toMap dosyaNo içermiyor: ${map1['dosyaNo']}');

      final withoutDosya = _sampleUser(null);
      final map2 = withoutDosya.toMap();
      _expect(!map2.containsKey('dosyaNo'),
          'dosyaNo null iken map içinde bulunmamalı.');

      return 'toMap, dosyaNo alanını doğru işliyor (dolu/boş).';
    });
  }

  // ---------------------- Firestore-backed tests ----------------------

  Future<void> _testBulkAppointments() async {
    await _runTest('Toplu randevu ekleme + doğrulama + temizlik (3 adet)',
        () async {
      final manager =
          Provider.of<AppointmentManager>(context, listen: false);
      final userId = widget.user.userId;
      final prefix = 'diagtest_${DateTime.now().millisecondsSinceEpoch}';

      final createdIds = <String>[];
      final expectedType = <String, MeetingType>{};
      for (int i = 0; i < 3; i++) {
        final id = '${prefix}_$i';
        final mt = _rnd.nextBool() ? MeetingType.f2f : MeetingType.online;
        final date =
            DateTime.now().subtract(Duration(days: _rnd.nextInt(300)));
        await manager.addAppointment(
          AppointmentModel(
            appointmentId: id,
            userId: userId,
            subscriptionId: null,
            meetingType: mt,
            appointmentType: AppointmentType.haftalik,
            appointmentDateTime: DateTime(date.year, date.month, date.day, 0, 0),
            status: AppointmentStatus.completed,
            createDate: DateTime.now(),
            createUser: 'diagnostic',
            durationMinutes: 30,
          ),
        );
        createdIds.add(id);
        expectedType[id] = mt;
      }

      final all = await manager.fetchAppointments(null,
          showAllAppointments: true, userId: userId);
      final ours =
          all.where((a) => a.appointmentId.startsWith(prefix)).toList();
      _expect(ours.length == 3,
          '3 randevu bekleniyordu, ${ours.length} bulundu.');
      for (final a in ours) {
        _expect(a.appointmentType == AppointmentType.haftalik,
            'Randevu türü Haftalık değil: ${a.appointmentType.lbl}');
        _expect(a.status == AppointmentStatus.completed,
            'Durum "Yapıldı" değil: ${a.status.label}');
        _expect(a.durationMinutes == 30,
            'Süre 30 dk değil: ${a.durationMinutes}');
        _expect(a.appointmentDateTime.hour == 0 &&
            a.appointmentDateTime.minute == 0, 'Saat 00:00 değil.');
        _expect(a.subscriptionId == null, 'Abonelik boş (null) olmalıydı.');
        _expect(a.meetingType == expectedType[a.appointmentId],
            'Görüşme türü eşleşmiyor.');
      }

      int deleted = 0;
      for (final id in createdIds) {
        final ok = await manager.deleteAppointment(id, userId,
            deletedBy: 'diagnostic');
        if (ok) deleted++;
      }
      _expect(deleted == 3, 'Temizlik: 3 silinmeliydi, $deleted silindi.');

      final after = await manager.fetchAppointments(null,
          showAllAppointments: true, userId: userId);
      final remaining =
          after.where((a) => a.appointmentId.startsWith(prefix)).length;
      _expect(remaining == 0,
          'Silme sonrası $remaining test randevusu kaldı.');

      return '3 randevu eklendi, tüm sabit alanlar doğrulandı ve temizlendi.';
    });
  }

  Future<void> _testBulkPayments() async {
    await _runTest('Toplu ödeme ekleme + doğrulama + temizlik (3 adet)',
        () async {
      final provider = Provider.of<PaymentProvider>(context, listen: false);
      final userId = widget.user.userId;
      final marker = 'DIAGTEST_${DateTime.now().millisecondsSinceEpoch}';

      final expectedAmounts = <double>[];
      for (int i = 0; i < 3; i++) {
        final amount = (_rnd.nextInt(900) + 100).toDouble();
        final date =
            DateTime.now().subtract(Duration(days: _rnd.nextInt(300)));
        await provider.addPayment(
          userId: userId,
          subscription: null,
          amount: amount,
          paymentDate: DateTime(date.year, date.month, date.day),
          status: PaymentStatus.completed,
          paymentType: PaymentType.nakit,
          notes: marker,
        );
        expectedAmounts.add(amount);
      }

      final all = await provider.fetchPayments(null,
          userId: userId, showAllPayments: true);
      final ours = all.where((p) => p.notes == marker).toList();
      _expect(
          ours.length == 3, '3 ödeme bekleniyordu, ${ours.length} bulundu.');
      for (final p in ours) {
        _expect(p.status == PaymentStatus.completed,
            'Durum "Tamamlandı" değil: ${p.status.label}');
        _expect(p.paymentType == PaymentType.nakit,
            'Ödeme türü "Nakit" değil: ${p.paymentType.label}');
        _expect(p.subscriptionId == null, 'Abonelik boş (null) olmalıydı.');
        _expect(p.paymentDate != null, 'Ödeme tarihi boş (null).');
      }

      final gotAmounts = ours.map((p) => p.amount).toList()..sort();
      final expAmounts = [...expectedAmounts]..sort();
      _expect(_doubleListEquals(gotAmounts, expAmounts),
          'Tutarlar eşleşmiyor: $gotAmounts vs $expAmounts');

      for (final p in ours) {
        await provider.deletePayment(p.paymentId, userId);
      }
      final after = await provider.fetchPayments(null,
          userId: userId, showAllPayments: true);
      final remaining = after.where((p) => p.notes == marker).length;
      _expect(remaining == 0, 'Silme sonrası $remaining test ödemesi kaldı.');

      return '3 ödeme (Nakit/Tamamlandı) eklendi, doğrulandı ve temizlendi.';
    });
  }

  Future<void> _testDosyaNoPersistence() async {
    await _runTest('Dosya NO kaydetme/güncelleme (gerçek kayıt)', () async {
      final provider = Provider.of<UserProvider>(context, listen: false);
      final userId = widget.user.userId;

      final original = await provider.fetchUserDetails(userId: userId);
      _expect(original != null, 'Kullanıcı bulunamadı.');
      final originalDosya = original!.dosyaNo;

      final testValue = 'DN-${DateTime.now().millisecondsSinceEpoch % 1000000}';
      await provider
          .updateUserDetails(_copyWithDosya(original, testValue));

      final afterSet = await provider.fetchUserDetails(userId: userId);
      _expect(afterSet?.dosyaNo == testValue,
          'Dosya NO kaydedilemedi: ${afterSet?.dosyaNo}');

      // Restore original value (empty string is functionally equal to null in
      // the UI, so a previously-empty field stays visually unchanged).
      await provider
          .updateUserDetails(_copyWithDosya(original, originalDosya ?? ''));
      final restored = await provider.fetchUserDetails(userId: userId);
      _expect((restored?.dosyaNo ?? '') == (originalDosya ?? ''),
          'Dosya NO eski değerine döndürülemedi: ${restored?.dosyaNo}');

      return 'Dosya NO "$testValue" olarak kaydedildi, doğrulandı ve '
          'eski haline getirildi.';
    });
  }

  // ---------------------- Helpers ----------------------

  bool _doubleListEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.001) return false;
    }
    return true;
  }

  UserModel _copyWithDosya(UserModel u, String? dosyaNo) {
    return UserModel(
      userId: u.userId,
      name: u.name,
      email: u.email,
      password: u.password,
      role: u.role,
      createDate: u.createDate,
      createUser: u.createUser,
      updateDate: DateTime.now(),
      updateUser: 'diagnostic',
      surname: u.surname,
      age: u.age,
      reference: u.reference,
      notes: u.notes,
      dosyaNo: dosyaNo,
    );
  }

  UserModel _sampleUser(String? dosyaNo) {
    return UserModel(
      userId: 'diag_sample',
      name: 'Test',
      email: 'test@example.com',
      password: '',
      role: 'customer',
      surname: 'Kullanıcı',
      dosyaNo: dosyaNo,
    );
  }

  // ---------------------- Build ----------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test / Doğrulama'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber.shade50,
            padding: const EdgeInsets.all(12),
            child: Text(
              'Bu ekran, bu kullanıcı (${widget.user.name} '
              '${widget.user.surname}) üzerinde geçici test verileri oluşturup '
              'doğrular ve ardından otomatik olarak siler. Sabit alanlar, '
              'toplu ekleme ve Dosya NO alanı test edilir.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _running ? null : _runAll,
                    icon: _running
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_running ? 'Çalışıyor...' : 'Testleri Çalıştır'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_results.isNotEmpty || _running)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    'Sonuç: $_passed / ${_results.length} başarılı',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _results.isNotEmpty && _passed == _results.length
                          ? Colors.green.shade700
                          : (_running ? Colors.grey : Colors.red.shade700),
                    ),
                  ),
                  const Spacer(),
                  if (_running && _currentStep != null)
                    Expanded(
                      child: Text(
                        _currentStep!,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _running
                          ? 'Testler çalışıyor...'
                          : 'Testleri başlatmak için yukarıdaki butona basın.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final r = _results[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            r.passed ? Icons.check_circle : Icons.cancel,
                            color: r.passed ? Colors.green : Colors.red,
                          ),
                          title: Text(
                            r.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            r.detail,
                            style: TextStyle(
                              fontSize: 12,
                              color: r.passed
                                  ? Colors.grey.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TestResult {
  final String name;
  final bool passed;
  final String detail;

  _TestResult(this.name, this.passed, this.detail);
}
