import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ngy_app/models/meal_model.dart';
import 'package:ngy_app/models/pending_upload.dart';
import 'package:ngy_app/widgets/chat/pending_upload_bubble.dart';

void main() {
  PendingUpload upload() => PendingUpload(
        chatId: 'c1',
        image: XFile('/yok/foto.jpg'),
        meal: Meals.lunch,
        runner: (_) async {},
      );

  Future<void> pumpBubble(WidgetTester tester, PendingUpload upload) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PendingUploadBubble(
            upload: upload,
            photoSizeOf: (_) => const Size(200, 150),
            onDiscard: () {},
            onRetry: () {},
          ),
        ),
      ));

  testWidgets('yüklenirken iptal edilebilir', (tester) async {
    final PendingUpload u = upload()..markUploading();
    await pumpBubble(tester, u);

    expect(find.text('İptal').hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets(
      'dosyalar yüklendi, kayıt yazılıyor: iptal düğmesi yok, sırada sayılır',
      (tester) async {
    final PendingUpload u = upload()
      ..status.value = PendingUploadStatus.committing;
    await pumpBubble(tester, u);

    // Yeri korunur (baloncuk boyu değişmez) ama görünmez, dokunulamaz.
    expect(find.text('İptal').hitTestable(), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('Gönderiliyor…'), findsOneWidget);
    expect(u.isQueued, isTrue,
        reason: 'öğünün kalan fotoğraf hakkı hesabında sayılır');
  });
}
