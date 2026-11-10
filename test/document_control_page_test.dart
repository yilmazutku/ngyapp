import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/pages/document_control_page.dart';
import 'package:ngy_app/providers/admin_notifications_provider.dart';
import 'package:ngy_app/providers/blood_test_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/utils/calendar_day.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<FakeFirebaseFirestore> seed() async {
    final FakeFirebaseFirestore db = FakeFirebaseFirestore();
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    Future<void> user(String id, String name, int daysAgo, {bool? present}) =>
        db.collection('users').doc(id).set({
          'name': name,
          'surname': 'Test',
          'email': '$id@x.com',
          'role': 'customer',
          'createDate':
              Timestamp.fromDate(now.subtract(Duration(days: daysAgo))),
          if (present != null) 'isBloodTestPresent': present,
        }).then((_) => db
            .collection('users')
            .doc(id)
            .collection('subscriptions')
            .add({'status': 'active'}));
    await user('eksik', 'Eksik', 20);
    await user('eski', 'Eski', 300, present: true);
    await db.collection('users').doc('eski').collection('tests').add({
      'isBloodTest': true,
      'bloodTestDate': calendarDayToTimestamp(
          DateTime(today.year, today.month - 4, today.day)),
    });
    await user('yeni', 'Yeni', 2, present: false);
    await user('guncel', 'Guncel', 300, present: true);
    await db.collection('users').doc('guncel').collection('tests').add({
      'isBloodTest': true,
      'bloodTestDate':
          Timestamp.fromDate(today.subtract(const Duration(days: 3))),
    });
    return db;
  }

  testWidgets('kontrol bütün danışanları listeler, gecikmişler en üstte; '
      'kartlar ve arama süzer', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeFirebaseFirestore db = await seed();
    final AdminNotificationsProvider notifications =
        AdminNotificationsProvider(db: db, currentUid: () => 'admin-1');
    addTearDown(notifications.dispose);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AdminNotificationsProvider>.value(
            value: notifications),
        ChangeNotifierProvider(
          create: (_) =>
              BloodTestProvider(notifications: notifications, db: db),
        ),
        ChangeNotifierProvider(create: (_) => UserProvider()),
      ],
      child: const MaterialApp(home: DocumentControlPage()),
    ));
    expect(find.textContaining('Henüz kontrol yapılmadı'), findsOneWidget);

    await tester.tap(find.text('Kan tahlillerini kontrol et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('GECİKMİŞ (2)'), findsOneWidget);
    expect(find.text('YAKLAŞAN (1)'), findsOneWidget);
    expect(find.text('GÜNCEL (1)'), findsOneWidget);
    final double eski = tester.getTopLeft(find.text('Eski Test')).dy;
    final double eksik = tester.getTopLeft(find.text('Eksik Test')).dy;
    final double yeni = tester.getTopLeft(find.text('Yeni Test')).dy;
    final double guncel = tester.getTopLeft(find.text('Guncel Test')).dy;
    expect(eski < eksik && eksik < yeni && yeni < guncel, isTrue);
    expect(find.text('Kan tahlilinin üzerinden 3 ay geçti'), findsOneWidget);
    expect(find.text('İlk kan tahlili yüklenmedi'), findsOneWidget);
    expect(find.textContaining('Son kontrol:'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Gecikmiş (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni Test'), findsNothing);
    expect(find.text('Eksik Test'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Tümü (4)'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni Test'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'guncel');
    await tester.pumpAndSettle();
    expect(find.text('Guncel Test'), findsOneWidget);
    expect(find.text('Eski Test'), findsNothing);
  });
}
