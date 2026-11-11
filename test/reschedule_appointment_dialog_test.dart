import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/dialogs/reschedule_appointment_dialog.dart';
import 'package:ngy_app/models/appointment_model.dart';
import 'package:ngy_app/models/filter_params.dart';
import 'package:ngy_app/models/subs_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/sub_provider.dart';
import 'package:ngy_app/widgets/inline_note.dart';
import 'package:provider/provider.dart';

const String _title = 'Randevuyu Taşı';
const String _deductOption = 'Evet, erteleme hakkından düş';
const String _moveOnlyOption = 'Hayır, yalnızca tarihi ve saati değiştir';
const String _rightQuestion = 'Danışanın erteleme hakkından düşülsün mü?';
const String _cancel = 'Vazgeç';

class _FakeSubProvider extends SubProvider {
  _FakeSubProvider(this.subscriptions, {this.fails = false});

  final List<SubscriptionModel> subscriptions;
  final bool fails;
  int fetches = 0;

  @override
  Future<List<SubscriptionModel>> fetchSubscriptions({
    required String userId,
    required bool showAllSubscriptions,
    SubscriptionFilterParams? filterParams,
  }) async {
    fetches++;
    if (fails) throw StateError('okunamadı');
    return subscriptions;
  }
}

SubscriptionModel _subscription(String id,
        {required int allowed, required int used}) =>
    SubscriptionModel(
      subscriptionId: id,
      userId: 'u1',
      packageName: 'Paket $id',
      startDate: DateTime(2026, 10, 1),
      totalMeetings: 8,
      allowedPostponements: allowed,
      postponementsUsed: used,
      totalAmount: 1000,
      meetingType: SubsMeetingType.online,
    );

final DateTime _current = DateTime(2026, 11, 9, 9);
final DateTime _newStart = DateTime(2026, 11, 11, 10, 20);

AppointmentModel _appointment({
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? postponedDate,
  PostponeSource? postponedBy,
  String? subscriptionId = 's1',
}) =>
    AppointmentModel(
      appointmentId: 'a1',
      userId: 'u1',
      user: UserModel(
        userId: 'u1',
        name: 'Ayşe',
        surname: 'Yılmaz',
        email: 'u1@test.com',
        password: '',
        role: 'customer',
        dosyaNo: '1021',
      ),
      subscriptionId: subscriptionId,
      meetingType: MeetingType.f2f,
      appointmentType: AppointmentType.haftalik,
      appointmentDateTime: _current,
      status: status,
      createDate: DateTime(2026, 11, 1),
      postponedDate: postponedDate,
      postponedBy: postponedBy,
      durationMinutes: 30,
    );

class _Outcome {
  bool answered = false;
  bool? deductRight;
}

Future<_Outcome> _open(
  WidgetTester tester,
  AppointmentModel appointment, {
  List<SubscriptionModel> subscriptions = const <SubscriptionModel>[],
  bool subscriptionsFail = false,
}) async {
  final _Outcome outcome = _Outcome();
  await tester.pumpWidget(
    ChangeNotifierProvider<SubProvider>(
      create: (_) => _FakeSubProvider(subscriptions, fails: subscriptionsFail),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async {
                final bool? result = await showRescheduleAppointmentDialog(
                  context,
                  appointment: appointment,
                  newStart: _newStart,
                );
                outcome
                  ..answered = true
                  ..deductRight = result;
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
  return outcome;
}

FilledButton _confirmButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, _title));

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, _title));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String option) async {
  await tester.ensureVisible(find.text(option));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option));
  await tester.pump();
}

Future<void> _cancelDialog(WidgetTester tester) async {
  await tester.tap(find.text(_cancel));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('danışanı, mevcut ve yeni tarih-saati gösterir, taşımayı sorar',
      (WidgetTester tester) async {
    await _open(tester, _appointment());

    expect(find.text('1021-Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('Haftalık Görüşme • Yüz yüze • 30 dk'), findsOneWidget);
    expect(find.text('MEVCUT'), findsOneWidget);
    expect(find.text('9 Kasım 2026 Pazartesi'), findsOneWidget);
    expect(find.text('09:00 – 09:30'), findsOneWidget);
    expect(find.text('YENİ'), findsOneWidget);
    expect(find.text('11 Kasım 2026 Çarşamba'), findsOneWidget);
    expect(find.text('10:20 – 10:50'), findsOneWidget);
    expect(
        find.text('Randevu yeni tarih ve saate taşınsın mı?'), findsOneWidget);
    expect(find.text(_rightQuestion), findsOneWidget);
  });

  testWidgets('ertelenmiş randevuda mevcut tarih ertelendiği tarihtir',
      (WidgetTester tester) async {
    await _open(
      tester,
      _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: DateTime(2026, 11, 10, 15, 40),
        postponedBy: PostponeSource.admin,
      ),
    );

    expect(find.text('10 Kasım 2026 Salı'), findsOneWidget);
    expect(find.text('15:40 – 16:10'), findsOneWidget);
    expect(find.text('9 Kasım 2026 Pazartesi'), findsNothing);
  });

  testWidgets('seçim yapılmadan onaylanamaz; "Evet" seçilince true döner',
      (WidgetTester tester) async {
    final _Outcome outcome = await _open(tester, _appointment(),
        subscriptions: [_subscription('s1', allowed: 3, used: 1)]);

    expect(_confirmButton(tester).onPressed, isNull);
    expect(find.byType(RadioListTile<bool>), findsNWidgets(2));

    await _choose(tester, _deductOption);
    expect(_confirmButton(tester).onPressed, isNotNull);
    await _confirm(tester);

    expect(outcome.answered, isTrue);
    expect(outcome.deductRight, isTrue);
    expect(find.text(_title), findsNothing);
  });

  testWidgets('"Hayır" seçilince false döner', (WidgetTester tester) async {
    final _Outcome outcome = await _open(tester, _appointment(),
        subscriptions: [_subscription('s1', allowed: 3, used: 1)]);

    await _choose(tester, _moveOnlyOption);
    await _confirm(tester);

    expect(outcome.answered, isTrue);
    expect(outcome.deductRight, isFalse);
  });

  testWidgets('seçim değiştirilebilir: son seçilen geçerlidir',
      (WidgetTester tester) async {
    final _Outcome outcome = await _open(tester, _appointment(),
        subscriptions: [_subscription('s1', allowed: 3, used: 1)]);

    await _choose(tester, _deductOption);
    await _choose(tester, _moveOnlyOption);
    await _confirm(tester);

    expect(outcome.deductRight, isFalse);
  });

  testWidgets('"Vazgeç" null döner: randevu taşınmaz',
      (WidgetTester tester) async {
    final _Outcome outcome = await _open(tester, _appointment());

    await _choose(tester, _deductOption);
    await _cancelDialog(tester);

    expect(outcome.answered, isTrue);
    expect(outcome.deductRight, isNull);
  });

  testWidgets('diyaloğun dışına dokunmak da vazgeçmektir',
      (WidgetTester tester) async {
    final _Outcome outcome = await _open(tester, _appointment());

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(outcome.answered, isTrue);
    expect(outcome.deductRight, isNull);
  });

  testWidgets('randevunun paketindeki kalan erteleme hakkını gösterir',
      (WidgetTester tester) async {
    await _open(tester, _appointment(), subscriptions: [
      _subscription('baska', allowed: 9, used: 0),
      _subscription('s1', allowed: 3, used: 1),
    ]);

    expect(find.text('Kalan erteleme hakkı: 2'), findsOneWidget);
  });

  testWidgets('paket okunamazsa bunu söyler, taşımayı engellemez',
      (WidgetTester tester) async {
    final _Outcome outcome =
        await _open(tester, _appointment(), subscriptionsFail: true);

    expect(find.text('Kalan erteleme hakkı okunamadı.'), findsOneWidget);
    await _choose(tester, _deductOption);
    await _confirm(tester);
    expect(outcome.deductRight, isTrue);
  });

  testWidgets('paketsiz randevuda düşülecek hak olmadığını söyler',
      (WidgetTester tester) async {
    for (final String? subscriptionId in <String?>[null, '']) {
      final _Outcome outcome =
          await _open(tester, _appointment(subscriptionId: subscriptionId));

      expect(
          find.text(
              'Randevu bir pakete bağlı değil; düşülecek erteleme hakkı yok.'),
          findsOneWidget);
      await _choose(tester, _deductOption);
      await _confirm(tester);
      expect(outcome.deductRight, isTrue);
    }
  });

  testWidgets(
      'hak kalmadıysa "Evet" onaylanmadan önce uyarılır; uyarı '
      'reddedilirse diyalog açık kalır', (WidgetTester tester) async {
    final _Outcome outcome = await _open(tester, _appointment(),
        subscriptions: [_subscription('s1', allowed: 2, used: 2)]);

    expect(find.text('Kalan erteleme hakkı: 0'), findsOneWidget);
    await _choose(tester, _deductOption);
    await _confirm(tester);

    expect(find.text('Evet'), findsOneWidget);
    await tester.tap(find.text('Hayır'));
    await tester.pumpAndSettle();
    expect(outcome.answered, isFalse);
    expect(find.text(_rightQuestion), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNotNull);

    await _confirm(tester);
    await tester.tap(find.text('Evet'));
    await tester.pumpAndSettle();
    expect(outcome.answered, isTrue);
    expect(outcome.deductRight, isTrue);
  });

  testWidgets('hak kalmadıysa "Hayır" seçimi uyarısız onaylanır',
      (WidgetTester tester) async {
    final _Outcome outcome = await _open(tester, _appointment(),
        subscriptions: [_subscription('s1', allowed: 2, used: 2)]);

    await _choose(tester, _moveOnlyOption);
    await _confirm(tester);

    expect(outcome.deductRight, isFalse);
  });

  testWidgets(
      'hakkı daha önce düşülmüş randevuda soru sorulmaz; yeniden '
      'düşülmeyeceği yazar ve false döner', (WidgetTester tester) async {
    final _Outcome outcome = await _open(
      tester,
      _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: DateTime(2026, 11, 10, 15, 40),
        postponedBy: PostponeSource.user,
      ),
      subscriptions: [_subscription('s1', allowed: 2, used: 2)],
    );

    expect(find.text(_rightQuestion), findsNothing);
    expect(find.byType(RadioListTile<bool>), findsNothing);
    expect(find.byType(InlineNote), findsOneWidget);
    expect(find.textContaining('yeniden düşülmez'), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNotNull);

    await _confirm(tester);
    expect(outcome.answered, isTrue);
    expect(outcome.deductRight, isFalse);
  });

  testWidgets('seçeneklerin açıklaması randevunun durumuna göre yazılır',
      (WidgetTester tester) async {
    await _open(tester, _appointment());
    expect(
        find.text('Randevu “Ertelendi” olur; erteleme kaynağı “Danışan '
            'Kaynaklı” seçilir.'),
        findsOneWidget);
    expect(find.text('Randevu “Planlandı” olarak kalır; erteleme sayılmaz.'),
        findsOneWidget);
    await _cancelDialog(tester);

    await _open(
      tester,
      _appointment(
        status: AppointmentStatus.postponed,
        postponedDate: DateTime(2026, 11, 10, 15, 40),
        postponedBy: PostponeSource.admin,
      ),
    );
    expect(
        find.text('Erteleme kaynağı “Danışan Kaynaklı” olur.'), findsOneWidget);
    expect(
        find.text(
            'Randevu “Ertelendi” olarak kalır; erteleme kaynağı değişmez.'),
        findsOneWidget);
  });

  for (final Size size in const <Size>[Size(320, 568), Size(390, 844)]) {
    testWidgets('telefonda taşmaz (${size.width.toInt()} px)',
        (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _open(tester, _appointment(),
          subscriptions: [_subscription('s1', allowed: 2, used: 2)]);

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, _title), findsOneWidget);
    });
  }
}
