import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/dialogs/add_diet_dialog.dart';
import 'package:ngy_app/models/diet_recipe.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/subs_model.dart';
import 'package:ngy_app/providers/diet_provider.dart';
import 'package:provider/provider.dart';

class _FakeFilePicker extends FilePicker {
  final List<PlatformFile> queue = <PlatformFile>[];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (queue.isEmpty) return null;
    return FilePickerResult(<PlatformFile>[queue.removeAt(0)]);
  }
}

class _FakeDietProvider extends ChangeNotifier implements DietProvider {
  final List<String> uploadedRecipeNames = <String>[];
  Map<String, dynamic>? savedSubtitles;
  String? savedRecipePdfUrl;
  bool? savedRecipesPerLine;

  @override
  Future<DietRecipe?> uploadRecipePdf({
    required String userId,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async {
    uploadedRecipeNames.add(fileName);
    return DietRecipe(
      url: 'https://example.com/$fileName',
      path: 'users/$userId/dietRecipes/1/$fileName',
      name: fileName,
    );
  }

  @override
  Future<Map<String, String>?> uploadSourceFile({
    required String userId,
    required String fileName,
    String? filePath,
    Uint8List? fileBytes,
  }) async =>
      null;

  @override
  Future<void> deleteStorageFile(String? storagePath) async {}

  @override
  Future<String?> uploadDiet({
    required String userId,
    required Map<String, dynamic> subtitles,
    String? subscriptionId,
    Map<String, dynamic>? weekendSubtitles,
    String? displayName,
    String? recipePdfUrl,
    String? recipePdfPath,
    String? recipePdfName,
    bool recipesPerLine = false,
    String? sourceFileUrl,
    String? sourceFilePath,
    String? sourceFileName,
    String? waterGoal,
    String? sportGoal,
  }) async {
    savedSubtitles = subtitles;
    savedRecipePdfUrl = recipePdfUrl;
    savedRecipesPerLine = recipesPerLine;
    return 'd1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlatformFile pdf(String name) {
  final Uint8List bytes = Uint8List.fromList('%PDF-1.4 $name'.codeUnits);
  return PlatformFile(name: name, size: bytes.length, bytes: bytes);
}

void main() {
  late _FakeFilePicker picker;
  late _FakeDietProvider diets;
  late Directory tempDir;

  setUp(() {
    picker = _FakeFilePicker();
    FilePicker.platform = picker;
    diets = _FakeDietProvider();
    tempDir = Directory.systemTemp.createTempSync('diet_dialog_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tempDir.path,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> openPreview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final Uint8List docx =
        File('test/fixtures/iki_tarifli_diyet.docx').readAsBytesSync();
    picker.queue.add(PlatformFile(
      name: 'diyet.docx',
      size: docx.length,
      bytes: docx,
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<DietProvider>.value(
        value: diets,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AddDietDialog(
                    userId: 'u1',
                    selectedSubscription: SubscriptionModel(
                      subscriptionId: 's1',
                      userId: 'u1',
                      packageName: 'Aktif Paket',
                      startDate: DateTime(2026, 11, 1),
                      totalMeetings: 4,
                      allowedPostponements: 1,
                      totalAmount: 1000,
                      meetingType: SubsMeetingType.values.first,
                    ),
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

    await tester.runAsync(() async {
      await tester.tap(find.text('Dosya Seç ve İşle'));
      for (int i = 0; i < 50 && find.text('Onayla').evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
      'aynı öğünde alt alta iki "tarifi ektedir" için iki ayrı PDF '
      'seçilir ve her biri kendi satırına kaydedilir', (tester) async {
    await openPreview(tester);

    expect(find.text('2 "tarifi ektedir" ifadesi bulundu'), findsOneWidget);
    expect(find.text('Mercimek köftesi (*tarifi ektedir)'), findsOneWidget);
    expect(find.text('Kinoa salatası (*tarifi ektedir)'), findsOneWidget);
    expect(find.text('PDF Seç'), findsNWidgets(2));

    picker.queue.add(pdf('mercimek.pdf'));
    await tester.tap(find.text('PDF Seç').first);
    await tester.pumpAndSettle();
    picker.queue.add(pdf('kinoa.pdf'));
    await tester.tap(find.text('PDF Seç'));
    await tester.pumpAndSettle();

    expect(find.text('mercimek.pdf'), findsOneWidget);
    expect(find.text('kinoa.pdf'), findsOneWidget);
    expect(find.text('PDF Değiştir'), findsNWidgets(2));

    await tester.tap(find.text('Onayla'));
    await tester.pumpAndSettle();

    expect(diets.uploadedRecipeNames, <String>['mercimek.pdf', 'kinoa.pdf']);
    expect(diets.savedRecipesPerLine, isTrue);
    expect(diets.savedRecipePdfUrl, 'https://example.com/mercimek.pdf');

    final List<dynamic> lunch =
        diets.savedSubtitles![Meals.lunch.name]['content'] as List<dynamic>;
    expect(
      <String?>[
        for (final dynamic line in lunch)
          DietRecipe.listFrom(line[DietRecipe.lineField]).isEmpty
              ? null
              : DietRecipe.listFrom(line[DietRecipe.lineField]).single?.name,
      ],
      <String?>['mercimek.pdf', null, 'kinoa.pdf'],
    );
    expect(find.text('Başarılı'), findsOneWidget);
  });

  testWidgets('PDF\'i seçilmeyen ifade varsa yüklemeden önce sorulur',
      (tester) async {
    await openPreview(tester);

    picker.queue.add(pdf('mercimek.pdf'));
    await tester.tap(find.text('PDF Seç').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Onayla'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('2 "tarifi ektedir" ifadesinden 1 tanesine'),
      findsOneWidget,
    );
    await tester.tap(find.text('Vazgeç').last);
    await tester.pumpAndSettle();

    expect(diets.uploadedRecipeNames, isEmpty);
    expect(diets.savedSubtitles, isNull);
  });
}
