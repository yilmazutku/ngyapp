import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/constants/app_constants.dart';
import 'package:ngy_app/models/app_update_info.dart';
import 'package:ngy_app/providers/app_update_provider.dart';
import 'package:ngy_app/widgets/app_update_gate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

const MethodChannel _urlLauncher =
    MethodChannel('plugins.flutter.io/url_launcher');

final TargetPlatformVariant _mobile = TargetPlatformVariant(
  <TargetPlatform>{TargetPlatform.android, TargetPlatform.iOS},
);

class _DelayedUpdateProvider extends AppUpdateProvider {
  _DelayedUpdateProvider() : super(db: FakeFirebaseFirestore());

  final List<Completer<AppUpdateInfo?>> checks = <Completer<AppUpdateInfo?>>[];

  @override
  Future<AppUpdateInfo?> checkForUpdate({String? currentVersion}) {
    final Completer<AppUpdateInfo?> check = Completer<AppUpdateInfo?>();
    checks.add(check);
    return check.future;
  }
}

bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

String get _storeAddress => _isIos
    ? 'itms-apps://itunes.apple.com/app/id${AppUpdateConstants.iosAppId}'
    : 'market://details?id=${AppUpdateConstants.androidPackageName}';

String get _webStoreAddress => _isIos
    ? 'https://apps.apple.com/app/id${AppUpdateConstants.iosAppId}'
    : 'https://play.google.com/store/apps/details?id='
        '${AppUpdateConstants.androidPackageName}';

Future<AppUpdateProvider> _providerWith({
  required String installed,
  required Map<String, dynamic> document,
}) async {
  PackageInfo.setMockInitialValues(
    appName: 'ngy_app',
    packageName: AppUpdateConstants.androidPackageName,
    version: installed,
    buildNumber: '1',
    buildSignature: '',
  );
  final FakeFirebaseFirestore db = FakeFirebaseFirestore();
  await db
      .collection(AppUpdateConstants.collection)
      .doc(AppUpdateConstants.docId)
      .set(document);
  return AppUpdateProvider(db: db);
}

List<String> _mockStore(WidgetTester tester, {required bool opens}) {
  final List<String> launched = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_urlLauncher,
      (MethodCall call) async {
    if (call.method != 'launch') return null;
    launched.add((call.arguments as Map<Object?, Object?>)['url']! as String);
    return opens;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(_urlLauncher, null));
  return launched;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required AppUpdateProvider provider,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final GlobalKey<NavigatorState> key =
      navigatorKey ?? GlobalKey<NavigatorState>();
  return tester.pumpWidget(ChangeNotifierProvider<AppUpdateProvider>.value(
    value: provider,
    child: MaterialApp(
      navigatorKey: key,
      builder: (context, child) =>
          AppUpdateGate(navigatorKey: key, child: child!),
      home: const Scaffold(body: Text('ana sayfa')),
    ),
  ));
}

void main() {
  testWidgets(
      'denetim bitmeden açılan sayfa da zorunlu güncelleme ekranının altında '
      'kalır; zorunluluk kalkınca sayfa kaldığı yerden kullanılır',
      (tester) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    final _DelayedUpdateProvider provider = _DelayedUpdateProvider();
    final FocusNode pageFocus = FocusNode();
    addTearDown(pageFocus.dispose);
    int sent = 0;
    await _pumpApp(tester, provider: provider, navigatorKey: navigatorKey);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Focus(
          focusNode: pageFocus,
          child: ElevatedButton(
            onPressed: () => sent++,
            child: const Text('Gönder'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    pageFocus.requestFocus();
    await tester.pump();
    expect(pageFocus.hasFocus, isTrue);

    provider.checks.single.complete(AppUpdateInfo.resolve(
      data: {'minSupportedVersion': '1.0.5'},
      currentVersion: '1.0.3',
      isIos: _isIos,
    ));
    await tester.pumpAndSettle();

    expect(find.text(AppUpdateConstants.forcedTitle), findsOneWidget);
    expect(pageFocus.hasFocus, isFalse);
    await tester.tap(find.text('Gönder'), warnIfMissed: false);
    expect(sent, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(provider.checks, hasLength(2));
    provider.checks.last.complete(null);
    await tester.pumpAndSettle();

    expect(find.text(AppUpdateConstants.forcedTitle), findsNothing);
    await tester.tap(find.text('Gönder'));
    expect(sent, 1);
  }, variant: _mobile);

  testWidgets(
      'en yeni sürümün altındaki kullanıcıya güncelleme sorulur; Güncelle '
      'mağazayı açar', (tester) async {
    final AppUpdateProvider provider = await _providerWith(
      installed: '1.0.5',
      document: {
        'isCheckVersion': true,
        'latestVersion': '1.0.6',
        'minSupportedVersion': '1.0.5',
      },
    );
    final List<String> launched = _mockStore(tester, opens: true);
    await _pumpApp(tester, provider: provider);
    await tester.pumpAndSettle();

    expect(find.text(AppUpdateConstants.optionalTitle), findsOneWidget);
    expect(find.text(AppUpdateConstants.forcedTitle), findsNothing);
    await tester.tap(find.text(AppUpdateConstants.updateButton));
    await tester.pumpAndSettle();

    expect(launched, <String>[_storeAddress]);
    expect(find.text(AppUpdateConstants.optionalTitle), findsNothing);
    expect(find.text(AppUpdateConstants.storeErrorTitle), findsNothing);
  }, variant: _mobile);

  testWidgets(
      'zorunlu güncellemede mağaza açılamazsa hata, güncelleme ekranının '
      'kendisinde görünür', (tester) async {
    final AppUpdateProvider provider = await _providerWith(
      installed: '1.0.3',
      document: {'isCheckVersion': true, 'minSupportedVersion': '1.0.5'},
    );
    final List<String> launched = _mockStore(tester, opens: false);
    await _pumpApp(tester, provider: provider);
    await tester.pumpAndSettle();

    expect(find.text(AppUpdateConstants.forcedTitle), findsOneWidget);
    expect(find.text(AppUpdateConstants.storeErrorMessage), findsNothing);
    await tester.tap(find.text(AppUpdateConstants.updateButton));
    await tester.pumpAndSettle();

    expect(launched, <String>[_storeAddress, _webStoreAddress]);
    expect(find.text(AppUpdateConstants.storeErrorMessage), findsOneWidget);
  }, variant: _mobile);

  testWidgets('isCheckVersion false iken hiçbir şey gösterilmez',
      (tester) async {
    final AppUpdateProvider provider = await _providerWith(
      installed: '1.0.3',
      document: {
        'isCheckVersion': false,
        'latestVersion': '1.0.6',
        'minSupportedVersion': '1.0.5',
      },
    );
    await _pumpApp(tester, provider: provider);
    await tester.pumpAndSettle();

    expect(find.text(AppUpdateConstants.forcedTitle), findsNothing);
    expect(find.text(AppUpdateConstants.optionalTitle), findsNothing);
    expect(find.text('ana sayfa'), findsOneWidget);
  }, variant: _mobile);

  testWidgets('masaüstünde sürüm denetimi hiç yapılmaz', (tester) async {
    final _DelayedUpdateProvider provider = _DelayedUpdateProvider();
    await _pumpApp(tester, provider: provider);
    await tester.pumpAndSettle();

    expect(provider.checks, isEmpty);
    expect(find.text('ana sayfa'), findsOneWidget);
  }, variant: TargetPlatformVariant.desktop());
}
