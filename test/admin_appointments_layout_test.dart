import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:ngy_app/models/appointment_model.dart';
import 'package:ngy_app/models/event_model.dart';
import 'package:ngy_app/models/user_model.dart';
import 'package:ngy_app/pages/admin_appointments_page.dart';
import 'package:ngy_app/providers/appointment_colors_provider.dart';
import 'package:ngy_app/providers/appointment_manager.dart';
import 'package:ngy_app/providers/event_provider.dart';
import 'package:ngy_app/providers/sub_provider.dart';
import 'package:ngy_app/providers/timeslot_manager.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:provider/provider.dart';

class _FakeAppointmentManager extends AppointmentManager {
  _FakeAppointmentManager(this.appointments)
      : super(subProvider: SubProvider());

  final List<AppointmentModel> appointments;

  @override
  Future<List<AppointmentModel>> fetchAppointmentsWithUsers({
    DateTime? startDate,
    DateTime? endDate,
    AppointmentStatus? statusFilter,
    MeetingType? meetingTypeFilter,
    Set<AppointmentStatus>? statusesFilter,
  }) async =>
      List<AppointmentModel>.of(appointments);
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
}

final RegExp _cardLabel =
    RegExp('^\\d.* ${RegExp.escape(kPostponedMark)}\$');

DateTime _today() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _thisWeeksSaturday() {
  final DateTime today = _today();
  return DateTime(today.year, today.month,
      today.day - (today.weekday - DateTime.monday) + 5);
}

UserModel _customer(String id, String name, String surname,
        {String? dosyaNo}) =>
    UserModel(
      userId: id,
      name: name,
      surname: surname,
      email: '$id@test.com',
      password: '',
      role: 'customer',
      dosyaNo: dosyaNo,
    );

AppointmentModel _postponedOnce(
        String id, DateTime day, int hour, UserModel user) =>
    AppointmentModel(
      appointmentId: id,
      userId: user.userId,
      user: user,
      meetingType: MeetingType.f2f,
      appointmentType: AppointmentType.haftalik,
      appointmentDateTime: DateTime(day.year, day.month, day.day, hour),
      durationMinutes: 30,
      status: AppointmentStatus.completed,
      postponedBy: PostponeSource.user,
      createDate: day,
    );

List<AppointmentModel> _postponedAppointmentsOn(DateTime day) => [
      _postponedOnce('kisa', day, 10, _customer('u1', 'Ali', 'Veli')),
      _postponedOnce(
        'uzun',
        day,
        12,
        _customer('u2', 'Ayşegül Nur', 'Karamollaoğlu Büyükdemirci',
            dosyaNo: '1234'),
      ),
    ];

Future<void> _pumpPage(WidgetTester tester, double width,
    List<AppointmentModel> appointments,
    {double sideInset = 0}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(left: sideInset, right: sideInset);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppointmentManager>(
          create: (_) => _FakeAppointmentManager(appointments)),
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
}

double _scrollbarThumbLeft(WidgetTester tester) {
  final Finder scrollbarPaints = find.byWidgetPredicate((Widget widget) =>
      widget is CustomPaint && widget.foregroundPainter is ScrollbarPainter);
  expect(scrollbarPaints, findsWidgets);
  double left = double.infinity;
  for (final Element element in scrollbarPaints.evaluate()) {
    final ScrollbarPainter painter = (element.widget as CustomPaint)
        .foregroundPainter! as ScrollbarPainter;
    final CupertinoScrollbar? cupertino =
        element.findAncestorWidgetOfExactType<CupertinoScrollbar>();
    final double thickness = cupertino == null
        ? painter.thickness
        : math.max(painter.thickness, cupertino.thicknessWhileDragging);
    final RenderBox area = element.renderObject! as RenderBox;
    final double right = area.localToGlobal(Offset(area.size.width, 0)).dx;
    final EdgeInsets padding = painter.padding.resolve(TextDirection.ltr);
    left = math.min(
        left, right - padding.right - painter.crossAxisMargin - thickness);
  }
  return left;
}

RenderBox _clippingStackOf(RenderObject object) {
  RenderObject? current = object.parent;
  while (current != null && current is! RenderStack) {
    current = current.parent;
  }
  expect(current, isNotNull);
  return current! as RenderBox;
}

Rect _onScreen(RenderBox box, [Rect? local]) => MatrixUtils.transformRect(
    box.getTransformTo(null), local ?? Offset.zero & box.size);

void _expectPostponedMarksVisible(WidgetTester tester, double visibleRight,
    {required int count}) {
  final Finder cards = find.byWidgetPredicate((Widget widget) {
    return widget is RichText &&
        _cardLabel.hasMatch(widget.text.toPlainText());
  });
  expect(cards, findsNWidgets(count));
  for (final Element element in cards.evaluate()) {
    final RenderParagraph paragraph = element.renderObject! as RenderParagraph;
    final String text = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: text);

    final Rect card = _onScreen(paragraph);
    final Rect grid = _onScreen(_clippingStackOf(paragraph));
    expect(card.left, greaterThanOrEqualTo(grid.left - 0.01), reason: text);
    expect(card.right, lessThanOrEqualTo(grid.right + 0.01), reason: text);
    expect(card.right, lessThanOrEqualTo(visibleRight + 0.01), reason: text);

    final List<TextBox> markBoxes = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: text.length - kPostponedMark.length,
        extentOffset: text.length,
      ),
    );
    expect(markBoxes, isNotEmpty, reason: text);
    for (final TextBox box in markBoxes) {
      final Rect local = box.toRect();
      expect(local.left, greaterThanOrEqualTo(-0.01), reason: text);
      expect(local.right, lessThanOrEqualTo(paragraph.size.width + 0.01),
          reason: text);
      final Rect mark = _onScreen(paragraph, local);
      expect(mark.left, greaterThanOrEqualTo(0), reason: text);
      expect(mark.right, lessThanOrEqualTo(visibleRight + 0.01), reason: text);
    }
  }
}

Future<void> _expectSaturdayVisible(WidgetTester tester, double width,
    {double sideInset = 0}) async {
  final DateTime saturday = _thisWeeksSaturday();
  await _pumpPage(tester, width, _postponedAppointmentsOn(saturday),
      sideInset: sideInset);

  final double thumbLeft = _scrollbarThumbLeft(tester);
  expect(thumbLeft, lessThanOrEqualTo(width - sideInset));

  final Finder dayTitles = find.byWidgetPredicate((Widget widget) =>
      widget is Text &&
      widget.data == DateFormat('d MMMM EEEE', 'tr_TR').format(saturday));
  expect(dayTitles, findsOneWidget);
  expect(tester.getRect(dayTitles).right, lessThanOrEqualTo(thumbLeft + 0.01));

  final Finder dayButtons = find.widgetWithText(ElevatedButton, 'Diğer');
  expect(dayButtons, findsNWidgets(6));
  for (final Element button in dayButtons.evaluate()) {
    final Rect rect = _onScreen(button.renderObject! as RenderBox);
    expect(rect.left, greaterThanOrEqualTo(sideInset - 0.01));
    expect(rect.right, lessThanOrEqualTo(thumbLeft + 0.01));
  }

  _expectPostponedMarksVisible(tester, thumbLeft, count: 2);
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  for (final double width in const <double>[600, 800, 1024, 1280, 1920]) {
    testWidgets(
        'haftalık görünümde cumartesi sütunu ve (E) işareti ekrandan '
        'taşmaz, kaydırma çubuğunun altında kalmaz ($width px)',
        (WidgetTester tester) async {
      await _expectSaturdayVisible(tester, width);
    }, variant: TargetPlatformVariant.all());
  }

  testWidgets(
      'yatay tutulan çentikli telefonda cumartesi sütunu ve (E) işareti '
      'güvenli alanın içinde kalır', (WidgetTester tester) async {
    await _expectSaturdayVisible(tester, 844, sideInset: 47);
  }, variant: TargetPlatformVariant.all());

  for (final double width in const <double>[390, 430, 540]) {
    testWidgets(
        'günlük görünümde (E) işareti ekrandan taşmaz, kaydırma çubuğunun '
        'altında kalmaz ($width px)', (WidgetTester tester) async {
      await _pumpPage(tester, width, _postponedAppointmentsOn(_today()));

      final double thumbLeft = _scrollbarThumbLeft(tester);
      expect(thumbLeft, lessThanOrEqualTo(width));
      _expectPostponedMarksVisible(tester, thumbLeft, count: 2);
    }, variant: TargetPlatformVariant.all());
  }
}
