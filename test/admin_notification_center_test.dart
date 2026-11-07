import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ngy_app/pages/admin_notifications_page.dart';
import 'package:ngy_app/providers/admin_notifications_provider.dart';
import 'package:ngy_app/providers/meal_photo_notifications_provider.dart';
import 'package:ngy_app/providers/user_provider.dart';
import 'package:ngy_app/services/admin_notification_delivery.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoScheduler implements AdminNotificationScheduler {
  @override
  bool get isSupported => false;

  @override
  Future<bool> schedule({
    required String docId,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async =>
      false;

  @override
  Future<void> cancel(String docId) async {}

  @override
  Future<Set<String>> pendingDocIds() async => const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeFirebaseFirestore db = FakeFirebaseFirestore();
    final AdminNotificationsProvider notifications = AdminNotificationsProvider(
      db: db,
      currentUid: () => 'admin-1',
      delivery: AdminNotificationDelivery(
        local: _NoScheduler(),
        banner: ({required title, required body, required data}) {},
        osShowsInForeground: false,
      ),
    );
    addTearDown(notifications.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AdminNotificationsProvider>.value(
            value: notifications),
        ChangeNotifierProvider(
            create: (_) => MealPhotoNotificationsProvider(db: db)),
        ChangeNotifierProvider(create: (_) => UserProvider()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openAdminNotificationCenter(context),
              child: const Text('Zil'),
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  int selectedTab(WidgetTester tester) =>
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

  void request(WidgetTester tester, Finder from, AdminNotificationTab tab) {
    unawaited(
        openAdminNotificationCenter(tester.element(from), initialTab: tab));
  }

  testWidgets('merkez öndeyken gelen dokunuş sekmesini değiştirir',
      (WidgetTester tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Zil'));
    await settle(tester);
    expect(find.byType(AdminNotificationCenter), findsOneWidget);
    expect(selectedTab(tester), AdminNotificationTab.chat.index);

    request(tester, find.byType(AdminNotificationCenter),
        AdminNotificationTab.system);
    await settle(tester);
    expect(find.byType(AdminNotificationCenter), findsOneWidget);
    expect(selectedTab(tester), AdminNotificationTab.system.index);
  });

  testWidgets(
      'merkezin üstünde sayfa varken merkez yeniden açılır; alttaki merkezin '
      'sekmesi değişmez', (WidgetTester tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Zil'));
    await settle(tester);
    request(tester, find.byType(AdminNotificationCenter),
        AdminNotificationTab.system);
    await settle(tester);
    expect(selectedTab(tester), AdminNotificationTab.system.index);

    final NavigatorState navigator =
        Navigator.of(tester.element(find.byType(AdminNotificationCenter)));
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Sohbet sayfası')),
    )));
    await settle(tester);

    request(tester, find.text('Sohbet sayfası'), AdminNotificationTab.chat);
    await settle(tester);
    expect(find.byType(AdminNotificationCenter), findsOneWidget);
    expect(selectedTab(tester), AdminNotificationTab.chat.index);

    request(tester, find.byType(AdminNotificationCenter),
        AdminNotificationTab.chat);
    await settle(tester);
    expect(find.byType(AdminNotificationCenter), findsOneWidget);

    navigator.pop();
    await settle(tester);
    expect(find.text('Sohbet sayfası'), findsOneWidget);
    navigator.pop();
    await settle(tester);
    expect(selectedTab(tester), AdminNotificationTab.system.index);

    request(tester, find.byType(AdminNotificationCenter),
        AdminNotificationTab.chat);
    await settle(tester);
    expect(find.byType(AdminNotificationCenter), findsOneWidget);
    expect(selectedTab(tester), AdminNotificationTab.chat.index);
    navigator.pop();
    await settle(tester);
    expect(find.text('Zil'), findsOneWidget);
  });
}
