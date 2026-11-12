import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:ngy_app/dialogs/edit_appointment_dialog.dart';
import 'package:ngy_app/dialogs/reschedule_appointment_dialog.dart';
import 'package:ngy_app/models/appointment_model.dart';
import 'package:ngy_app/models/event_model.dart';
import 'package:ngy_app/models/filter_params.dart';
import 'package:ngy_app/models/subs_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/pages/admin_appointments_page.dart';
import 'package:ngy_app/providers/appointment_colors_provider.dart';
import 'package:ngy_app/providers/appointment_manager.dart';
import 'package:ngy_app/providers/event_provider.dart';
import 'package:ngy_app/providers/sub_provider.dart';
import 'package:ngy_app/providers/timeslot_manager.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:provider/provider.dart';

const String _dialogTitle = 'Randevuyu Taşı';
const String _deductOption = 'Evet, erteleme hakkından düş';
const String _moveOnlyOption = 'Hayır, yalnızca tarihi ve saati değiştir';
const String _cancel = 'Vazgeç';
const String _loadingMessage = 'Randevu taşınıyor...';
const String _notDraggableTitle = 'Randevu Taşınamaz';
const Duration _hold = Duration(milliseconds: 600);

typedef _Move = ({String id, DateTime newStart, bool deductRight});

class _FakeSubProvider extends SubProvider {
  @override
  Future<List<SubscriptionModel>> fetchSubscriptions({
    required String userId,
    required bool showAllSubscriptions,
    SubscriptionFilterParams? filterParams,
  }) async =>
      <SubscriptionModel>[];
}

class _FakeAppointmentManager extends AppointmentManager {
  _FakeAppointmentManager(this.appointments)
      : super(subProvider: SubProvider());

  List<AppointmentModel> appointments;
  final List<_Move> moves = <_Move>[];
  Object? rescheduleError;
  Completer<void>? holdNextFetch;
  int fetches = 0;

  @override
  Future<List<AppointmentModel>> fetchAppointmentsWithUsers({
    DateTime? startDate,
    DateTime? endDate,
    AppointmentStatus? statusFilter,
    MeetingType? meetingTypeFilter,
    Set<AppointmentStatus>? statusesFilter,
  }) async {
    fetches++;
    final Completer<void>? hold = holdNextFetch;
    if (hold != null) {
      holdNextFetch = null;
      await hold.future;
    }
    return List<AppointmentModel>.of(appointments);
  }

  @override
  Future<void> rescheduleAppointment(
    AppointmentModel appointment,
    DateTime newStart, {
    required bool deductPostponementRight,
  }) async {
    final Object? error = rescheduleError;
    if (error != null) throw error;
    moves.add((
      id: appointment.appointmentId,
      newStart: newStart,
      deductRight: deductPostponementRight,
    ));
    appointments = [
      for (final AppointmentModel existing in appointments)
        existing.appointmentId == appointment.appointmentId
            ? existing.rescheduledTo(newStart,
                deductPostponementRight: deductPostponementRight)
            : existing,
    ];
  }
}

class _FakeEventProvider extends EventProvider {
  @override
  Future<List<EventModel>> fetchEventsForDateRange(
          DateTime startDate, DateTime endDate) async =>
      <EventModel>[];
}

class _FakeTimeslotManager extends TimeslotManager {
  @override
  Future<void> backfillBusySlotsOnce() async {}
}

class _FakeUserProvider extends UserProvider {
  @override
  Future<List<UserModel>> fetchAllCustomers(
          {bool forceRefresh = false}) async =>
      <UserModel>[];

  @override
  Future<UserModel?> fetchUserDetails({required String userId}) async => null;
}

DateTime _today() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _weekDay(int index) {
  final DateTime today = _today();
  return DateTime(today.year, today.month,
      today.day - (today.weekday - DateTime.monday) + index);
}

DateTime _at(DateTime day, int hour, [int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute);

final UserModel _ali = UserModel(
  userId: 'u1',
  name: 'Ali',
  surname: 'Veli',
  email: 'u1@test.com',
  password: '',
  role: 'customer',
);

AppointmentModel _appointment(
  DateTime start, {
  String id = 'a1',
  AppointmentStatus status = AppointmentStatus.scheduled,
  DateTime? postponedDate,
  PostponeSource? postponedBy,
  int durationMinutes = 30,
}) =>
    AppointmentModel(
      appointmentId: id,
      userId: _ali.userId,
      user: _ali,
      subscriptionId: 's1',
      meetingType: MeetingType.f2f,
      appointmentType: AppointmentType.haftalik,
      appointmentDateTime: start,
      durationMinutes: durationMinutes,
      status: status,
      postponedDate: postponedDate,
      postponedBy: postponedBy,
      createDate: start,
    );

Future<_FakeAppointmentManager> _pumpPage(
  WidgetTester tester,
  List<AppointmentModel> appointments, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final _FakeAppointmentManager manager = _FakeAppointmentManager(appointments);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SubProvider>(create: (_) => _FakeSubProvider()),
      ChangeNotifierProvider<AppointmentManager>.value(value: manager),
      ChangeNotifierProvider<EventProvider>(
          create: (_) => _FakeEventProvider()),
      ChangeNotifierProvider<TimeslotManager>(
          create: (_) => _FakeTimeslotManager()),
      ChangeNotifierProvider<UserProvider>(create: (_) => _FakeUserProvider()),
      ChangeNotifierProvider<AppointmentColorsProvider>(
          create: (_) =>
              AppointmentColorsProvider(db: FakeFirebaseFirestore())),
    ],
    child: const MaterialApp(home: AdminAppointmentsPage()),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return manager;
}

final DateFormat _dayTitle = DateFormat('d MMMM EEEE', 'tr_TR');

Finder _card(String label) => find.text(label);

double _columnWidth(WidgetTester tester) =>
    tester.getTopLeft(find.text(_dayTitle.format(_weekDay(1)))).dx -
    tester.getTopLeft(find.text(_dayTitle.format(_weekDay(0)))).dx;

final Finder _gridScrollView =
    find.byKey(const PageStorageKey<String>('admin_appts_vertical'));

ScrollPosition _scrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(of: _gridScrollView, matching: find.byType(Scrollable))
        .first)
    .position;

double _sourceOpacity(WidgetTester tester, String label) => tester
    .widget<Opacity>(
        find.ancestor(of: _card(label), matching: find.byType(Opacity)).first)
    .opacity;

Future<TestGesture> _pickUp(WidgetTester tester, String label,
    {PointerDeviceKind kind = PointerDeviceKind.touch}) async {
  final TestGesture gesture =
      await tester.startGesture(tester.getCenter(_card(label)), kind: kind);
  await tester.pump(_hold);
  return gesture;
}

Future<void> _choose(WidgetTester tester, String option) async {
  await tester.ensureVisible(find.text(option));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option));
  await tester.pump();
}

Future<void> _confirmMove(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, _dialogTitle));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('saat sütunu', () {
    testWidgets(
        'tam saatlerin arasında yarım saatler daha küçük yazıyla '
        'gösterilir', (WidgetTester tester) async {
      await _pumpPage(tester, <AppointmentModel>[]);

      for (final String label in const <String>['09:00', '14:00', '19:00']) {
        expect(tester.widget<Text>(find.text(label)).style!.fontSize,
            kHourLabelFontSize,
            reason: label);
      }
      for (final String label in const <String>['08:30', '09:30', '19:30']) {
        expect(tester.widget<Text>(find.text(label)).style!.fontSize,
            kHalfHourLabelFontSize,
            reason: label);
      }
      expect(kHalfHourLabelFontSize, lessThan(kHourLabelFontSize));
      expect(find.text('20:00'), findsNothing);
    });

    testWidgets('yarım saat etiketi iki tam saatin tam ortasındadır',
        (WidgetTester tester) async {
      await _pumpPage(tester, <AppointmentModel>[]);

      final double ten = tester.getTopLeft(find.text('10:00')).dy;
      final double halfPast = tester.getTopLeft(find.text('10:30')).dy;
      final double eleven = tester.getTopLeft(find.text('11:00')).dy;
      expect(halfPast - ten, closeTo(30 * kPixelsPerMinute, 0.01));
      expect(eleven - halfPast, closeTo(30 * kPixelsPerMinute, 0.01));
    });

    test('bir sürükleme adımı tam piksele denk gelir', () {
      final double step = kSnapMinutes * kPixelsPerMinute;
      expect(step, closeTo(step.roundToDouble(), 1e-9));
      expect(step, greaterThanOrEqualTo(20));
    });
  });

  group('basılı tutup sürükleme (dokunmatik)', () {
    testWidgets(
        'başka güne ve saate taşınan randevu onaydan sonra ertelenir, '
        'sayfa yeni yerini gösterir', (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);
      final double columnWidth = _columnWidth(tester);
      final int fetchesBefore = manager.fetches;

      final TestGesture gesture = await _pickUp(tester, '10:00-10:30 Ali Veli');
      expect(
          _sourceOpacity(tester, '10:00-10:30 Ali Veli'), kDragSourceOpacity);

      await gesture.moveBy(Offset(columnWidth, 60 * kPixelsPerMinute));
      await tester.pump();
      expect(_card('11:00-11:30 Ali Veli'), findsOneWidget);
      expect(_card('10:00-10:30 Ali Veli'), findsOneWidget);
      expect(find.text('11:00'), findsNWidgets(2));
      expect(find.byType(RescheduleAppointmentDialog), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(RescheduleAppointmentDialog), findsOneWidget);
      expect(
          find.text(DateFormat('d MMMM y EEEE', 'tr_TR').format(_weekDay(1))),
          findsOneWidget);
      expect(find.text('11:00 – 11:30'), findsOneWidget);
      expect(manager.moves, isEmpty);

      await _choose(tester, _deductOption);
      await _confirmMove(tester);

      expect(manager.moves, <_Move>[
        (id: 'a1', newStart: _at(_weekDay(1), 11), deductRight: true),
      ]);
      expect(manager.fetches, fetchesBefore + 1);
      expect(find.byType(RescheduleAppointmentDialog), findsNothing);
      expect(find.text(_loadingMessage), findsNothing);
      expect(_card('10:00-10:30 Ali Veli'), findsNothing);
      expect(_card('11:00-11:30 Ali Veli'), findsOneWidget);
      final double cardLeft =
          tester.getTopLeft(_card('11:00-11:30 Ali Veli')).dx;
      final double tuesdayLeft =
          tester.getTopLeft(find.text(_dayTitle.format(_weekDay(1)))).dx;
      expect(cardLeft, greaterThanOrEqualTo(tuesdayLeft - kMainMargin));
      expect(cardLeft, lessThan(tuesdayLeft + columnWidth));
      expect(_sourceOpacity(tester, '11:00-11:30 Ali Veli'), 1);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.all());

    testWidgets(
        '"Hayır" denirse randevu yalnızca düzenlenir: Planlandı kalır, '
        '(E) işareti çıkmaz', (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(2), 10))]);

      final TestGesture gesture = await _pickUp(tester, '10:00-10:30 Ali Veli');
      await gesture.moveBy(const Offset(0, -30 * kPixelsPerMinute));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _moveOnlyOption);
      await _confirmMove(tester);

      expect(manager.moves, <_Move>[
        (id: 'a1', newStart: _at(_weekDay(2), 9, 30), deductRight: false),
      ]);
      expect(manager.appointments.single.status, AppointmentStatus.scheduled);
      expect(_card('09:30-10:00 Ali Veli'), findsOneWidget);
      expect(find.textContaining(kPostponedMark), findsOneWidget,
          reason: 'yalnızca açıklama satırındaki (E)');
    }, variant: TargetPlatformVariant.all());

    testWidgets('"Vazgeç" denirse hiçbir şey değişmez',
        (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);
      final int fetchesBefore = manager.fetches;

      final TestGesture gesture = await _pickUp(tester, '10:00-10:30 Ali Veli');
      await gesture.moveBy(const Offset(0, 60 * kPixelsPerMinute));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text(_cancel));
      await tester.pumpAndSettle();

      expect(manager.moves, isEmpty);
      expect(manager.fetches, fetchesBefore);
      expect(_card('10:00-10:30 Ali Veli'), findsOneWidget);
      expect(_sourceOpacity(tester, '10:00-10:30 Ali Veli'), 1);
    }, variant: TargetPlatformVariant.all());

    testWidgets('yerine geri bırakılan randevu için onay sorulmaz',
        (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);

      final TestGesture gesture = await _pickUp(tester, '10:00-10:30 Ali Veli');
      await gesture.moveBy(const Offset(0, 80));
      await tester.pump();
      expect(_card('10:30-11:00 Ali Veli'), findsOneWidget);
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(RescheduleAppointmentDialog), findsNothing);
      expect(find.byType(EditAppointmentDialog), findsNothing);
      expect(manager.moves, isEmpty);
      expect(_sourceOpacity(tester, '10:00-10:30 Ali Veli'), 1);
    }, variant: TargetPlatformVariant.all());

    testWidgets(
        'basılı tutmadan kaydırmak sayfayı kaydırır, randevuyu '
        'taşımaz', (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 12))]);
      expect(_scrollPosition(tester).pixels, 0);

      await tester.drag(_card('12:00-12:30 Ali Veli'), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(_scrollPosition(tester).pixels, greaterThan(100));
      expect(find.byType(RescheduleAppointmentDialog), findsNothing);
      expect(manager.moves, isEmpty);
    }, variant: TargetPlatformVariant.all());

    testWidgets('dokunmak randevu düzenlemeyi açar',
        (WidgetTester tester) async {
      await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);

      await tester.tap(_card('10:00-10:30 Ali Veli'));
      await tester.pumpAndSettle();

      expect(find.byType(EditAppointmentDialog), findsOneWidget);
    }, variant: TargetPlatformVariant.all());
  });

  group('hassasiyet', () {
    testWidgets(
        'yarım adımdan az sürükleme saati değiştirmez, fazlası bir '
        'adım (10 dk) kaydırır', (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);
      final double halfStep = kSnapMinutes * kPixelsPerMinute / 2;

      final TestGesture gesture = await _pickUp(tester, '10:00-10:30 Ali Veli');
      await gesture.moveBy(Offset(0, halfStep - 1));
      await tester.pump();
      expect(_card('10:10-10:40 Ali Veli'), findsNothing);
      expect(find.text('10:00'), findsNWidgets(2));

      await gesture.moveBy(const Offset(0, 2));
      await tester.pump();
      expect(_card('10:10-10:40 Ali Veli'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _moveOnlyOption);
      await _confirmMove(tester);
      expect(manager.moves.single.newStart, _at(_weekDay(0), 10, 10));
    });

    testWidgets(
        'yalnızca yana sürüklenen randevu, ızgara dışındaki saatini '
        'korur', (WidgetTester tester) async {
      final _FakeAppointmentManager manager = await _pumpPage(
          tester, [_appointment(_at(_weekDay(0), 10, 5), durationMinutes: 20)]);
      final double columnWidth = _columnWidth(tester);

      final TestGesture gesture = await _pickUp(tester, '10:05-10:25 Ali Veli');
      await gesture.moveBy(Offset(3 * columnWidth, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _moveOnlyOption);
      await _confirmMove(tester);

      expect(manager.moves.single.newStart, _at(_weekDay(3), 10, 5));
    });

    testWidgets(
        'ızgaranın dışına bırakılamaz: ilk gün, son gün, günün başı '
        've sonu', (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(2), 9))]);

      TestGesture gesture = await _pickUp(tester, '09:00-09:30 Ali Veli');
      await gesture.moveBy(const Offset(-900, -400));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _moveOnlyOption);
      await _confirmMove(tester);
      expect(manager.moves.last.newStart, _at(_weekDay(0), 8, 30));

      gesture = await _pickUp(tester, '08:30-09:00 Ali Veli');
      await gesture.moveBy(const Offset(2000, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _moveOnlyOption);
      await _confirmMove(tester);
      expect(manager.moves.last.newStart, _at(_weekDay(5), 8, 30));
    });
  });

  group('fareyle sürükleme', () {
    testWidgets('yarım saniye basılı tutulunca sürüklenir; bırakınca onay '
        'sorulur', (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);
      final double columnWidth = _columnWidth(tester);

      final TestGesture gesture = await _pickUp(
          tester, '10:00-10:30 Ali Veli',
          kind: PointerDeviceKind.mouse);
      expect(
          _sourceOpacity(tester, '10:00-10:30 Ali Veli'), kDragSourceOpacity);
      await gesture.moveBy(Offset(2 * columnWidth, 90 * kPixelsPerMinute));
      await tester.pump();
      expect(_card('11:30-12:00 Ali Veli'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _deductOption);
      await _confirmMove(tester);

      expect(manager.moves, <_Move>[
        (id: 'a1', newStart: _at(_weekDay(2), 11, 30), deductRight: true),
      ]);
      expect(_card('11:30-12:00 Ali Veli'), findsOneWidget);
    }, variant: TargetPlatformVariant.all());

    testWidgets('basılı tutmadan sürüklenen fare randevuyu taşımaz',
        (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);
      final double columnWidth = _columnWidth(tester);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card('10:00-10:30 Ali Veli')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(2 * columnWidth, 90 * kPixelsPerMinute));
      await tester.pump();
      await tester.pump(_hold);
      expect(_card('11:30-12:00 Ali Veli'), findsNothing);
      expect(_sourceOpacity(tester, '10:00-10:30 Ali Veli'), 1);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(RescheduleAppointmentDialog), findsNothing);
      expect(find.byType(EditAppointmentDialog), findsNothing);
      expect(manager.moves, isEmpty);
    }, variant: TargetPlatformVariant.all());

    testWidgets('yarım saniyeden kısa basılı tutup sürüklemek taşımaz',
        (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card('10:00-10:30 Ali Veli')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(_sourceOpacity(tester, '10:00-10:30 Ali Veli'), 1);
      await gesture.moveBy(const Offset(0, 60 * kPixelsPerMinute));
      await tester.pump();
      await tester.pump(_hold);
      expect(_card('11:00-11:30 Ali Veli'), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(RescheduleAppointmentDialog), findsNothing);
      expect(manager.moves, isEmpty);
    }, variant: TargetPlatformVariant.all());

    testWidgets('fare tıklaması düzenlemeyi açar', (WidgetTester tester) async {
      await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_card('10:00-10:30 Ali Veli')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(EditAppointmentDialog), findsOneWidget);
    }, variant: TargetPlatformVariant.all());

    testWidgets('basılı tutup yerinde bırakmak ne düzenlemeyi açar ne onay '
        'sorar', (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);

      final TestGesture gesture = await _pickUp(
          tester, '10:00-10:30 Ali Veli',
          kind: PointerDeviceKind.mouse);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(EditAppointmentDialog), findsNothing);
      expect(find.byType(RescheduleAppointmentDialog), findsNothing);
      expect(manager.moves, isEmpty);
      expect(_sourceOpacity(tester, '10:00-10:30 Ali Veli'), 1);
    }, variant: TargetPlatformVariant.all());

    testWidgets('Esc sürüklemeyi iptal eder', (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);

      final TestGesture gesture = await _pickUp(
          tester, '10:00-10:30 Ali Veli',
          kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(_card('10:50-11:20 Ali Veli'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_card('10:50-11:20 Ali Veli'), findsNothing);
      expect(_sourceOpacity(tester, '10:00-10:30 Ali Veli'), 1);

      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(_card('11:10-11:40 Ali Veli'), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(RescheduleAppointmentDialog), findsNothing);
      expect(find.byType(EditAppointmentDialog), findsNothing);
      expect(manager.moves, isEmpty);
    }, variant: TargetPlatformVariant.all());
  });

  group('kenarda kendiliğinden kaydırma', () {
    testWidgets(
        'alt kenara götürülen randevu sayfayı aşağı kaydırır; hedef '
        'saat kaydırmayla birlikte ilerler', (WidgetTester tester) async {
      final _FakeAppointmentManager manager = await _pumpPage(
          tester, [_appointment(_at(_weekDay(0), 9))],
          size: const Size(1280, 640));
      final ScrollPosition position = _scrollPosition(tester);
      expect(position.pixels, 0);

      final Offset start = tester.getCenter(_card('09:00-09:30 Ali Veli'));
      final TestGesture gesture = await _pickUp(tester, '09:00-09:30 Ali Veli');
      const double bottomEdge = 640 - 8;
      await gesture.moveTo(Offset(start.dx, bottomEdge));
      await tester.pump();
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final double scrolled = position.pixels;
      expect(scrolled, greaterThan(200));

      final double moved = bottomEdge - start.dy + scrolled;
      final int expectedMinutes = 9 * 60 +
          (moved / kPixelsPerMinute / kSnapMinutes).round() * kSnapMinutes;
      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _moveOnlyOption);
      await _confirmMove(tester);

      expect(
        manager.moves.single.newStart,
        _at(_weekDay(0), expectedMinutes ~/ 60, expectedMinutes % 60),
      );
    }, variant: TargetPlatformVariant.all());

    testWidgets('taşımadan sonra kaydırma konumu korunur',
        (WidgetTester tester) async {
      await _pumpPage(tester, [_appointment(_at(_weekDay(0), 14))],
          size: const Size(1280, 640));
      _scrollPosition(tester).jumpTo(600);
      await tester.pumpAndSettle();

      final TestGesture gesture = await _pickUp(tester, '14:00-14:30 Ali Veli');
      await gesture.moveBy(const Offset(0, 60 * kPixelsPerMinute));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _moveOnlyOption);
      await _confirmMove(tester);

      expect(_card('15:00-15:30 Ali Veli'), findsOneWidget);
      expect(_scrollPosition(tester).pixels, 600);
    });
  });

  group('taşıma sırasında sayfa', () {
    testWidgets(
        'yenilenirken takvim ekranda kalır, yükleniyor yazısı '
        'yenileme bitince kapanır', (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);

      final TestGesture gesture = await _pickUp(tester, '10:00-10:30 Ali Veli');
      await gesture.moveBy(const Offset(0, 60 * kPixelsPerMinute));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _moveOnlyOption);

      final Completer<void> hold = Completer<void>();
      manager.holdNextFetch = hold;
      await tester.tap(find.widgetWithText(FilledButton, _dialogTitle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(manager.moves, hasLength(1));
      expect(find.text(_loadingMessage), findsOneWidget);
      expect(find.text(_dayTitle.format(_weekDay(0))), findsOneWidget);
      expect(_card('10:00-10:30 Ali Veli'), findsOneWidget);

      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text(_loadingMessage), findsNothing);
      expect(_card('11:00-11:30 Ali Veli'), findsOneWidget);
      expect(_card('10:00-10:30 Ali Veli'), findsNothing);
    });

    testWidgets('taşıma hata verirse hata gösterilir, randevu yerinde kalır',
        (WidgetTester tester) async {
      final _FakeAppointmentManager manager =
          await _pumpPage(tester, [_appointment(_at(_weekDay(0), 10))]);
      manager.rescheduleError = StateError('bağlantı yok');
      final int fetchesBefore = manager.fetches;

      final TestGesture gesture = await _pickUp(tester, '10:00-10:30 Ali Veli');
      await gesture.moveBy(const Offset(0, 60 * kPixelsPerMinute));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _deductOption);
      await _confirmMove(tester);

      expect(find.text(_loadingMessage), findsNothing);
      expect(find.text('Hata'), findsOneWidget);
      expect(find.textContaining('Randevu taşınırken bir hata oluştu'),
          findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();

      expect(manager.fetches, fetchesBefore);
      expect(_card('10:00-10:30 Ali Veli'), findsOneWidget);
    });
  });

  group('durumlar', () {
    testWidgets('hakkı düşülmüş ertelenmiş randevu soru sorulmadan taşınır',
        (WidgetTester tester) async {
      final _FakeAppointmentManager manager = await _pumpPage(tester, [
        _appointment(
          _at(_weekDay(0), 9),
          status: AppointmentStatus.postponed,
          postponedDate: _at(_weekDay(1), 10),
          postponedBy: PostponeSource.user,
        ),
      ]);

      final TestGesture gesture = await _pickUp(tester, '10:00-10:30 Ali Veli');
      await gesture.moveBy(const Offset(0, 120 * kPixelsPerMinute));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text(_deductOption), findsNothing);
      await _confirmMove(tester);

      expect(manager.moves, <_Move>[
        (id: 'a1', newStart: _at(_weekDay(1), 12), deductRight: false),
      ]);
      expect(
          manager.appointments.single.appointmentDateTime, _at(_weekDay(0), 9));
      expect(_card('12:00-12:30 Ali Veli'), findsOneWidget);
    });

    for (final AppointmentStatus status in const <AppointmentStatus>[
      AppointmentStatus.completed,
      AppointmentStatus.burned,
    ]) {
      testWidgets('${status.label} randevu sürüklenemez; nedeni söylenir',
          (WidgetTester tester) async {
        final _FakeAppointmentManager manager = await _pumpPage(
            tester, [_appointment(_at(_weekDay(0), 10), status: status)]);
        final Finder card = find.textContaining('10:00-10:30 Ali Veli');

        final TestGesture mouse = await tester.startGesture(
          tester.getCenter(card),
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveBy(const Offset(0, 120));
        await tester.pump();
        expect(find.textContaining('10:50-11:20'), findsNothing);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(find.byType(RescheduleAppointmentDialog), findsNothing);

        final TestGesture touch =
            await tester.startGesture(tester.getCenter(card));
        await tester.pump(_hold);
        await touch.moveBy(const Offset(0, 120));
        await tester.pump();
        expect(find.textContaining('10:50-11:20'), findsNothing);
        await touch.up();
        await tester.pumpAndSettle();

        expect(find.text(_notDraggableTitle), findsOneWidget);
        expect(find.textContaining('“${status.label}” durumundaki'),
            findsOneWidget);
        expect(find.byType(RescheduleAppointmentDialog), findsNothing);
        expect(manager.moves, isEmpty);
      });
    }
  });

  group('günlük görünüm (telefon)', () {
    testWidgets(
        'randevu aynı gün içinde başka saate taşınır; yana sürüklemek '
        'günü değiştirmez', (WidgetTester tester) async {
      final _FakeAppointmentManager manager = await _pumpPage(
          tester, [_appointment(_at(_today(), 9))],
          size: const Size(390, 800));

      final TestGesture gesture = await _pickUp(tester, '09:00-09:30 Ali Veli');
      await gesture.moveBy(const Offset(150, 90 * kPixelsPerMinute));
      await tester.pump();
      expect(_card('10:30-11:00 Ali Veli'), findsOneWidget);
      await gesture.moveBy(const Offset(-320, 0));
      await tester.pump();
      expect(_card('10:30-11:00 Ali Veli'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      await _choose(tester, _deductOption);
      await _confirmMove(tester);

      expect(manager.moves, <_Move>[
        (id: 'a1', newStart: _at(_today(), 10, 30), deductRight: true),
      ]);
      expect(_card('10:30-11:00 Ali Veli'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.all());
  });

  testWidgets('sürükleme ipucu sayfada yazar', (WidgetTester tester) async {
    await _pumpPage(tester, <AppointmentModel>[]);
    expect(find.text(kDragHint), findsOneWidget);
  });
}
