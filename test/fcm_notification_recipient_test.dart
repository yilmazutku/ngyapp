import 'package:flutter_test/flutter_test.dart';
import 'package:ngy_app/providers/chat_manager_new.dart';
import 'package:ngy_app/services/fcm_service.dart';

void main() {
  const String client = 'danisan-1';
  const String previousClient = 'danisan-0';
  final String admin = ChatManager.adminIds.first;

  Map<String, dynamic> chat(String chatId) =>
      {'type': 'chat', 'chatId': chatId};
  Map<String, dynamic> chatAdmin(String chatId) =>
      {'type': 'chat_admin', 'chatId': chatId, 'senderId': chatId};

  group('uygulama açıkken sohbet bildirimi kime gösterilir', () {
    test('danışan kendi sohbetinin bildirimini görür', () {
      expect(FcmService.isMeantFor(chat(client), client), isTrue);
    });

    test(
        'cihazda önceki hesabın jetonu kaldıysa onun sohbet bildirimi '
        'gösterilmez', () {
      expect(FcmService.isMeantFor(chat(previousClient), client), isFalse);
    });

    test('danışana admin bildirimi gösterilmez', () {
      expect(FcmService.isMeantFor(chatAdmin(previousClient), client),
          isFalse);
      expect(FcmService.isMeantFor(chatAdmin(client), client), isFalse);
    });

    test('admin danışanlardan gelen bildirimleri görür', () {
      expect(FcmService.isMeantFor(chatAdmin(client), admin), isTrue);
    });

    test('admine danışana giden bildirim gösterilmez', () {
      expect(FcmService.isMeantFor(chat(client), admin), isFalse);
    });

    test('duyuru bildirimi herkese gösterilir', () {
      const Map<String, dynamic> news = {'type': 'news'};
      expect(FcmService.isMeantFor(news, client), isTrue);
      expect(FcmService.isMeantFor(news, admin), isTrue);
    });
  });
}
