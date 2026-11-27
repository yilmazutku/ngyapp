import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/dialogs/edit_appointment_dialog.dart';
import 'package:ngy_app/models/appointment_duration_config.dart';
import 'package:ngy_app/models/appointment_model.dart';
import 'package:ngy_app/models/filter_params.dart';
import 'package:ngy_app/models/subs_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/providers/appointment_durations_provider.dart';
import 'package:ngy_app/providers/appointment_manager.dart';
import 'package:ngy_app/providers/sub_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:provider/provider.dart';

const String _repostponeTitle = 'TEKRAR ERTELEME';
const String _repostponeOption = 'Evet, tekrar erteleme: erteleme hakkından düş';
const String _dateOnlyOption = 'Hayır, yalnızca tarihi değiştir';

class _FakeSubProvider extends SubProvider {
  _FakeSubProvider({required this.used});

  final int used;
  final List<({String subscriptionId, int delta})> adjustments = [];

  @override
  Future<List<SubscriptionModel>> fetchSubscriptions({
    required String userId,
    required bool showAllSubscriptions,
    SubscriptionFilterParams? filterParams,
  }) async {
    return <SubscriptionModel>[
      SubscriptionModel(
        subscriptionId: 's1',
        userId: 'u1',
        packageName: 'Paket s1',
        startDate: DateTime(2026, 10, 1),
        totalMeetings: 12,
        allowedPostponements: 3,
        postponementsUsed: used,
        totalAmount: 1000,
        meetingType: SubsMeetingType.faceToFace,
      ),
    ];
  }

  @override
  Future<bool> adjustPostponementsUsed({
    required String userId,
    required String subscriptionId,
    required int delta,
    String updateUser = 'admin',
  }) async {
    adjustments.add((subscriptionId: subscriptionId, delta: delta));
    return true;
  }
}

class _FakeUserProvider extends UserProvider {
  @override
  Future<UserModel?> fetchUserDetails({required String userId}) async => null;
}

class _FakeDurationsProvider extends ChangeNotifier
    implements AppointmentDurationsProvider {
  @override
  Future<Map<AppointmentDurationSlot, int>> fetchDurations(
          {bool force = false}) async =>
      <AppointmentDurationSlot, int>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAppointmentManager extends AppointmentManager {
  _RecordingAppointmentManager(SubProvider subs) : super(subProvider: subs);

  final List<AppointmentModel> updates = [];

  @override
  Future<void> updateAppointment(AppointmentModel updated) async {
    updates.add(updated);
  }
}

final DateTime _firstDate = DateTime(2026, 11, 14, 14);
final DateTime _postponedDate = DateTime(2026, 11, 28, 14);
final DateTime _newPostponedDate = DateTime(2026, 12, 5, 14);

AppointmentModel _appointment({
  List<DateTime> repostponedFrom = const <DateTime>[],
}) =>
    AppointmentModel(
      appointmentId: 'a1',
      userId: 'u1',
      subscriptionId: 's1',
      meetingType: MeetingType.f2f,
      appointmentType: AppointmentType.haftalik,
      appointmentDateTime: _firstDate,
      status: AppointmentStatus.postponed,
      createDate: DateTime(2026, 11, 1),
      postponedDate: _postponedDate,
      postponedBy: PostponeSource.user,
      repostponedFrom: repostponedFrom,
      durationMinutes: 30,
    );

class _Harness {
  _Harness({required int used}) : subs = _FakeSubProvider(used: used) {
    manager = _RecordingAppointmentManager(subs);
  }

  final _FakeSubProvider subs;
  late final _RecordingAppointmentManager manager;
}

Future<_Harness> _open(
  WidgetTester tester,
  AppointmentModel appointment, {
  int used = 1,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final _Harness harness = _Harness(used: used);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SubProvider>.value(value: harness.subs),
        ChangeNotifierProvider<UserProvider>(
            create: (_) => _FakeUserProvider()),
        ChangeNotifierProvider<AppointmentDurationsProvider>(
            create: (_) => _FakeDurationsProvider()),
        ChangeNotifierProvider<AppointmentManager>.value(
            value: harness.manager),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => EditAppointmentDialog(
                  appointment: appointment,
                  onAppointmentUpdated: () {},
                ),
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _pickPostponedDate(WidgetTester tester) async {
  await tester.tap(find.text('ERTELENDİĞİ TARİH'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Next month'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('5'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Kaydet'));
  await tester.pumpAndSettle();
}

Future<void> _answer(WidgetTester tester, String option) async {
  await tester.tap(find.text(option));
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets(
      'ertelendiği tarih değişince tekrar erteleme mi diye sorulur; "Evet" '
      'önceki tarihi kaydeder ve bir hak daha düşer',
      (WidgetTester tester) async {
    final _Harness harness = await _open(tester, _appointment());

    await _pickPostponedDate(tester);
    expect(find.text('05.12.2026 14:00'), findsOneWidget);
    await _save(tester);

    expect(find.text(_repostponeTitle), findsOneWidget);
    expect(find.textContaining('28.11.2026 14:00 → 05.12.2026 14:00'),
        findsOneWidget);
    expect(find.textContaining('KALAN ERTELEME HAKKI: 2'), findsOneWidget);
    expect(harness.manager.updates, isEmpty);

    await _answer(tester, _repostponeOption);

    final AppointmentModel saved = harness.manager.updates.single;
    expect(saved.status, AppointmentStatus.postponed);
    expect(saved.appointmentDateTime, _firstDate);
    expect(saved.postponedDate, _newPostponedDate);
    expect(saved.postponedBy, PostponeSource.user);
    expect(saved.repostponedFrom, [_postponedDate]);
    expect(harness.subs.adjustments, [(subscriptionId: 's1', delta: 1)]);

    expect(find.text('Başarılı'), findsOneWidget);
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
  });

  testWidgets('"Hayır" seçilince yalnızca tarih değişir, hak düşülmez',
      (WidgetTester tester) async {
    final _Harness harness = await _open(tester, _appointment());

    await _pickPostponedDate(tester);
    await _save(tester);
    await _answer(tester, _dateOnlyOption);

    final AppointmentModel saved = harness.manager.updates.single;
    expect(saved.postponedDate, _newPostponedDate);
    expect(saved.repostponedFrom, isEmpty);
    expect(harness.subs.adjustments, isEmpty);

    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
  });

  testWidgets('soruda vazgeçilirse randevu kaydedilmez',
      (WidgetTester tester) async {
    final _Harness harness = await _open(tester, _appointment());

    await _pickPostponedDate(tester);
    await _save(tester);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(harness.manager.updates, isEmpty);
    expect(harness.subs.adjustments, isEmpty);
    expect(find.text('Randevu Düzenle'), findsOneWidget);
  });

  testWidgets('ertelendiği tarih değişmezse soru sorulmaz',
      (WidgetTester tester) async {
    final _Harness harness = await _open(tester, _appointment());

    await _save(tester);

    expect(find.text(_repostponeTitle), findsNothing);
    expect(harness.manager.updates.single.postponedDate, _postponedDate);
    expect(harness.subs.adjustments, isEmpty);

    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'hak kalmadıysa tekrar erteleme onaylanmadan önce uyarılır; '
      'uyarı reddedilirse kaydedilmez', (WidgetTester tester) async {
    final _Harness harness = await _open(tester, _appointment(), used: 3);

    await _pickPostponedDate(tester);
    await _save(tester);
    await _answer(tester, _repostponeOption);

    expect(find.text('ERTELEME HAKKI YOK'), findsOneWidget);
    await tester.tap(find.text('Hayır'));
    await tester.pumpAndSettle();

    expect(harness.manager.updates, isEmpty);
    expect(harness.subs.adjustments, isEmpty);
  });

  testWidgets(
      'erteleme kaynağı ofise çevrilirse tekrar ertelemelerle birlikte '
      'bütün haklar geri verilir', (WidgetTester tester) async {
    final _Harness harness = await _open(
        tester, _appointment(repostponedFrom: [DateTime(2026, 11, 21, 14)]),
        used: 2);

    await tester.tap(find.text('Danışan Kaynaklı'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ofis Kaynaklı').last);
    await tester.pumpAndSettle();
    await _save(tester);

    expect(find.text(_repostponeTitle), findsNothing);
    final AppointmentModel saved = harness.manager.updates.single;
    expect(saved.postponedBy, PostponeSource.admin);
    expect(saved.repostponedFrom, isEmpty);
    expect(harness.subs.adjustments, [(subscriptionId: 's1', delta: -2)]);
    expect(find.textContaining('2 ERTELEME HAKKI DANIŞANA GERİ VERİLDİ'),
        findsOneWidget);

    await tester.tap(find.text('Anladım'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
  });
}
